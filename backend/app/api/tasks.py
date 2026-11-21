from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from app.database.session import get_db
from app.models.domain import Task, TaskStep
from app.orchestrator.engine import orchestrator
from app.core.config import settings

router = APIRouter(prefix="/tasks", tags=["Tasks"])

class TaskCreateRequest(BaseModel):
    description: Optional[str] = None
    prompt: Optional[str] = None
    command: Optional[str] = None
    user_id: Optional[str] = "dev_user_1"
    origin_device: Optional[str] = "BROWSER"
    session_id: Optional[str] = None
    mode: Optional[str] = None  # 'alpha' | 'g_mode' | None (use DEFAULT_AGENT_MODE)

@router.post("")
async def create_task(req: TaskCreateRequest, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    task_desc = (req.description or req.prompt or req.command or "").strip()
    if not task_desc:
        raise HTTPException(status_code=422, detail="Field 'description', 'prompt', or 'command' is required.")

    # Determine effective agent mode
    effective_mode = (req.mode or settings.DEFAULT_AGENT_MODE or "alpha").lower()

    # ── G Mode: route to G Mode orchestrator ──────────────────────────────────
    if effective_mode == "g_mode":
        from app.orchestrator.g_orchestrator import g_orchestrator
        exp = g_orchestrator.create_experiment(
            db=db,
            objective=task_desc,
            mode="research"
        )
        background_tasks.add_task(g_orchestrator.start_experiment, exp.id)
        return {
            "id": exp.id,
            "mode": "g_mode",
            "description": task_desc,
            "status": exp.status,
            "experiment_id": exp.id,
            "workspace_path": exp.workspace_path,
            "response": "G Mode experiment started.",
            "message": "G Mode experiment started. Monitor via /api/v1/gmode/experiments or WebSocket."
        }

    # ── Alpha Mode: use existing orchestrator pipeline ────────────────────────
    session_id = req.session_id
    if not session_id:
        from app.models.domain import ChatSession
        sess = ChatSession(user_id=req.user_id, title=task_desc[:30])
        db.add(sess)
        db.commit()
        db.refresh(sess)
        session_id = sess.id

    import re
    # Normalize common speech recognition cuts (e.g. "for scout op in youtube" -> "search for scout op in youtube")
    if re.search(r'\b(in|on)\s+youtube\b', task_desc, re.IGNORECASE) and not re.search(r'^(search|play|find|open)\b', task_desc, re.IGNORECASE):
        task_desc = f"search {task_desc}"

    action_keywords = [
        "open", "launch", "create", "make", "delete", "remove", "search", "find",
        "screenshot", "type", "write", "play", "run", "save", "add", "append",
        "close", "restart", "shutdown", "install", "kill", "send", "call", "sms",
        "youtube", "google", "spotify", "notepad", "calculator", "calc", "paint",
        "chrome", "browser", "camera", "whatsapp", "settings", "terminal", "powershell",
        "joke", "poem", "note"
    ]
    is_action = any(re.search(r'\b' + kw + r'\b', task_desc, re.IGNORECASE) for kw in action_keywords)

    if not is_action:
        # Conversational greeting or query (e.g. "hi", "how are you", "who are you")
        from app.ai.providers import get_ai_provider
        from app.models.domain import ChatMessage
        ai_provider = get_ai_provider()
        reply_text = await ai_provider.generate_response(
            prompt=task_desc,
            system_prompt="You are KIKO, an advanced personal AI assistant. Be concise, friendly, and conversational in 1-2 sentences."
        )
        if not reply_text or not reply_text.strip():
            reply_text = "Hi there! How can I help you today?"

        user_msg = ChatMessage(session_id=session_id, sender="user", content=task_desc)
        bot_msg = ChatMessage(session_id=session_id, sender="kiko", content=reply_text)
        db.add(user_msg)
        db.add(bot_msg)
        db.commit()

        return {
            "id": f"chat_{session_id}",
            "mode": "alpha",
            "session_id": session_id,
            "description": task_desc,
            "status": "COMPLETED",
            "response": reply_text,
            "message": reply_text,
            "steps": []
        }

    task = await orchestrator.create_and_run_task(
        db,
        user_id=req.user_id,
        description=task_desc,
        origin_device=req.origin_device,
        session_id=session_id
    )
    steps = db.query(TaskStep).filter(TaskStep.task_id == task.id).order_by(TaskStep.step_number).all()

    from app.devices.router import device_router
    route_res = device_router.route_command(user_id=req.user_id, command=task_desc)
    is_mobile_target = route_res.target_device in ["ANDROID_PHONE", "IOS_PHONE", "MOBILE"]

    action_summary = task.result_summary or f"Executing task: '{task_desc}'"
    return {
        "id": task.id,
        "mode": "alpha",
        "session_id": session_id,
        "description": task.description,
        "status": task.status,
        "response": action_summary,
        "message": action_summary,
        "created_at": task.created_at.isoformat(),
        "steps": [
            {
                "tool_name": s.tool_name,
                "parameters": s.parameters,
                "target_device": "mobile" if is_mobile_target or "mobile" in s.tool_name else "laptop"
            }
            for s in steps
        ]
    }

@router.get("")
def list_tasks(db: Session = Depends(get_db)):
    tasks = db.query(Task).order_by(Task.created_at.desc()).all()
    res = []
    for t in tasks:
        steps = db.query(TaskStep).filter(TaskStep.task_id == t.id).order_by(TaskStep.step_number).all()
        res.append({
            "id": t.id,
            "description": t.description,
            "status": t.status,
            "priority": t.priority,
            "created_at": t.created_at.isoformat(),
            "steps": [
                {
                    "id": s.id,
                    "step_number": s.step_number,
                    "tool_name": s.tool_name,
                    "status": s.status,
                    "parameters": s.parameters,
                    "result": s.result,
                    "error": s.error
                }
                for s in steps
            ]
        })
    return res

@router.get("/{task_id}")
def get_task(task_id: str, db: Session = Depends(get_db)):
    t = db.query(Task).filter(Task.id == task_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Task not found")
    steps = db.query(TaskStep).filter(TaskStep.task_id == t.id).order_by(TaskStep.step_number).all()
    return {
        "id": t.id,
        "description": t.description,
        "status": t.status,
        "priority": t.priority,
        "created_at": t.created_at.isoformat(),
        "result_summary": t.result_summary,
        "steps": [
            {
                "id": s.id,
                "step_number": s.step_number,
                "tool_name": s.tool_name,
                "status": s.status,
                "parameters": s.parameters,
                "result": s.result,
                "error": s.error
            }
            for s in steps
        ]
    }

@router.post("/{task_id}/cancel")
async def cancel_task(task_id: str, db: Session = Depends(get_db)):
    t = db.query(Task).filter(Task.id == task_id).first()
    if not t:
        raise HTTPException(status_code=404, detail="Task not found")
    t.status = "CANCELLED"
    db.commit()
    from app.agents.browser_agent import browser_agent
    from app.websocket.manager import manager as ws_manager
    from datetime import datetime
    browser_agent.cancel_task(task_id)
    await ws_manager.broadcast({
        "event": "TASK_FAILED",
        "task_id": task_id,
        "message": "Task cancelled by user.",
        "timestamp": datetime.utcnow().isoformat()
    })
    return {"status": "SUCCESS", "message": f"Task {task_id} cancelled."}
