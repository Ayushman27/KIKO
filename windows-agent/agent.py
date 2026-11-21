import asyncio
import json
import logging
import sys
import os
import socket

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import WS_URL, DEVICE_NAME, DEVICE_ID
from tools import filesystem, desktop, media

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("windows.agent")

TOOL_MAP = {
    "search_files": filesystem.search_files,
    "read_file": filesystem.read_file,
    "create_folder": filesystem.create_folder,
    "create_file": filesystem.create_file,
    "move_file": filesystem.move_file,
    "copy_file": filesystem.copy_file,
    "delete_file": filesystem.delete_file,
    "open_application": desktop.open_application,
    "close_application": desktop.close_application,
    "keyboard_type": desktop.keyboard_type,
    "keyboard_press": desktop.keyboard_press,
    "save_document": desktop.save_document,
    "take_screenshot": desktop.take_screenshot,
    "get_battery_status": desktop.get_battery_status,
    "battery_info": desktop.get_battery_status,
    "sync_clipboard": desktop.sync_clipboard,
    "search_youtube": media.search_youtube,
    "open_browser": media.open_browser,
    "open_url": media.open_browser,
    "search_web": media.open_browser
}

async def execute_tool(tool_name: str, parameters: dict) -> dict:
    logger.info(f"Executing tool: {tool_name} with params: {parameters}")
    fn = TOOL_MAP.get(tool_name)
    if not fn:
        return {"error": f"Tool '{tool_name}' not supported on Windows Agent."}
    try:
        res = fn(**parameters)
        return res
    except Exception as e:
        logger.error(f"Error executing tool {tool_name}: {e}")
        return {"error": str(e)}

async def run_udp_discovery_responder():
    """Listens on UDP port 53535 for KIKO_DISCOVER_PING and responds with KIKO_DISCOVER_PONG."""
    DISCOVERY_PORT = 53535
    loop = asyncio.get_running_loop()

    class UDPResponderProtocol(asyncio.DatagramProtocol):
        def __init__(self):
            super().__init__()
            self.transport = None

        def connection_made(self, transport):
            self.transport = transport

        def datagram_received(self, data: bytes, addr: tuple):
            try:
                msg = json.loads(data.decode("utf-8"))
                if msg.get("magic") == "KIKO_DISCOVER_PING":
                    bat = desktop.get_battery_status()
                    pong = json.dumps({
                        "magic": "KIKO_DISCOVER_PONG",
                        "device_id": DEVICE_ID,
                        "name": DEVICE_NAME,
                        "device_type": "WINDOWS_PC",
                        "platform": "windows",
                        "connection_type": "wifi",
                        "battery_level": bat.get("battery_level", "100%"),
                        "battery_status": bat.get("battery_status", "Plugged In"),
                        "capabilities": list(TOOL_MAP.keys())
                    }).encode("utf-8")
                    self.transport.sendto(pong, addr)
            except Exception:
                pass

    try:
        await loop.create_datagram_endpoint(
            UDPResponderProtocol,
            local_addr=('0.0.0.0', DISCOVERY_PORT)
        )
        logger.info(f"[DISCOVERY] Windows Agent UDP discovery responder active on port {DISCOVERY_PORT}")
    except Exception as e:
        logger.warning(f"[DISCOVERY] Could not bind UDP discovery port {DISCOVERY_PORT}: {e}")

async def run_agent():
    import websockets
    ws_endpoint = f"{WS_URL}/{DEVICE_ID}"
    logger.info(f"Starting KIKO Windows Agent daemon: '{DEVICE_NAME}' ({DEVICE_ID})")
    logger.info(f"Connecting to backend WebSocket endpoint: {ws_endpoint}")

    # Start UDP discovery listener
    asyncio.create_task(run_udp_discovery_responder())

    while True:
        try:
            async with websockets.connect(ws_endpoint) as websocket:
                logger.info("Successfully connected to KIKO Backend WebSocket server.")
                
                bat = desktop.get_battery_status()
                init_msg = {
                    "event": "DEVICE_CONNECTED",
                    "device_id": DEVICE_ID,
                    "name": DEVICE_NAME,
                    "device_type": "WINDOWS_PC",
                    "platform": "windows",
                    "status": "ONLINE",
                    "connection_type": "wifi",
                    "battery_level": bat.get("battery_level", "100%"),
                    "battery_status": bat.get("battery_status", "Plugged In"),
                    "capabilities": ["open_app", "file_operations", "browser_control", "clipboard_sync", "battery_status", "media_control"]
                }
                await websocket.send(json.dumps(init_msg))

                while True:
                    raw_msg = await websocket.recv()
                    data = json.loads(raw_msg)
                    logger.info(f"Received command from backend: {data}")

                    if data.get("action") == "EXECUTE_TOOL":
                        target = data.get("target")
                        t_name = data.get("tool_name", "")
                        if target == "mobile" or t_name.endswith("_mobile") or "mobile" in t_name:
                            logger.info(f"Ignoring tool execution '{t_name}' targeted for mobile device.")
                            continue
                        
                        t_params = data.get("parameters", {})
                        result = await execute_tool(t_name, t_params)

                        reply = {
                            "event": "TOOL_RESULT",
                            "device_id": DEVICE_ID,
                            "tool_name": t_name,
                            "result": result
                        }
                        await websocket.send(json.dumps(reply))

        except Exception as e:
            logger.warning(f"Connection lost or backend unavailable ({e}). Retrying in 5 seconds...")
            await asyncio.sleep(5)

if __name__ == "__main__":
    asyncio.run(run_agent())
