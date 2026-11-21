import logging
import time
from typing import Dict, List, Any, Optional
from datetime import datetime
from fastapi import WebSocket

logger = logging.getLogger("kiko.devices")

class Device:
    def __init__(
        self,
        device_id: str,
        device_type: str, # WINDOWS_PC, ANDROID_PHONE, IOS_PHONE, BROWSER
        name: str,
        platform: str,
        capabilities: List[str],
        websocket: Optional[WebSocket] = None,
        user_id: str = "default_user",
        online: bool = True,
        connection_type: str = "wifi",
        ip_address: Optional[str] = None,
        port: Optional[int] = None,
        battery_level: str = "100%",
        battery_status: str = "Normal",
        paired: bool = True,
        authenticated: bool = True,
        agent_version: str = "1.0.0"
    ):
        self.device_id = device_id
        self.device_type = device_type.upper()
        self.name = name
        self.platform = platform.lower()
        self.capabilities = [c.lower() for c in capabilities]
        self.websocket = websocket
        self.user_id = user_id
        self.online = online
        self.connection_type = connection_type
        self.ip_address = ip_address
        self.port = port
        self.battery_level = battery_level
        self.battery_status = battery_status
        self.paired = paired
        self.authenticated = authenticated
        self.agent_version = agent_version
        self.status = "connected" if online else "offline"
        self.last_seen = datetime.utcnow()

    def update_heartbeat(self):
        self.online = True
        self.status = "connected"
        self.last_seen = datetime.utcnow()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "device_id": self.device_id,
            "device_type": self.device_type,
            "name": self.name,
            "platform": self.platform,
            "capabilities": self.capabilities,
            "user_id": self.user_id,
            "online": self.online,
            "status": self.status,
            "connection_type": self.connection_type,
            "ip_address": self.ip_address,
            "battery_level": self.battery_level,
            "battery_status": self.battery_status,
            "paired": self.paired,
            "authenticated": self.authenticated,
            "agent_version": self.agent_version,
            "last_seen": self.last_seen.isoformat()
        }

class DeviceRegistry:
    def __init__(self):
        self.devices: Dict[str, Device] = {}

    def register_device(
        self,
        device_id: str,
        device_type: str,
        name: str,
        platform: str,
        capabilities: List[str],
        websocket: Optional[WebSocket] = None,
        user_id: str = "default_user",
        connection_type: str = "wifi",
        ip_address: Optional[str] = None,
        battery_level: str = "100%",
        battery_status: str = "Normal"
    ) -> Device:
        dtype = device_type.upper()
        if "LAPTOP" in dtype or "WINDOWS" in dtype or "PC" in dtype:
            dtype = "WINDOWS_PC"
        elif "MOBILE" in dtype or "ANDROID" in dtype or "PHONE" in dtype:
            dtype = "ANDROID_PHONE"
        elif "IOS" in dtype or "IPHONE" in dtype:
            dtype = "IOS_PHONE"
        elif "WEB" in dtype or "BROWSER" in dtype:
            dtype = "BROWSER"

        dev = Device(
            device_id=device_id,
            device_type=dtype,
            name=name,
            platform=platform,
            capabilities=capabilities,
            websocket=websocket,
            user_id=user_id,
            online=True,
            connection_type=connection_type,
            ip_address=ip_address,
            battery_level=battery_level,
            battery_status=battery_status,
            paired=True,
            authenticated=True
        )
        self.devices[device_id] = dev
        logger.info(f"[REGISTRY] Registered device '{name}' ({device_id}) of type {dtype} with caps {capabilities}")
        return dev

    def update_heartbeat(self, device_id: str):
        if device_id in self.devices:
            self.devices[device_id].update_heartbeat()

    def update_status(self, device_id: str, status_dict: Dict[str, Any]):
        if device_id in self.devices:
            dev = self.devices[device_id]
            if "battery_level" in status_dict:
                dev.battery_level = str(status_dict["battery_level"])
            if "battery_status" in status_dict:
                dev.battery_status = str(status_dict["battery_status"])
            if "status" in status_dict:
                dev.status = str(status_dict["status"])
            if "ip_address" in status_dict:
                dev.ip_address = str(status_dict["ip_address"])
            dev.update_heartbeat()

    def pair_device(self, device_id: str, pairing_token: Optional[str] = None) -> bool:
        if device_id in self.devices:
            self.devices[device_id].paired = True
            self.devices[device_id].authenticated = True
            return True
        return False

    def get_device(self, device_id: str) -> Optional[Device]:
        return self.devices.get(device_id)

    def mark_offline(self, device_id: str):
        if device_id in self.devices:
            self.devices[device_id].online = False
            self.devices[device_id].status = "offline"
            self.devices[device_id].websocket = None
            logger.info(f"[REGISTRY] Device marked offline: {device_id}")

    def list_devices(self, user_id: Optional[str] = None, online_only: bool = False) -> List[Dict[str, Any]]:
        result = []
        for dev in self.devices.values():
            if user_id and dev.user_id != user_id:
                continue
            if online_only and not dev.online:
                continue
            result.append(dev.to_dict())
        return result

    def get_device_by_type(self, device_type: str, online_only: bool = True) -> Optional[Device]:
        devs = self.get_devices_by_type(device_type, online_only=online_only)
        return devs[0] if devs else None

    def get_devices_by_type(self, device_type: str, online_only: bool = True) -> List[Device]:
        dtype = device_type.upper()
        matched = []
        for dev in self.devices.values():
            if online_only and not dev.online:
                continue
            
            if dtype == "MOBILE" and dev.device_type in ["ANDROID_PHONE", "IOS_PHONE"]:
                matched.append(dev)
            elif dtype == "LAPTOP" and dev.device_type in ["WINDOWS_PC"]:
                matched.append(dev)
            elif dev.device_type == dtype:
                matched.append(dev)
        return matched

    def get_capable_devices(self, capability: str, online_only: bool = True) -> List[Device]:
        cap = capability.lower()
        matched = []
        for dev in self.devices.values():
            if online_only and not dev.online:
                continue
            if cap in dev.capabilities:
                matched.append(dev)
        return matched

device_registry = DeviceRegistry()
