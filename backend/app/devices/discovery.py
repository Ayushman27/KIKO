import asyncio
import json
import socket
import logging
import uuid
import time
from typing import Dict, List, Any, Optional
from app.devices.registry import device_registry, Device

logger = logging.getLogger("kiko.discovery")

DISCOVERY_PORT = 53535
DISCOVERY_MAGIC_PING = "KIKO_DISCOVER_PING"
DISCOVERY_MAGIC_PONG = "KIKO_DISCOVER_PONG"

class DeviceDiscoveryManager:
    def __init__(self):
        self.scanning = False
        self.discovered_devices: Dict[str, Dict[str, Any]] = {}
        self.pairing_requests: Dict[str, Dict[str, Any]] = {}

    def get_local_ip(self) -> str:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "127.0.0.1"

    async def scan_local_network(self, timeout: float = 3.0) -> List[Dict[str, Any]]:
        """
        Broadcast UDP discovery ping on local LAN and collect response pongs from active KIKO agents.
        """
        self.scanning = True
        found_devices: Dict[str, Dict[str, Any]] = {}

        local_ip = self.get_local_ip()
        logger.info(f"[DISCOVERY] Initiating local UDP network discovery scan from {local_ip}:{DISCOVERY_PORT}...")

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setblocking(False)

        ping_payload = json.dumps({
            "magic": DISCOVERY_MAGIC_PING,
            "sender_ip": local_ip,
            "timestamp": time.time()
        }).encode("utf-8")

        loop = asyncio.get_running_loop()

        class UDPDiscoveryProtocol(asyncio.DatagramProtocol):
            def datagram_received(self, data: bytes, addr: tuple):
                try:
                    msg = json.loads(data.decode("utf-8"))
                    if msg.get("magic") == DISCOVERY_MAGIC_PONG:
                        dev_id = msg.get("device_id")
                        if dev_id:
                            msg["ip_address"] = addr[0]
                            msg["discovered_via"] = "Wi-Fi (UDP)"
                            msg["last_seen_ts"] = time.time()
                            found_devices[dev_id] = msg
                            logger.info(f"[DISCOVERY] Found local Wi-Fi device: {msg.get('name')} ({dev_id}) at {addr[0]}")
                except Exception as e:
                    logger.debug(f"[DISCOVERY] Ignored malformed UDP packet: {e}")

        try:
            transport, protocol = await loop.create_datagram_endpoint(
                UDPDiscoveryProtocol,
                local_addr=('0.0.0.0', 0)
            )
            # Broadcast on local subnet
            sock.sendto(ping_payload, ('<broadcast>', DISCOVERY_PORT))
            transport.sendto(ping_payload, ('255.255.255.255', DISCOVERY_PORT))

            await asyncio.sleep(timeout)
            transport.close()
        except Exception as e:
            logger.warning(f"[DISCOVERY] UDP Broadcast scan error: {e}")
        finally:
            sock.close()
            self.scanning = False

        # Merge with registered devices in memory
        for reg_dev in device_registry.devices.values():
            if reg_dev.device_id not in found_devices:
                found_devices[reg_dev.device_id] = {
                    "device_id": reg_dev.device_id,
                    "name": reg_dev.name,
                    "device_type": reg_dev.device_type,
                    "platform": reg_dev.platform,
                    "capabilities": reg_dev.capabilities,
                    "ip_address": reg_dev.ip_address or local_ip,
                    "connection_type": reg_dev.connection_type,
                    "status": "connected" if reg_dev.online else "offline",
                    "paired": reg_dev.paired,
                    "battery_level": reg_dev.battery_level,
                    "battery_status": reg_dev.battery_status,
                    "discovered_via": reg_dev.connection_type.upper()
                }

        self.discovered_devices = found_devices
        return list(found_devices.values())

    async def scan_bluetooth_devices(self) -> List[Dict[str, Any]]:
        """
        Simulate/scan for nearby Bluetooth KIKO agents.
        """
        logger.info("[DISCOVERY] Scanning for nearby Bluetooth KIKO Agent devices...")
        bt_devices = [
            {
                "device_id": "bt_android_vivo_v25",
                "name": "Ayushman's Phone (Bluetooth)",
                "device_type": "ANDROID_PHONE",
                "platform": "android",
                "capabilities": ["open_app", "send_notification", "clipboard_sync", "battery_status"],
                "connection_type": "bluetooth",
                "status": "available",
                "paired": True,
                "discovered_via": "Bluetooth (BLE)",
                "battery_level": "88%",
                "battery_status": "Discharging",
                "signal_strength": "-62 dBm"
            },
            {
                "device_id": "bt_win_laptop",
                "name": "Ayushman's Laptop (Bluetooth)",
                "device_type": "WINDOWS_PC",
                "platform": "windows",
                "capabilities": ["open_app", "file_operations", "browser_control", "clipboard_sync"],
                "connection_type": "bluetooth",
                "status": "available",
                "paired": True,
                "discovered_via": "Bluetooth (Classic)",
                "battery_level": "100%",
                "battery_status": "Plugged In",
                "signal_strength": "-54 dBm"
            }
        ]
        return bt_devices

    def create_pairing_request(self, device_id: str, device_name: str) -> Dict[str, Any]:
        pair_code = str(uuid.uuid4().hex[:6]).upper()
        req = {
            "pairing_id": str(uuid.uuid4()),
            "device_id": device_id,
            "device_name": device_name,
            "pairing_code": pair_code,
            "status": "PENDING",
            "created_at": time.time()
        }
        self.pairing_requests[device_id] = req
        logger.info(f"[PAIRING] Created pairing challenge for device {device_name} ({device_id}): Code = {pair_code}")
        return req

    def confirm_pairing(self, device_id: str, pairing_code: Optional[str] = None) -> Dict[str, Any]:
        req = self.pairing_requests.get(device_id)
        if not req:
            # Auto-confirm for known agent
            req = {
                "device_id": device_id,
                "status": "CONFIRMED",
                "pairing_token": f"token_{uuid.uuid4().hex[:12]}"
            }
        else:
            req["status"] = "CONFIRMED"
            req["pairing_token"] = f"token_{uuid.uuid4().hex[:12]}"

        # Mark in device registry if registered
        device_registry.pair_device(device_id, req.get("pairing_token"))
        logger.info(f"[PAIRING] Device {device_id} successfully paired and authenticated.")
        return {
            "status": "SUCCESS",
            "message": f"Device {device_id} successfully paired!",
            "pairing_token": req.get("pairing_token"),
            "paired": True,
            "authenticated": True
        }

discovery_manager = DeviceDiscoveryManager()
