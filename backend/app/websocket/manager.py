import json
import logging
from typing import Dict, List, Any, Optional
from fastapi import WebSocket
from datetime import datetime
from app.devices.registry import device_registry

logger = logging.getLogger("kiko.websocket")

import asyncio

class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.web_clients: List[WebSocket] = []
        self.mobile_clients: List[WebSocket] = []
        self.agent_clients: Dict[str, WebSocket] = {}
        self.pending_task_futures: Dict[str, asyncio.Future] = {}

    def register_task_future(self, task_id: str) -> asyncio.Future:
        loop = asyncio.get_event_loop()
        fut = loop.create_future()
        self.pending_task_futures[task_id] = fut
        return fut

    def resolve_task_future(self, task_id: str, result_data: dict):
        if task_id in self.pending_task_futures:
            fut = self.pending_task_futures.pop(task_id)
            if not fut.done():
                fut.set_result(result_data)

    async def connect_client(self, websocket: WebSocket, client_id: str, client_type: str = "web", capabilities: Optional[List[str]] = None):
        await websocket.accept()
        self.active_connections[client_id] = websocket
        
        is_windows = "windows" in client_id.lower() or "desktop" in client_id.lower()
        is_mobile = "mobile" in client_id.lower() or client_type.lower() in ["mobile", "android", "ios"]
        if is_windows:
            dtype = "WINDOWS_PC"
            caps = capabilities or ["apps", "browser", "camera", "microphone", "files"]
            name = "Ayushman's Windows PC"
            self.agent_clients[client_id] = websocket
        elif is_mobile:
            if websocket not in self.mobile_clients:
                self.mobile_clients.append(websocket)
            dtype = "ANDROID_PHONE"
            caps = capabilities or ["camera", "microphone", "apps", "browser", "notifications"]
            name = "Ayushman's Phone"
        else:
            if websocket not in self.web_clients:
                self.web_clients.append(websocket)
            dtype = "BROWSER"
            caps = capabilities or ["microphone", "browser"]
            name = "Web Client"

        device_registry.register_device(
            device_id=client_id,
            device_type=dtype,
            name=name,
            platform="windows" if is_windows else ("android" if is_mobile else "web"),
            capabilities=caps,
            websocket=websocket
        )

        logger.info(f"[WS] Client connected: {client_id} (type: {dtype})")
        await self.broadcast_device_list()

    async def connect_agent(self, websocket: WebSocket, device_id: str, capabilities: Optional[List[str]] = None):
        await websocket.accept()
        self.agent_clients[device_id] = websocket
        self.active_connections[device_id] = websocket
        
        caps = capabilities or ["apps", "browser", "camera", "microphone", "files"]
        device_registry.register_device(
            device_id=device_id,
            device_type="WINDOWS_PC",
            name="Ayushman's Laptop",
            platform="windows",
            capabilities=caps,
            websocket=websocket
        )

        logger.info(f"[WS] Windows Agent connected: {device_id}")
        await self.broadcast_device_list()

    def disconnect(self, client_id: str):
        if client_id in self.active_connections:
            ws = self.active_connections.pop(client_id)
            if ws in self.web_clients:
                self.web_clients.remove(ws)
            if ws in self.mobile_clients:
                self.mobile_clients.remove(ws)
            if client_id in self.agent_clients:
                del self.agent_clients[client_id]
            device_registry.mark_offline(client_id)
            logger.info(f"[WS] Client disconnected: {client_id}")

    async def send_personal_message(self, message: dict, client_id: str):
        if client_id in self.active_connections:
            try:
                await self.active_connections[client_id].send_text(json.dumps(message))
            except Exception as e:
                logger.error(f"[WS] Error sending message to {client_id}: {e}")

    async def send_to_mobile(self, message: dict) -> bool:
        payload = json.dumps(message)
        sent = False
        for client_id, connection in list(self.active_connections.items()):
            # Send strictly to mobile clients and exclude web browser connections
            is_web = connection in self.web_clients or "web" in client_id.lower() or "browser" in client_id.lower()
            if not is_web and (connection in self.mobile_clients or "mobile" in client_id.lower()):
                try:
                    await connection.send_text(payload)
                    sent = True
                    logger.info(f"[WS] Successfully sent mobile command to {client_id}")
                except Exception as e:
                    logger.error(f"[WS] Error sending to mobile client {client_id}: {e}")
        if not sent:
            logger.warning(f"[WS] No mobile WebSocket client connected to receive: {message.get('tool_name')}")
        return sent

    async def broadcast(self, message: dict):
        payload = json.dumps(message)
        for client_id, connection in list(self.active_connections.items()):
            try:
                await connection.send_text(payload)
            except Exception as e:
                logger.error(f"[WS] Broadcast error to {client_id}: {e}")

    async def broadcast_device_list(self):
        devices = device_registry.list_devices(online_only=False)
        await self.broadcast({
            "event": "DEVICE_LIST_UPDATED",
            "devices": devices,
            "timestamp": datetime.utcnow().isoformat()
        })

manager = ConnectionManager()
