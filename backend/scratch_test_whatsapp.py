import sys
import os

backend_dir = r"c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend"
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.context.manager import active_context_manager
from app.ai.providers import RuleFallbackProvider

user_id = "voice_user"

# 1. Simulate active context having Notepad from previous task
active_context_manager.update_context(user_id, {"active_application": "notepad"})
ctx = active_context_manager.get_context(user_id)
print(f"Initial Context: App='{ctx.active_application}'")

# 2. Test reference resolution for "open WhatsApp in my laptop"
cmd = "open WhatsApp in my laptop"
ref = active_context_manager.resolve_references(cmd, user_id=user_id)
print(f"[RESOLVER] Category: '{ref['category']}', Target App: '{ref['target_app']}', Resolved: '{ref['resolved_command']}'")

# 3. Test planning with RuleFallbackProvider
planner = RuleFallbackProvider()
steps = planner.plan_task_sync(ref["resolved_command"], active_context=ref["active_context"])

print(f"\n[PLANNED STEPS FOR '{cmd}']:")
for s in steps:
    print(f"  Tool: {s.get('tool_name')}, Parameters: {s.get('parameters')}, Target Device: {s.get('target_device')}")

assert steps[0]["parameters"]["app_name"].lower() == "whatsapp", f"ERROR: Expected whatsapp but got {steps[0]['parameters']['app_name']}"
print("\nTEST PASSED: 'open WhatsApp in my laptop' correctly plans app_name='whatsapp'!")
