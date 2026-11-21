from datetime import datetime
from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session
from app.models.domain import Approval, Task
from app.websocket.manager import manager as ws_manager

class ApprovalManager:
    """Manages creation, query, and resolution of sensitive task approvals."""
    
    def create_approval_request(
        self,
        db: Session,
        task_id: str,
        step_id: Optional[str],
        tool_name: str,
        risk_level: str,
        action_description: str,
        parameters: Dict[str, Any]
    ) -> Approval:
        approval = Approval(
            task_id=task_id,
            step_id=step_id,
            tool_name=tool_name,
            risk_level=risk_level,
            action_description=action_description,
            parameters=parameters,
            status="PENDING"
        )
        db.add(approval)
        db.commit()
        db.refresh(approval)

        # Update task status
        task = db.query(Task).filter(Task.id == task_id).first()
        if task:
            task.status = "WAITING_FOR_APPROVAL"
            db.commit()

        return approval

    async def resolve_approval(self, db: Session, approval_id: str, approved: bool, reason: str = "") -> Optional[Approval]:
        approval = db.query(Approval).filter(Approval.id == approval_id).first()
        if not approval:
            return None

        approval.status = "APPROVED" if approved else "REJECTED"
        approval.reason = reason
        approval.resolved_at = datetime.utcnow()
        db.commit()
        db.refresh(approval)

        # Broadcast WebSocket notification
        await ws_manager.broadcast({
            "event": "APPROVAL_RESOLVED",
            "task_id": approval.task_id,
            "approval_id": approval.id,
            "approved": approved,
            "message": f"Approval {approval.id} {'APPROVED' if approved else 'REJECTED'}",
            "timestamp": datetime.utcnow().isoformat()
        })

        return approval

    def list_pending_approvals(self, db: Session) -> List[Approval]:
        return db.query(Approval).filter(Approval.status == "PENDING").all()

approval_manager = ApprovalManager()
