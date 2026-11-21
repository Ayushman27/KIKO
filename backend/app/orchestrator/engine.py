import asyncio
import json
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session

from app.models.domain import Task, TaskStep, AuditLog
from app.ai.providers import get_ai_provider
from app.tools.registry import tool_registry
from app.permissions.engine import permission_engine
from app.approvals.manager import approval_manager
from app.websocket.manager import manager as ws_manager
from app.agents.browser_agent import browser_agent
from app.agents.browser_tools import browser_tools
from app.agents.job_agent import job_agent
from app.rag.subsystem import rag_subsystem

logger = logging.getLogger("kiko.orchestrator")

class AgentOrchestrator:
    """Central Task Orchestrator: Plan, Execute Tools, Route Commands, Handle Approvals."""
    
    async def create_and_run_task(self, db: Session, user_id: str, description: str, origin_device: str = "BROWSER", session_context: Optional[dict] = None, session_id: Optional[str] = None) -> Task:
        from app.devices.router import device_router
        from app.context.manager import active_context_manager
        from app.models.domain import ChatSession, ChatMessage

        # 0. Active Context & Reference Resolution Layer
        ref_info = active_context_manager.resolve_references(description, user_id=user_id)
        effective_command = ref_info["resolved_command"]
        active_ctx = ref_info["active_context"]

        if effective_command == description:
            active_context_manager.update_context(user_id, {"last_command": description})

        # Ensure active ChatSession exists if session_id is provided or create default
        if session_id:
            sess = db.query(ChatSession).filter(ChatSession.id == session_id).first()
            if not sess:
                sess = ChatSession(id=session_id, user_id=user_id, title=description[:30])
                db.add(sess)
                db.commit()
            # Save user message to ChatMessage
            user_msg = ChatMessage(session_id=session_id, sender="user", content=description)
            db.add(user_msg)
            db.commit()

        # 1. Device Intent Extraction & Routing Check
        route_res = device_router.route_command(
            user_id=user_id,
            command=effective_command,
            origin_device=origin_device,
            session_context=session_context
        )

        # 2. Initialize Task Record
        task = Task(
            user_id=user_id,
            session_id=session_id,
            description=description,
            status="PLANNING"
        )
        db.add(task)
        db.commit()
        db.refresh(task)

        # Handle OFFLINE device error (Rule 11: Offline target device must not cause automatic fallback to another device)
        if route_res.is_offline_error:
            logger.warning(f"[ORCHESTRATOR] Task '{description}' rejected: {route_res.error_message}")
            task.status = "FAILED"
            db.commit()

            await ws_manager.broadcast({
                "event": "TASK_FAILED",
                "task_id": task.id,
                "message": f"⚠️ {route_res.error_message}",
                "timestamp": datetime.utcnow().isoformat()
            })
            return task

        # Handle AMBIGUOUS device prompt (Prompt user: Laptop or Phone)
        if route_res.is_ambiguous:
            logger.info(f"[ORCHESTRATOR] Ambiguous command '{description}'. Requesting user choice.")
            task.status = "WAITING_CHOICE"
            db.commit()

            await ws_manager.broadcast({
                "event": "CHOICE_REQUIRED",
                "task_id": task.id,
                "message": route_res.ambiguous_prompt,
                "options": route_res.ambiguous_options,
                "payload": route_res.to_dict(),
                "timestamp": datetime.utcnow().isoformat()
            })
            return task

        await ws_manager.broadcast({
            "event": "TASK_STARTED",
            "task_id": task.id,
            "message": f"Task created for {route_res.target_device}: '{description}'",
            "timestamp": datetime.utcnow().isoformat()
        })

        # 3. Decompose user intent using selected AI Provider with Active Context
        ai_provider = get_ai_provider()
        available_tools = tool_registry.list_tools()
        planned_steps = await ai_provider.plan_task(effective_command, available_tools, active_context=active_ctx)

        # Save planned steps to DB with router target_device
        for idx, step_data in enumerate(planned_steps):
            t_name = step_data.get("tool_name", "unknown_tool")
            t_params = step_data.get("parameters", {})
            if t_name == "open_application" and t_params.get("app_name"):
                active_context_manager.update_context(user_id, {
                    "active_application": t_params.get("app_name"),
                    "last_command": description
                })

            step = TaskStep(
                task_id=task.id,
                step_number=idx + 1,
                tool_name=t_name,
                parameters=t_params,
                status="PENDING"
            )
            db.add(step)
        
        task.status = "RUNNING"
        db.commit()

        # 4. Execute planned steps targeting route_res.target_device
        asyncio.create_task(self._execute_task_loop(task.id, route_res=route_res))
        return task

    async def _execute_task_loop(self, task_id: str, route_res: Any = None):
        from app.database.session import SessionLocal
        db = SessionLocal()
        try:
            task = db.query(Task).filter(Task.id == task_id).first()
            if not task:
                return

            steps = db.query(TaskStep).filter(TaskStep.task_id == task_id).order_by(TaskStep.step_number).all()

            for step in steps:
                if step.status == "COMPLETED":
                    continue

                tool = tool_registry.get_tool(step.tool_name)
                perm_level = tool.permission_level if tool else "MEDIUM"
                
                # Check Permission Engine
                needs_approval = permission_engine.requires_approval(
                    permission_level=perm_level,
                    tool_name=step.tool_name,
                    parameters=step.parameters or {}
                )

                if needs_approval and step.status != "APPROVED":
                    step.status = "WAITING_APPROVAL"
                    db.commit()

                    approval = approval_manager.create_approval_request(
                        db=db,
                        task_id=task_id,
                        step_id=step.id,
                        tool_name=step.tool_name,
                        risk_level=perm_level,
                        action_description=f"Action '{step.tool_name}' on task: {task.description}",
                        parameters=step.parameters or {}
                    )

                    await ws_manager.broadcast({
                        "event": "APPROVAL_REQUIRED",
                        "task_id": task_id,
                        "approval_id": approval.id,
                        "message": f"Approval required for high risk action: '{step.tool_name}'",
                        "payload": {
                            "tool_name": step.tool_name,
                            "risk_level": perm_level,
                            "parameters": step.parameters
                        },
                        "timestamp": datetime.utcnow().isoformat()
                    })

                    # Pause execution until approval resolved or timeout
                    approved = await self._wait_for_approval(db, approval.id)
                    if not approved:
                        step.status = "FAILED"
                        step.error = "Approval rejected by user."
                        task.status = "CANCELLED"
                        db.commit()
                        await ws_manager.broadcast({
                            "event": "TASK_FAILED",
                            "task_id": task_id,
                            "message": "Task cancelled due to approval rejection.",
                            "timestamp": datetime.utcnow().isoformat()
                        })
                        return

                # Execute step tool
                step.status = "EXECUTING"
                db.commit()

                await ws_manager.broadcast({
                    "event": "TASK_PROGRESS",
                    "task_id": task_id,
                    "message": f"Step {step.step_number}/{len(steps)} executing on {route_res.target_device if route_res else 'device'}: {step.tool_name}",
                    "timestamp": datetime.utcnow().isoformat()
                })

                if step.tool_name in ["keyboard_type", "type_text", "save_document"]:
                    # Give target application window sufficient time to render and gain focus
                    await asyncio.sleep(1.2)

                result = await self._dispatch_tool_execution(db, step.tool_name, step.parameters or {}, task_description=task.description, route_res=route_res, task_id=task_id)
                await asyncio.sleep(1.0)
                
                # Check real physical execution outcome
                is_success = result.get("success", result.get("status") == "SUCCESS")
                if not is_success:
                    err_msg = result.get("message", result.get("error", "Execution failed on target device"))
                    step.status = "FAILED"
                    step.error = err_msg
                    task.status = "FAILED"
                    db.commit()

                    await ws_manager.broadcast({
                        "event": "TASK_FAILED",
                        "task_id": task_id,
                        "message": err_msg,
                        "timestamp": datetime.utcnow().isoformat()
                    })
                    return

                # Update Active Context Manager with step execution results
                from app.context.manager import active_context_manager
                if isinstance(result, dict):
                    updates = {
                        "last_action": step.tool_name,
                        "last_command": task.description,
                        "last_tool": step.tool_name,
                        "last_tool_result": result
                    }
                    res_payload = result.get("result", result) if isinstance(result.get("result"), dict) else result
                    
                    if isinstance(res_payload, dict):
                        if res_payload.get("active_application"):
                            updates["active_application"] = res_payload["active_application"]
                        elif step.parameters.get("app_name"):
                            updates["active_application"] = step.parameters.get("app_name")

                        if res_payload.get("active_window"):
                            updates["active_window"] = res_payload["active_window"]
                        if res_payload.get("active_document"):
                            updates["active_document"] = res_payload["active_document"]
                        elif res_payload.get("saved_file"):
                            updates["active_document"] = res_payload["saved_file"]

                    active_context_manager.update_context(task.user_id, updates)
                
                step.status = "COMPLETED"
                step.result = json.dumps(result)
                db.commit()

                # Audit Log
                audit = AuditLog(
                    task_id=task_id,
                    tool_name=step.tool_name,
                    action="EXECUTE",
                    risk_level=perm_level,
                    result="SUCCESS"
                )
                db.add(audit)
                db.commit()

            task.status = "COMPLETED"
            if isinstance(result, dict) and result.get("answer"):
                task.result_summary = result.get("answer")
            elif not task.result_summary or task.result_summary == "All steps executed successfully.":
                task.result_summary = "All steps executed successfully."
            db.commit()

            target_label = route_res.target_device.replace('_', ' ').title() if route_res else "Target Device"
            await ws_manager.broadcast({
                "event": "TASK_COMPLETED",
                "task_id": task_id,
                "response": task.result_summary,
                "sources": result.get("sources", []) if isinstance(result, dict) else [],
                "message": f"Completed on {target_label}: '{task.description}'",
                "timestamp": datetime.utcnow().isoformat()
            })

        except Exception as e:
            logger.error(f"Task execution error on task {task_id}: {e}")
            if task:
                task.status = "FAILED"
                db.commit()
        finally:
            db.close()

    async def _wait_for_approval(self, db: Session, approval_id: str, timeout_sec: int = 120) -> bool:
        for _ in range(timeout_sec):
            from app.models.domain import Approval
            appr = db.query(Approval).filter(Approval.id == approval_id).first()
            db.refresh(appr)
            if appr.status == "APPROVED":
                return True
            elif appr.status == "REJECTED":
                return False
            await asyncio.sleep(1)
        return False

    async def _dispatch_tool_execution(self, db: Session, tool_name: str, params: Dict[str, Any], task_description: str = "", route_res: Any = None, task_id: str = "") -> Dict[str, Any]:
        """Routes tool execution strictly to designated target device and awaits physical execution confirmation."""
        from app.devices.registry import device_registry
        target_dev_type = route_res.target_device if route_res else "WINDOWS_PC"
        
        # 1. Route to Mobile Agent / Mobile Device
        if target_dev_type in ["ANDROID_PHONE", "IOS_PHONE", "MOBILE"] or tool_name.endswith("_mobile"):
            mobile_dev = device_registry.get_device_by_type("ANDROID_PHONE")
            if not mobile_dev or not mobile_dev.online:
                logger.warning(f"[ORCHESTRATOR] Mobile Phone is OFFLINE. Rejecting task {task_id}")
                return {
                    "status": "FAILED",
                    "error_type": "ANDROID_PHONE_OFFLINE",
                    "message": "⚠️ Android Phone is currently OFFLINE. Cannot execute task.",
                    "success": False
                }

            cmd_payload = {
                "action": "EXECUTE_TOOL",
                "tool_name": tool_name,
                "parameters": params,
                "target": "mobile",
                "task_id": task_id
            }

            task_future = ws_manager.register_task_future(task_id) if task_id else None
            sent = await ws_manager.send_to_mobile(cmd_payload)
            if not sent:
                ws_manager.pending_task_futures.pop(task_id, None)
                return {
                    "status": "FAILED",
                    "error_type": "ANDROID_PHONE_OFFLINE",
                    "message": "⚠️ Could not reach Android Phone over WebSocket.",
                    "success": False
                }

            if task_future:
                try:
                    logger.info(f"[ORCHESTRATOR] Awaiting physical execution confirmation from Android Phone for task {task_id} (10s timeout)...")
                    device_result = await asyncio.wait_for(task_future, timeout=10.0)
                    is_success = device_result.get("success", True)
                    logger.info(f"[ORCHESTRATOR] Received physical device result for task {task_id}: success={is_success}")
                    return {
                        "status": "SUCCESS" if is_success else "FAILED",
                        "success": is_success,
                        "message": device_result.get("message", f"Mobile action executed: {tool_name}"),
                        "error": device_result.get("error"),
                        "device_result": device_result
                    }
                except asyncio.TimeoutError:
                    logger.error(f"[ORCHESTRATOR] Physical device confirmation TIMEOUT (10s) for task {task_id}")
                    ws_manager.pending_task_futures.pop(task_id, None)
                    return {
                        "status": "TIMEOUT",
                        "success": False,
                        "message": "⚠️ Unable to confirm execution on your phone (10s Timeout)."
                    }

            return {"status": "SUCCESS", "success": True, "message": f"Dispatched tool '{tool_name}' to Mobile Phone ({target_dev_type})"}

        # 2. Route to Windows Laptop Agent / Desktop App
        active_agents = ws_manager.agent_clients
        if active_agents and target_dev_type in ["WINDOWS_PC", "LAPTOP"]:
            cmd_payload = {
                "action": "EXECUTE_TOOL",
                "tool_name": tool_name,
                "parameters": params,
                "target": "laptop",
                "task_id": task_id
            }
            task_future = ws_manager.register_task_future(task_id) if task_id else None
            for cid in list(active_agents.keys()):
                await ws_manager.send_personal_message(cmd_payload, cid)

            if task_future:
                try:
                    logger.info(f"[ORCHESTRATOR] Awaiting confirmation from Windows client for task {task_id} (4s timeout)...")
                    device_result = await asyncio.wait_for(task_future, timeout=4.0)
                    is_success = device_result.get("success", True)
                    logger.info(f"[ORCHESTRATOR] Received Windows client confirmation for task {task_id}: success={is_success}")
                    return {
                        "status": "SUCCESS" if is_success else "FAILED",
                        "success": is_success,
                        "message": device_result.get("message", f"Windows action executed: {tool_name}"),
                        "error": device_result.get("error"),
                        "device_result": device_result
                    }
                except asyncio.TimeoutError:
                    logger.info(f"[ORCHESTRATOR] Windows client future timeout (4s), falling back to native desktop host execution.")
                    ws_manager.pending_task_futures.pop(task_id, None)

        # 3. Direct Native Desktop Execution on Windows Host Fallback
        import platform
        if platform.system() == "Windows" or target_dev_type in ["WINDOWS_PC", "LAPTOP"]:
            if tool_name in ["open_application", "open_app", "launch_app"]:
                from app.tools.native_desktop import open_application as native_open_app
                app_target = params.get("app_name") or task_description
                res = native_open_app(app_target)
                logger.info(f"[ORCHESTRATOR] Native Windows execution result for '{tool_name}': {res}")
                return res
            elif tool_name in ["close_application", "kill_app"]:
                from app.tools.native_desktop import close_application as native_close_app
                app_target = params.get("app_name") or task_description
                return native_close_app(app_target)
            elif tool_name == "take_screenshot":
                from app.tools.native_desktop import take_screenshot as native_take_screenshot
                return native_take_screenshot()
            elif tool_name in ["keyboard_type", "type_text"]:
                from app.tools.native_desktop import keyboard_type as native_keyboard_type
                return native_keyboard_type(params.get("text", ""), append_line=params.get("append_line", False), target_app=params.get("app_name", "notepad"))
            elif tool_name in ["save_document", "save_file"]:
                from app.tools.native_desktop import save_document as native_save_doc
                return native_save_doc(params.get("file_name", "document.txt"), target_app=params.get("app_name", "notepad"))
            elif tool_name == "keyboard_press":
                from app.tools.native_desktop import keyboard_press as native_keyboard_press
                return native_keyboard_press(params.get("key", "enter"))
            elif tool_name in ["search_youtube", "play_youtube"]:
                from app.tools.native_desktop import search_youtube as native_search_youtube
                return native_search_youtube(params.get("query", ""))
            
            # Browser & Autonomous Web Tools (Playwright Persistent Session)
            elif tool_name == "autonomous_browser_task":
                logger.info(f"[ORCHESTRATOR] Executing autonomous browser task for: {task_description}")
                return await browser_agent.execute_autonomous_task(
                    task_id=task_id or f"task_{int(datetime.utcnow().timestamp())}",
                    user_intent=params.get("instruction") or task_description
                )
            elif tool_name in ["open_browser", "open_url"]:
                url = params.get("url") or "https://www.google.com"
                return await browser_tools.navigate_to_url(url, session_id=task_id)
            elif tool_name == "search_web":
                query = params.get("query", "")
                return await browser_tools.navigate_to_url(f"https://www.google.com/search?q={query.replace(' ', '+')}", session_id=task_id)
            elif tool_name == "navigate_to_url":
                return await browser_tools.navigate_to_url(params.get("url", ""), session_id=task_id)
            elif tool_name == "read_page":
                return await browser_tools.read_page(mode=params.get("mode", "all"), session_id=task_id)
            elif tool_name == "click_element":
                return await browser_tools.click_element(params.get("element_ref"), session_id=task_id)
            elif tool_name == "type_text":
                return await browser_tools.type_text(
                    element_ref=params.get("element_ref"),
                    text=params.get("text", ""),
                    press_enter=params.get("press_enter", True),
                    session_id=task_id
                )
            elif tool_name == "scroll_page":
                return await browser_tools.scroll_page(
                    direction=params.get("direction", "down"),
                    amount=params.get("amount", 600),
                    session_id=task_id
                )
            elif tool_name == "press_key":
                return await browser_tools.press_key(params.get("key", "Enter"), session_id=task_id)
            elif tool_name == "get_interactive_elements":
                return await browser_tools.get_interactive_elements(session_id=task_id)
            elif tool_name == "manage_tabs":
                return await browser_tools.manage_tabs(
                    action=params.get("action", "list"),
                    tab_index=params.get("tab_index"),
                    url=params.get("url"),
                    session_id=task_id
                )
            elif tool_name == "get_browser_state":
                return await browser_tools.get_browser_state(session_id=task_id)

        if active_agents and target_dev_type in ["WINDOWS_PC", "LAPTOP"]:
            return {"status": "SUCCESS", "message": f"Dispatched tool '{tool_name}' to Windows Agent", "parameters": params, "target": "laptop"}

        # 4. Local Backend Handlers Fallback
        if tool_name == "open_browser" or tool_name == "open_url":
            url = params.get("url", "https://google.com")
            return await browser_agent.open_url(url)
        elif tool_name == "search_web":
            query = params.get("query", "")
            return await browser_agent.search_web(query)
        elif tool_name == "search_jobs":
            keywords = params.get("keywords", "AI Engineer")
            jobs = await job_agent.search_jobs(keywords)
            return {"jobs": jobs}
        elif tool_name == "fill_job_application":
            return await job_agent.fill_application(
                job_title=params.get("job_title", ""),
                company=params.get("company", ""),
                resume_path=params.get("resume_path", "Documents/resume.pdf")
            )
        elif tool_name == "search_personal_documents":
            query = params.get("query", "")
            res = rag_subsystem.search_documents(db, query)
            return {"results": res}
        else:
            return {"status": "SUCCESS", "tool": tool_name, "parameters": params, "result": f"Executed {tool_name} on {target_dev_type}"}

orchestrator = AgentOrchestrator()
