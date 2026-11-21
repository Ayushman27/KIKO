from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from app.database.session import get_db
from app.approvals.manager import approval_manager

router = APIRouter(prefix="/approvals", tags=["Approvals"])

class ApprovalResolveRequest(BaseModel):
    approved: bool
    reason: Optional[str] = ""

@router.get("")
def list_approvals(db: Session = Depends(get_db)):
    approvals = approval_manager.list_pending_approvals(db)
    return [
        {
            "id": a.id,
            "task_id": a.task_id,
            "step_id": a.step_id,
            "tool_name": a.tool_name,
            "risk_level": a.risk_level,
            "action_description": a.action_description,
            "parameters": a.parameters,
            "status": a.status,
            "created_at": a.created_at.isoformat()
        }
        for a in approvals
    ]

@router.post("/{approval_id}/resolve")
async def resolve_approval(approval_id: str, req: ApprovalResolveRequest, db: Session = Depends(get_db)):
    res = await approval_manager.resolve_approval(db, approval_id, approved=req.approved, reason=req.reason)
    if not res:
        raise HTTPException(status_code=404, detail="Approval not found")
    return {"status": "SUCCESS", "approval_id": approval_id, "resolved_status": res.status}
