import sys
import os
import asyncio

backend_dir = r"c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend"
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.database.session import SessionLocal
from app.devices.router import device_router
from app.ai.providers import RuleFallbackProvider
from app.devices.registry import device_registry

def test_cross_device():
    user_id = "test_user"

    # Register mock devices in registry
    device_registry.register_device(
        device_id="mobile_app",
        device_type="ANDROID_PHONE",
        name="Ayushman's Phone",
        platform="android",
        capabilities=["camera", "microphone", "apps", "browser"]
    )
    device_registry.register_device(
        device_id="kiko_windows_agent",
        device_type="WINDOWS_PC",
        name="Ayushman's Laptop",
        platform="windows",
        capabilities=["apps", "browser", "camera", "microphone", "files"]
    )

    test_commands = [
        ("open instagram app in my phone", "ANDROID_PHONE", "instagram"),
        ("open camera in my phone", "ANDROID_PHONE", "camera"),
        ("open WhatsApp on my phone", "ANDROID_PHONE", "whatsapp"),
        ("open Notepad in my laptop", "WINDOWS_PC", "notepad"),
        ("open chrome on my pc", "WINDOWS_PC", "chrome"),
    ]

    print("==================================================")
    print("STARTING CROSS-DEVICE ROUTING & TOOL PARAM TEST")
    print("==================================================")

    planner = RuleFallbackProvider()

    for cmd, expected_device, expected_app in test_commands:
        route = device_router.route_command(user_id=user_id, command=cmd, origin_device="BROWSER")
        print(f"\nCommand: '{cmd}'")
        print(f"  Target Device: {route.target_device} (Expected: {expected_device})")
        print(f"  Extracted App: {route.app_name} (Expected: {expected_app})")

        assert route.target_device in [expected_device, "MOBILE" if expected_device == "ANDROID_PHONE" else "LAPTOP"], f"Device mismatch for {cmd}"

        steps = planner.plan_task_sync(cmd)
        planned_app = steps[0]["parameters"].get("app_name", "").lower()
        print(f"  Planned Tool: {steps[0]['tool_name']}, App Param: '{planned_app}'")

        assert expected_app in planned_app or planned_app in expected_app, f"Param mismatch: expected {expected_app}, got {planned_app}"

    print("\n==================================================")
    print("ALL CROSS-DEVICE CONTROL TESTS PASSED SUCCESSFULLY!")
    print("==================================================")

if __name__ == "__main__":
    test_cross_device()
