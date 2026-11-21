import logging
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.database.session import engine, Base
from app.websocket.manager import manager as ws_manager
from app.api import auth, tasks, approvals, devices, memory, rag, tools, settings as settings_api, voice as voice_api, sessions
from app.api import ollama_health, gmode as gmode_api
from app.devices.registry import device_registry
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("kiko.main")

# Auto-create tables for SQLite / DB
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Routers
app.include_router(auth.router, prefix=settings.API_V1_STR)
app.include_router(tasks.router, prefix=settings.API_V1_STR)
app.include_router(sessions.router, prefix=settings.API_V1_STR)
app.include_router(approvals.router, prefix=settings.API_V1_STR)
app.include_router(devices.router, prefix=settings.API_V1_STR)
app.include_router(memory.router, prefix=settings.API_V1_STR)
app.include_router(rag.router, prefix=settings.API_V1_STR)
app.include_router(tools.router, prefix=settings.API_V1_STR)
app.include_router(settings_api.router, prefix=settings.API_V1_STR)
app.include_router(voice_api.router, prefix=settings.API_V1_STR)
app.include_router(ollama_health.router, prefix=settings.API_V1_STR)
app.include_router(gmode_api.router, prefix=settings.API_V1_STR)

@app.get("/")
def root():
    return {"name": "KIKO Personal Agent API", "version": settings.VERSION, "docs": "/docs"}

@app.websocket("/ws/client/{client_id}")
async def websocket_client_endpoint(websocket: WebSocket, client_id: str):
    await ws_manager.connect_client(websocket, client_id)
    try:
        while True:
            data = await websocket.receive_text()
            logger.info(f"Received client message from {client_id}: {data}")
            try:
                msg = json.loads(data)
                if isinstance(msg, dict):
                    event = msg.get("event")
                    if event == "DEVICE_CONNECTED":
                        is_win_client = ("windows" in client_id.lower() or "desktop" in client_id.lower())
                        if is_win_client:
                            dev_type = "WINDOWS_PC"
                            plat = "windows"
                            dev_name = "Ayushman's Windows PC"
                            caps = ["apps", "browser", "camera", "microphone", "files", "open_app"]
                        else:
                            dev_type = msg.get("device_type", "ANDROID_PHONE" if "mobile" in client_id.lower() else "BROWSER")
                            plat = msg.get("platform", "android" if "mobile" in client_id.lower() else "web")
                            dev_name = msg.get("name", client_id)
                            caps = msg.get("capabilities", [])

                        device_registry.register_device(
                            device_id=client_id,
                            device_type=dev_type,
                            name=dev_name,
                            platform=plat,
                            capabilities=caps,
                            websocket=websocket
                        )
                        await ws_manager.broadcast_device_list()
                    elif event == "HEARTBEAT":
                        device_registry.touch(client_id)
                        await websocket.send_text(json.dumps({
                            "event": "HEARTBEAT_ACK",
                            "timestamp": datetime.utcnow().isoformat()
                        }))
                    elif event in ["ACTION_STATUS", "ACTION_RESULT"]:
                        task_id = msg.get("task_id")
                        if task_id and event == "ACTION_RESULT":
                            ws_manager.resolve_task_future(task_id, msg)
                        success = msg.get("success", True)
                        app_name = msg.get("app", msg.get("tool_name", "action"))
                        msg_text = msg.get("message", f"Native mobile execution for {app_name}: {'SUCCESS' if success else 'FAILED'}")
                        await ws_manager.broadcast({
                            "event": "TASK_PROGRESS" if event == "ACTION_STATUS" else ("TASK_COMPLETED" if success else "TASK_FAILED"),
                            "task_id": task_id,
                            "message": msg_text,
                            "details": msg
                        })
            except Exception as pe:
                logger.debug(f"Client payload parse info: {pe}")
    except WebSocketDisconnect:
        ws_manager.disconnect(client_id)

@app.websocket("/ws/agent/{device_id}")
async def websocket_agent_endpoint(websocket: WebSocket, device_id: str):
    await ws_manager.connect_agent(websocket, device_id)
    try:
        while True:
            data = await websocket.receive_text()
            logger.info(f"Received agent status from {device_id}: {data}")
            try:
                msg = json.loads(data)
                task_id = msg.get("task_id")
                event = msg.get("event")
                if task_id and event in ["TOOL_RESULT", "ACTION_RESULT"]:
                    ws_manager.resolve_task_future(task_id, msg)
            except Exception:
                pass
    except WebSocketDisconnect:
        ws_manager.disconnect(device_id)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
