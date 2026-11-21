"""
G Mode Autonomous Orchestrator
================================
G Mode is an isolated autonomous research, experimentation, and software-improvement agent.

Security invariants (never violate these):
- G Mode operates ONLY within its own workspace directory (data/g_workspace/<experiment_id>/)
- G Mode NEVER directly modifies the live Alpha application code
- Candidates require EXPLICIT user approval before any code reaches the main codebase
- G Mode cannot grant itself new permissions or disable its own restrictions
- All generated scripts are logged before execution; no arbitrary shell commands run without validation
- Network access is unrestricted in local mode but should be policy-gated in cloud mode

Autonomous loop:
    GOAL → RESEARCH → PLAN → EXPERIMENT → IMPLEMENT → TEST → EVALUATE → RECORD → [REPEAT | DONE]
"""
import asyncio
import json
import logging
import os
import shutil
import subprocess
import time
from datetime import datetime
from typing import Dict, Any, List, Optional

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.domain import GExperiment, GExperimentLog, GCandidate
from app.websocket.manager import manager as ws_manager

logger = logging.getLogger("kiko.g_orchestrator")


# ─── Allowed tool names for G Mode (explicit whitelist) ───────────────────────
# G Mode may only execute these tools in its own workspace.
# Adding new tools here requires a conscious decision, not an LLM instruction.
G_ALLOWED_TOOLS: List[str] = [
    "read_file",
    "write_file",
    "create_folder",
    "create_file",
    "search_files",
    "list_directory",
    "run_python_script",  # Only within experiment workspace
    "run_tests",
    "git_init",
    "git_commit",
    "git_diff",
    "web_search",         # Research only
    "fetch_url",          # Documentation only; no authenticated endpoints
]

# Stages of the G Mode autonomous loop
STAGES = ["research", "plan", "experiment", "implement", "test", "evaluate", "record"]


class GOrchestrator:
    """
    G Mode autonomous orchestrator.
    Each experiment runs in a dedicated workspace directory.
    Interacts with the database to persist state, logs, and candidate improvements.
    Broadcasts progress over WebSocket so the UI stays informed.
    """

    def _workspace_for(self, experiment_id: str) -> str:
        """Return the absolute path to this experiment's isolated workspace."""
        ws = os.path.join(settings.G_MODE_WORKSPACE_DIR, experiment_id)
        os.makedirs(ws, exist_ok=True)
        return ws

    def _is_path_safe(self, path: str, experiment_id: str) -> bool:
        """Verify that a file path is inside this experiment's workspace (no traversal)."""
        workspace = os.path.abspath(self._workspace_for(experiment_id))
        target = os.path.abspath(path)
        return target.startswith(workspace)

    # ─── Experiment lifecycle ──────────────────────────────────────────────────

    def create_experiment(
        self,
        db: Session,
        objective: str,
        mode: str = "research",
        max_runtime_secs: Optional[int] = None,
    ) -> GExperiment:
        """Create and persist a new G Mode experiment record."""
        exp = GExperiment(
            objective=objective,
            mode=mode,
            status="PENDING",
            max_runtime_secs=max_runtime_secs or settings.G_MODE_MAX_RUNTIME_SECS,
        )
        db.add(exp)
        db.commit()
        db.refresh(exp)

        # Create isolated workspace
        ws = self._workspace_for(exp.id)
        exp.workspace_path = ws
        db.commit()

        logger.info(f"[G MODE] Created experiment {exp.id}: '{objective}' | workspace: {ws}")
        return exp

    async def start_experiment(self, experiment_id: str):
        """Launch the experiment loop as a background asyncio task."""
        asyncio.create_task(self._run_experiment_loop(experiment_id))

    async def pause_experiment(self, db: Session, experiment_id: str):
        exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
        if exp and exp.status == "RUNNING":
            exp.status = "PAUSED"
            db.commit()
            await ws_manager.broadcast({
                "event": "G_EXPERIMENT_PAUSED",
                "experiment_id": experiment_id,
                "message": f"Experiment paused: {exp.objective[:60]}"
            })

    async def cancel_experiment(self, db: Session, experiment_id: str):
        exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
        if exp and exp.status in ("RUNNING", "PENDING", "PAUSED"):
            exp.status = "CANCELLED"
            exp.completed_at = datetime.utcnow()
            db.commit()
            await ws_manager.broadcast({
                "event": "G_EXPERIMENT_CANCELLED",
                "experiment_id": experiment_id,
                "message": f"Experiment cancelled: {exp.objective[:60]}"
            })

    # ─── Autonomous loop ───────────────────────────────────────────────────────

    async def _run_experiment_loop(self, experiment_id: str):
        """
        The core G Mode autonomous loop.
        Runs: RESEARCH → PLAN → EXPERIMENT → IMPLEMENT → TEST → EVALUATE → RECORD
        Respects max_runtime_secs and pause/cancel state.
        """
        from app.database.session import SessionLocal
        from app.ai.providers import get_ai_provider

        db = SessionLocal()
        start_time = time.monotonic()

        try:
            exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
            if not exp:
                logger.error(f"[G MODE] Experiment {experiment_id} not found")
                return

            exp.status = "RUNNING"
            exp.started_at = datetime.utcnow()
            db.commit()

            ai = get_ai_provider()
            workspace = exp.workspace_path or self._workspace_for(experiment_id)
            max_runtime = exp.max_runtime_secs

            await ws_manager.broadcast({
                "event": "G_EXPERIMENT_STARTED",
                "experiment_id": experiment_id,
                "objective": exp.objective,
                "workspace": workspace,
                "message": f"🔬 G Mode started: {exp.objective[:80]}"
            })

            for iteration in range(1, settings.G_MODE_MAX_RETRIES + 2):
                # --- Resource limit check ---
                elapsed = time.monotonic() - start_time
                if elapsed >= max_runtime:
                    await self._log_and_broadcast(db, exp, "evaluate",
                        f"⏱️ Max runtime ({max_runtime}s) reached after {elapsed:.0f}s. Stopping.",
                        success=False
                    )
                    exp.status = "FAILED"
                    exp.error_message = "Max runtime exceeded"
                    exp.completed_at = datetime.utcnow()
                    db.commit()
                    return

                # --- Pause/cancel check ---
                db.refresh(exp)
                if exp.status == "CANCELLED":
                    logger.info(f"[G MODE] Experiment {experiment_id} was cancelled.")
                    return
                if exp.status == "PAUSED":
                    logger.info(f"[G MODE] Experiment {experiment_id} is paused. Waiting...")
                    while exp.status == "PAUSED":
                        await asyncio.sleep(5)
                        db.refresh(exp)
                    if exp.status == "CANCELLED":
                        return

                exp.iteration_count = iteration
                db.commit()
                logger.info(f"[G MODE] Experiment {experiment_id} | Iteration {iteration}")

                # ── Stage 1: RESEARCH ────────────────────────────────────────
                await self._log_and_broadcast(db, exp, "research",
                    f"🔍 Iteration {iteration}: Researching objective...")

                research_prompt = (
                    f"You are an autonomous AI research and software engineering agent operating in G Mode.\n"
                    f"Your objective: {exp.objective}\n"
                    f"Iteration: {iteration}\n"
                    f"Workspace: {workspace}\n\n"
                    f"Step 1 - RESEARCH: Describe what you need to understand to make progress on this objective. "
                    f"List specific questions to answer and resources to consult. Be concise and actionable."
                )
                research_plan = await ai.generate_response(research_prompt, system_prompt=(
                    "You are KIKO G Mode — an autonomous AI research and coding agent. "
                    "You operate in an isolated workspace. You cannot modify the main application. "
                    "Be precise, technical, and honest about limitations."
                ))
                await self._log_and_broadcast(db, exp, "research",
                    f"Research plan:\n{research_plan[:500]}", details={"plan": research_plan})

                # ── Stage 2: PLAN ────────────────────────────────────────────
                await self._log_and_broadcast(db, exp, "plan",
                    f"📋 Planning experiment steps...")

                plan_prompt = (
                    f"Objective: {exp.objective}\n"
                    f"Research findings: {research_plan}\n"
                    f"Workspace: {workspace}\n\n"
                    f"Step 2 - PLAN: Create a concrete experiment plan. "
                    f"List specific files to create/modify (only within {workspace}), "
                    f"code to write, and tests to run. "
                    f"Output as a JSON object with keys: 'steps' (list of action strings), "
                    f"'files_to_create' (list of relative filenames), 'expected_outcome' (string).\n"
                    f"Respond with ONLY the JSON object."
                )
                plan_text = await ai.generate_response(plan_prompt)
                try:
                    if "```json" in plan_text:
                        plan_text = plan_text.split("```json")[1].split("```")[0].strip()
                    elif "```" in plan_text:
                        plan_text = plan_text.split("```")[1].split("```")[0].strip()
                    plan_data = json.loads(plan_text)
                except Exception:
                    plan_data = {"steps": [plan_text], "files_to_create": [], "expected_outcome": "Unknown"}

                await self._log_and_broadcast(db, exp, "plan",
                    f"Experiment plan ready: {len(plan_data.get('steps', []))} steps",
                    details=plan_data)

                # ── Stage 3: IMPLEMENT ───────────────────────────────────────
                await self._log_and_broadcast(db, exp, "implement",
                    f"⚙️ Implementing experiment...")

                files_created = []
                for step in plan_data.get("steps", [])[:5]:  # cap steps per iteration
                    impl_prompt = (
                        f"Objective: {exp.objective}\n"
                        f"Current step: {step}\n"
                        f"Workspace: {workspace}\n\n"
                        f"Implement this step. If it involves creating a file, respond with:\n"
                        f"FILENAME: <relative_filename>\n"
                        f"CONTENT:\n<file_content>\n\n"
                        f"If it is an analysis step, describe your findings."
                    )
                    impl_result = await ai.generate_response(impl_prompt)

                    # Parse and write file if instructed
                    if "FILENAME:" in impl_result and "CONTENT:" in impl_result:
                        try:
                            fname_line = [l for l in impl_result.split("\n") if l.startswith("FILENAME:")][0]
                            rel_path = fname_line.replace("FILENAME:", "").strip()
                            content_start = impl_result.index("CONTENT:") + len("CONTENT:\n")
                            content = impl_result[content_start:].strip()

                            abs_path = os.path.join(workspace, rel_path)
                            if self._is_path_safe(abs_path, experiment_id):
                                os.makedirs(os.path.dirname(abs_path), exist_ok=True)
                                with open(abs_path, "w", encoding="utf-8") as f:
                                    f.write(content)
                                files_created.append(rel_path)
                                await self._log_and_broadcast(db, exp, "implement",
                                    f"✅ Created file: {rel_path} ({len(content)} chars)")
                            else:
                                await self._log_and_broadcast(db, exp, "implement",
                                    f"⛔ Path safety check FAILED for: {rel_path} — skipping",
                                    success=False)
                        except Exception as fe:
                            await self._log_and_broadcast(db, exp, "implement",
                                f"⚠️ File creation error: {fe}", success=False)

                # ── Stage 4: TEST ────────────────────────────────────────────
                await self._log_and_broadcast(db, exp, "test", "🧪 Running tests...")
                test_results = await self._run_workspace_tests(workspace, experiment_id)
                await self._log_and_broadcast(db, exp, "test",
                    f"Test results: {test_results.get('summary', 'No tests found')}",
                    details=test_results)

                # ── Stage 5: EVALUATE ────────────────────────────────────────
                await self._log_and_broadcast(db, exp, "evaluate", "📊 Evaluating results...")
                eval_prompt = (
                    f"Objective: {exp.objective}\n"
                    f"Files created: {files_created}\n"
                    f"Test results: {json.dumps(test_results)}\n\n"
                    f"Evaluate progress on the objective. "
                    f"Respond with JSON: {{\"achieved\": true/false, \"confidence\": 0-100, "
                    f"\"summary\": \"...\", \"next_action\": \"continue|done|failed\"}}"
                )
                eval_text = await ai.generate_response(eval_prompt)
                try:
                    if "```json" in eval_text:
                        eval_text = eval_text.split("```json")[1].split("```")[0].strip()
                    elif "```" in eval_text:
                        eval_text = eval_text.split("```")[1].split("```")[0].strip()
                    eval_data = json.loads(eval_text)
                except Exception:
                    eval_data = {"achieved": False, "confidence": 0, "summary": eval_text, "next_action": "continue"}

                await self._log_and_broadcast(db, exp, "evaluate",
                    f"Evaluation: confidence={eval_data.get('confidence', 0)}% — {eval_data.get('summary', '')[:200]}",
                    details=eval_data)

                # ── Stage 6: RECORD ──────────────────────────────────────────
                if files_created:
                    await self._create_candidate(
                        db, exp, files_created, eval_data, plan_data, test_results
                    )

                # ── Loop control ─────────────────────────────────────────────
                next_action = eval_data.get("next_action", "continue")
                if next_action == "done" or eval_data.get("achieved"):
                    exp.status = "COMPLETED"
                    exp.result_summary = eval_data.get("summary", "Experiment completed successfully.")
                    exp.completed_at = datetime.utcnow()
                    db.commit()
                    await ws_manager.broadcast({
                        "event": "G_EXPERIMENT_COMPLETED",
                        "experiment_id": experiment_id,
                        "message": f"✅ G Mode experiment completed: {exp.objective[:60]}",
                        "result_summary": exp.result_summary
                    })
                    return
                elif next_action == "failed":
                    exp.status = "FAILED"
                    exp.error_message = eval_data.get("summary", "Evaluation indicated failure.")
                    exp.completed_at = datetime.utcnow()
                    db.commit()
                    return

                # Continue to next iteration
                await asyncio.sleep(2)

            # Exhausted retries
            exp.status = "FAILED"
            exp.error_message = f"Exhausted {settings.G_MODE_MAX_RETRIES + 1} iterations without completion."
            exp.completed_at = datetime.utcnow()
            db.commit()

        except Exception as e:
            logger.error(f"[G MODE] Experiment {experiment_id} crashed: {e}", exc_info=True)
            try:
                exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
                if exp:
                    exp.status = "FAILED"
                    exp.error_message = str(e)
                    exp.completed_at = datetime.utcnow()
                    db.commit()
            except Exception:
                pass
        finally:
            db.close()

    # ─── Helper methods ────────────────────────────────────────────────────────

    async def _log_and_broadcast(
        self,
        db: Session,
        exp: GExperiment,
        stage: str,
        message: str,
        details: Optional[Dict] = None,
        success: Optional[bool] = None
    ):
        """Persist a log entry and broadcast it over WebSocket."""
        log_entry = GExperimentLog(
            experiment_id=exp.id,
            stage=stage,
            message=message,
            details=details,
            success=success
        )
        db.add(log_entry)
        db.commit()

        await ws_manager.broadcast({
            "event": "G_EXPERIMENT_PROGRESS",
            "experiment_id": exp.id,
            "stage": stage,
            "message": message,
            "iteration": exp.iteration_count,
            "timestamp": datetime.utcnow().isoformat()
        })

    async def _run_workspace_tests(self, workspace: str, experiment_id: str) -> Dict[str, Any]:
        """
        Run tests found in the experiment workspace.
        Only runs files named test_*.py or *_test.py within the workspace.
        Enforces an absolute path safety check before executing.
        """
        test_files = []
        for root, dirs, files in os.walk(workspace):
            # Skip hidden dirs
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            for f in files:
                if (f.startswith("test_") or f.endswith("_test.py")) and f.endswith(".py"):
                    abs_path = os.path.join(root, f)
                    if self._is_path_safe(abs_path, experiment_id):
                        test_files.append(abs_path)

        if not test_files:
            return {"summary": "No test files found in workspace", "passed": 0, "failed": 0, "files": []}

        results = {"passed": 0, "failed": 0, "files": [], "details": []}
        for tf in test_files:
            try:
                proc = subprocess.run(
                    ["python", "-m", "pytest", tf, "-v", "--tb=short", "--no-header"],
                    capture_output=True, text=True, timeout=60,
                    cwd=workspace
                )
                passed = proc.returncode == 0
                results["passed" if passed else "failed"] += 1
                results["files"].append(os.path.relpath(tf, workspace))
                results["details"].append({
                    "file": os.path.relpath(tf, workspace),
                    "passed": passed,
                    "output": proc.stdout[-1000:] if proc.stdout else proc.stderr[-1000:]
                })
            except subprocess.TimeoutExpired:
                results["failed"] += 1
                results["details"].append({"file": tf, "passed": False, "output": "TIMEOUT"})
            except Exception as e:
                results["failed"] += 1
                results["details"].append({"file": tf, "passed": False, "output": str(e)})

        results["summary"] = f"{results['passed']} passed, {results['failed']} failed"
        return results

    async def _create_candidate(
        self,
        db: Session,
        exp: GExperiment,
        files_created: List[str],
        eval_data: Dict,
        plan_data: Dict,
        test_results: Dict
    ):
        """
        Record a candidate improvement for user review.
        The candidate is never automatically promoted — it sits in PENDING_REVIEW
        until the user explicitly approves it via the API.
        """
        # Build diff summary from files
        diff_summary = f"Files created/modified in experiment workspace:\n"
        for f in files_created:
            diff_summary += f"  + {f}\n"
        diff_summary += f"\nExpected outcome: {plan_data.get('expected_outcome', 'N/A')}"

        candidate = GCandidate(
            experiment_id=exp.id,
            title=f"Candidate from iteration {exp.iteration_count}: {exp.objective[:50]}",
            description=eval_data.get("summary", "No evaluation summary"),
            files_changed=files_created,
            diff_summary=diff_summary,
            test_results=test_results,
            candidate_score=str(eval_data.get("confidence", 0)),
            known_limitations="Review candidate files in workspace before approving.",
            risk_assessment="Candidate code has not been tested against the main codebase.",
            status="PENDING_REVIEW"
        )
        db.add(candidate)
        db.commit()
        db.refresh(candidate)

        await ws_manager.broadcast({
            "event": "G_CANDIDATE_READY",
            "experiment_id": exp.id,
            "candidate_id": candidate.id,
            "message": f"🆕 New candidate ready for review: {candidate.title}",
            "files_changed": files_created,
            "test_results": test_results
        })
        logger.info(f"[G MODE] Candidate {candidate.id} created for experiment {exp.id}")

    async def approve_candidate(self, db: Session, experiment_id: str, candidate_id: str, review_notes: str = "") -> Dict[str, Any]:
        """
        Approve a candidate. This records approval but does NOT automatically copy files.
        The actual promotion (copying workspace files to the main codebase) must be
        done manually or through a separate verified promotion tool — never automatically.
        """
        candidate = db.query(GCandidate).filter(
            GCandidate.id == candidate_id,
            GCandidate.experiment_id == experiment_id
        ).first()
        if not candidate:
            return {"success": False, "error": "Candidate not found"}
        if candidate.status != "PENDING_REVIEW":
            return {"success": False, "error": f"Candidate status is '{candidate.status}', not PENDING_REVIEW"}

        candidate.status = "APPROVED"
        candidate.reviewed_at = datetime.utcnow()
        candidate.review_notes = review_notes
        db.commit()

        await ws_manager.broadcast({
            "event": "G_CANDIDATE_APPROVED",
            "experiment_id": experiment_id,
            "candidate_id": candidate_id,
            "message": f"✅ Candidate approved. Files in workspace are ready for manual promotion.",
            "workspace_path": db.query(GExperiment).filter(GExperiment.id == experiment_id).first().workspace_path,
            "files_changed": candidate.files_changed
        })

        return {
            "success": True,
            "candidate_id": candidate_id,
            "status": "APPROVED",
            "files_changed": candidate.files_changed,
            "workspace_path": db.query(GExperiment).filter(GExperiment.id == experiment_id).first().workspace_path,
            "note": "Candidate approved. Files remain in the isolated workspace. Review them before manually copying to the main codebase."
        }

    async def reject_candidate(self, db: Session, experiment_id: str, candidate_id: str, review_notes: str = "") -> Dict[str, Any]:
        candidate = db.query(GCandidate).filter(
            GCandidate.id == candidate_id,
            GCandidate.experiment_id == experiment_id
        ).first()
        if not candidate:
            return {"success": False, "error": "Candidate not found"}

        candidate.status = "REJECTED"
        candidate.reviewed_at = datetime.utcnow()
        candidate.review_notes = review_notes
        db.commit()

        return {"success": True, "candidate_id": candidate_id, "status": "REJECTED"}


# Singleton orchestrator instance
g_orchestrator = GOrchestrator()
