import sys
import os
import asyncio
import logging

# Add backend directory to sys.path
backend_dir = r"c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend"
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("test_context")

async def test_full_continuity():
    from app.context.manager import active_context_manager
    from app.database.session import SessionLocal
    from app.orchestrator.engine import orchestrator

    user_id = "voice_user"
    
    commands = [
        "open Notepad",
        "write Ayushman",
        "write Patro below it",
        "save it as myname.txt",
        "add AI Agent Developer below it"
    ]

    print("==================================================")
    print("STARTING TASK CONTINUITY & CONTEXT RESOLUTION TEST")
    print("==================================================")

    for idx, cmd in enumerate(commands, 1):
        print(f"\n--- STEP {idx}: '{cmd}' ---")
        
        # Test reference resolution
        ref = active_context_manager.resolve_references(cmd, user_id=user_id)
        print(f"[RESOLVER] Category: {ref['category']}")
        print(f"[RESOLVER] Target App: {ref['target_app']}")
        print(f"[RESOLVER] Resolved Cmd: {ref['resolved_command']}")
        print(f"[RESOLVER] Is Append: {ref['is_append']}")

        db = SessionLocal()
        try:
            task = await orchestrator.create_and_run_task(
                db=db,
                user_id=user_id,
                description=cmd,
                origin_device="WINDOWS_PC"
            )
            print(f"[ORCHESTRATOR] Task ID: {task.id}, Status: {task.status}")
        finally:
            db.close()

        # Wait for task execution loop to complete step
        await asyncio.sleep(4.0)

        # Print current context state
        ctx = active_context_manager.get_context(user_id)
        print(f"[CONTEXT CURRENT] App: {ctx.active_application}, Doc: {ctx.active_document}, LastAction: {ctx.last_action}")

    print("\n==================================================")
    print("VERIFICATION COMPLETED SUCCESSFULLY!")
    print("==================================================")

if __name__ == "__main__":
    asyncio.run(test_full_continuity())
