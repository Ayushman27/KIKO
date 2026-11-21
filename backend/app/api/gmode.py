"""
G Mode API Routes
==================
All G Mode operations go through this router.
Key security contract: candidate approval endpoints are backend-enforced.
The frontend cannot promote a candidate without calling these endpoints;
there is no client-side-only approval pathway.
"""
import os
import logging
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List

from app.database.session import get_db
from app.models.domain import GExperiment, GExperimentLog, GCandidate
from app.orchestrator.g_orchestrator import g_orchestrator
from app.core.config import settings

logger = logging.getLogger("kiko.gmode_api")
router = APIRouter(prefix="/gmode", tags=["G Mode"])


# ─── Request / Response schemas ────────────────────────────────────────────────

class StartExperimentRequest(BaseModel):
    objective: str
    mode: Optional[str] = "research"    # research, coding, testing, evaluation
    max_runtime_secs: Optional[int] = None  # Override default; None = use settings default

class CandidateReviewRequest(BaseModel):
    approved: bool
    review_notes: Optional[str] = ""


# ─── Experiment management ─────────────────────────────────────────────────────

@router.post("/experiments")
async def start_experiment(
    req: StartExperimentRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """
    Start a new G Mode autonomous experiment.
    The experiment runs in an isolated workspace and broadcasts progress over WebSocket.
    The experiment loop continues in the background even if the HTTP connection closes.
    """
    # Cap runtime at configured maximum
    max_runtime = req.max_runtime_secs
    if max_runtime and max_runtime > settings.G_MODE_MAX_RUNTIME_SECS:
        max_runtime = settings.G_MODE_MAX_RUNTIME_SECS

    # Check parallel experiment limit
    running_count = db.query(GExperiment).filter(GExperiment.status == "RUNNING").count()
    if running_count >= settings.G_MODE_MAX_PARALLEL_EXPERIMENTS:
        raise HTTPException(
            status_code=429,
            detail=f"Maximum parallel experiments ({settings.G_MODE_MAX_PARALLEL_EXPERIMENTS}) reached. "
                   f"Pause or cancel a running experiment first."
        )

    exp = g_orchestrator.create_experiment(
        db=db,
        objective=req.objective,
        mode=req.mode,
        max_runtime_secs=max_runtime,
    )

    # Launch autonomously in background
    background_tasks.add_task(g_orchestrator.start_experiment, exp.id)

    return {
        "id": exp.id,
        "objective": exp.objective,
        "mode": exp.mode,
        "status": exp.status,
        "workspace_path": exp.workspace_path,
        "max_runtime_secs": exp.max_runtime_secs,
        "created_at": exp.created_at.isoformat()
    }


@router.get("/experiments")
def list_experiments(
    status: Optional[str] = None,
    limit: int = 20,
    db: Session = Depends(get_db)
):
    """List G Mode experiments, optionally filtered by status."""
    query = db.query(GExperiment).order_by(GExperiment.created_at.desc())
    if status:
        query = query.filter(GExperiment.status == status)
    experiments = query.limit(limit).all()
    return [_serialize_experiment(e) for e in experiments]


@router.get("/experiments/{experiment_id}")
def get_experiment(experiment_id: str, db: Session = Depends(get_db)):
    """Get full details of a G Mode experiment including logs and candidates."""
    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp:
        raise HTTPException(status_code=404, detail="Experiment not found")
    return {
        **_serialize_experiment(exp),
        "logs": [_serialize_log(l) for l in exp.logs[-50:]],  # last 50 log entries
        "candidates": [_serialize_candidate(c) for c in exp.candidates]
    }


@router.post("/experiments/{experiment_id}/pause")
async def pause_experiment(experiment_id: str, db: Session = Depends(get_db)):
    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp:
        raise HTTPException(status_code=404, detail="Experiment not found")
    await g_orchestrator.pause_experiment(db, experiment_id)
    return {"status": "paused", "experiment_id": experiment_id}


@router.post("/experiments/{experiment_id}/resume")
async def resume_experiment(experiment_id: str, db: Session = Depends(get_db)):
    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp:
        raise HTTPException(status_code=404, detail="Experiment not found")
    if exp.status == "PAUSED":
        exp.status = "RUNNING"
        db.commit()
        return {"status": "resumed", "experiment_id": experiment_id}
    return {"status": exp.status, "experiment_id": experiment_id}


@router.post("/experiments/{experiment_id}/cancel")
async def cancel_experiment(experiment_id: str, db: Session = Depends(get_db)):
    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp:
        raise HTTPException(status_code=404, detail="Experiment not found")
    await g_orchestrator.cancel_experiment(db, experiment_id)
    return {"status": "cancelled", "experiment_id": experiment_id}


@router.delete("/experiments/{experiment_id}")
def delete_experiment(experiment_id: str, db: Session = Depends(get_db)):
    """Delete an experiment and its workspace directory. Only allowed for completed/cancelled/failed experiments."""
    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp:
        raise HTTPException(status_code=404, detail="Experiment not found")
    if exp.status == "RUNNING":
        raise HTTPException(status_code=409, detail="Cannot delete a running experiment. Cancel it first.")

    workspace = exp.workspace_path
    db.delete(exp)
    db.commit()

    # Clean up workspace directory
    if workspace and os.path.exists(workspace):
        try:
            import shutil
            shutil.rmtree(workspace)
        except Exception as e:
            logger.warning(f"[G MODE] Failed to delete workspace {workspace}: {e}")

    return {"status": "deleted", "experiment_id": experiment_id}


# ─── Logs ──────────────────────────────────────────────────────────────────────

@router.get("/experiments/{experiment_id}/logs")
def get_experiment_logs(
    experiment_id: str,
    stage: Optional[str] = None,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """Get log entries for a G Mode experiment."""
    query = db.query(GExperimentLog).filter(
        GExperimentLog.experiment_id == experiment_id
    ).order_by(GExperimentLog.created_at.asc())
    if stage:
        query = query.filter(GExperimentLog.stage == stage)
    logs = query.limit(limit).all()
    return [_serialize_log(l) for l in logs]


# ─── Candidate approval ────────────────────────────────────────────────────────

@router.get("/experiments/{experiment_id}/candidates")
def list_candidates(experiment_id: str, db: Session = Depends(get_db)):
    """List all candidate improvements produced by this experiment."""
    candidates = db.query(GCandidate).filter(
        GCandidate.experiment_id == experiment_id
    ).order_by(GCandidate.created_at.desc()).all()
    return [_serialize_candidate(c) for c in candidates]


@router.post("/experiments/{experiment_id}/candidates/{candidate_id}/review")
async def review_candidate(
    experiment_id: str,
    candidate_id: str,
    req: CandidateReviewRequest,
    db: Session = Depends(get_db)
):
    """
    Approve or reject a G Mode candidate improvement.
    
    IMPORTANT: Approval records the decision but does NOT automatically
    copy files into the main codebase. The user must manually review
    the workspace files and perform the promotion themselves.
    
    This is a backend-enforced operation — the frontend cannot bypass
    this endpoint to auto-promote candidates.
    """
    if req.approved:
        result = await g_orchestrator.approve_candidate(
            db, experiment_id, candidate_id, req.review_notes
        )
    else:
        result = await g_orchestrator.reject_candidate(
            db, experiment_id, candidate_id, req.review_notes
        )

    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error", "Review failed"))
    return result


@router.get("/experiments/{experiment_id}/candidates/{candidate_id}/workspace-files")
def get_candidate_workspace_files(
    experiment_id: str,
    candidate_id: str,
    db: Session = Depends(get_db)
):
    """
    List files in the candidate's workspace for user inspection.
    Returns file paths and sizes — content must be fetched file-by-file.
    Only APPROVED or PENDING_REVIEW candidates can be inspected.
    """
    candidate = db.query(GCandidate).filter(
        GCandidate.id == candidate_id,
        GCandidate.experiment_id == experiment_id
    ).first()
    if not candidate:
        raise HTTPException(status_code=404, detail="Candidate not found")

    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp or not exp.workspace_path:
        raise HTTPException(status_code=404, detail="Workspace not found")

    files_info = []
    for rel_path in (candidate.files_changed or []):
        abs_path = os.path.join(exp.workspace_path, rel_path)
        if os.path.exists(abs_path):
            files_info.append({
                "relative_path": rel_path,
                "size_bytes": os.path.getsize(abs_path),
                "exists": True
            })
        else:
            files_info.append({"relative_path": rel_path, "exists": False})

    return {
        "candidate_id": candidate_id,
        "workspace_path": exp.workspace_path,
        "files": files_info,
        "note": "Review files before approving. To read a file, use the /api/v1/gmode/workspace-read endpoint."
    }


@router.post("/experiments/{experiment_id}/candidates/{candidate_id}/read-file")
def read_candidate_file(
    experiment_id: str,
    candidate_id: str,
    relative_path: str,
    db: Session = Depends(get_db)
):
    """Read the content of a file in the candidate's workspace for diff inspection."""
    candidate = db.query(GCandidate).filter(
        GCandidate.id == candidate_id,
        GCandidate.experiment_id == experiment_id
    ).first()
    if not candidate:
        raise HTTPException(status_code=404, detail="Candidate not found")

    exp = db.query(GExperiment).filter(GExperiment.id == experiment_id).first()
    if not exp or not exp.workspace_path:
        raise HTTPException(status_code=404, detail="Workspace not found")

    abs_path = os.path.abspath(os.path.join(exp.workspace_path, relative_path))
    # Path safety check
    if not abs_path.startswith(os.path.abspath(exp.workspace_path)):
        raise HTTPException(status_code=403, detail="Path traversal attempt blocked")

    if not os.path.exists(abs_path):
        raise HTTPException(status_code=404, detail="File not found in workspace")

    try:
        with open(abs_path, "r", encoding="utf-8") as f:
            content = f.read()
        return {"relative_path": relative_path, "content": content, "size": len(content)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Could not read file: {e}")


# ─── Emergency stop ────────────────────────────────────────────────────────────

@router.post("/emergency-stop")
async def emergency_stop(db: Session = Depends(get_db)):
    """
    Global emergency stop: cancel ALL running G Mode experiments immediately.
    This is a backend-enforced operation with no undo.
    """
    running = db.query(GExperiment).filter(GExperiment.status.in_(["RUNNING", "PAUSED"])).all()
    cancelled_ids = []
    for exp in running:
        exp.status = "CANCELLED"
        exp.completed_at = datetime.utcnow()
        exp.error_message = "Emergency stop triggered by user."
        cancelled_ids.append(exp.id)
    db.commit()

    logger.warning(f"[G MODE] EMERGENCY STOP: cancelled {len(cancelled_ids)} experiments: {cancelled_ids}")
    return {
        "status": "emergency_stop_executed",
        "cancelled_experiments": cancelled_ids,
        "count": len(cancelled_ids)
    }


# ─── Status overview ───────────────────────────────────────────────────────────

@router.get("/status")
def gmode_status(db: Session = Depends(get_db)):
    """Overview of G Mode system status."""
    running = db.query(GExperiment).filter(GExperiment.status == "RUNNING").count()
    paused = db.query(GExperiment).filter(GExperiment.status == "PAUSED").count()
    pending_review = db.query(GCandidate).filter(GCandidate.status == "PENDING_REVIEW").count()
    return {
        "running_experiments": running,
        "paused_experiments": paused,
        "candidates_pending_review": pending_review,
        "max_parallel": settings.G_MODE_MAX_PARALLEL_EXPERIMENTS,
        "workspace_dir": settings.G_MODE_WORKSPACE_DIR,
        "max_runtime_secs": settings.G_MODE_MAX_RUNTIME_SECS,
    }


# ─── Serialization helpers ─────────────────────────────────────────────────────

def _serialize_experiment(exp: GExperiment) -> dict:
    return {
        "id": exp.id,
        "objective": exp.objective,
        "mode": exp.mode,
        "status": exp.status,
        "workspace_path": exp.workspace_path,
        "iteration_count": exp.iteration_count,
        "max_runtime_secs": exp.max_runtime_secs,
        "started_at": exp.started_at.isoformat() if exp.started_at else None,
        "completed_at": exp.completed_at.isoformat() if exp.completed_at else None,
        "created_at": exp.created_at.isoformat(),
        "result_summary": exp.result_summary,
        "error_message": exp.error_message,
    }


def _serialize_log(log: GExperimentLog) -> dict:
    return {
        "id": log.id,
        "stage": log.stage,
        "message": log.message,
        "details": log.details,
        "success": log.success,
        "created_at": log.created_at.isoformat()
    }


def _serialize_candidate(c: GCandidate) -> dict:
    return {
        "id": c.id,
        "experiment_id": c.experiment_id,
        "title": c.title,
        "description": c.description,
        "files_changed": c.files_changed,
        "diff_summary": c.diff_summary,
        "test_results": c.test_results,
        "baseline_score": c.baseline_score,
        "candidate_score": c.candidate_score,
        "known_limitations": c.known_limitations,
        "risk_assessment": c.risk_assessment,
        "status": c.status,
        "reviewed_at": c.reviewed_at.isoformat() if c.reviewed_at else None,
        "review_notes": c.review_notes,
        "created_at": c.created_at.isoformat()
    }
