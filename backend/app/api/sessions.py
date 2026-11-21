from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from app.database.session import get_db
from app.models.domain import ChatSession, ChatMessage

router = APIRouter(prefix="/sessions", tags=["Sessions"])

class SessionCreateRequest(BaseModel):
    user_id: Optional[str] = "dev_user_1"
    title: Optional[str] = "New Chat"

@router.post("")
def create_session(req: SessionCreateRequest, db: Session = Depends(get_db)):
    session = ChatSession(user_id=req.user_id, title=req.title)
    db.add(session)
    db.commit()
    db.refresh(session)
    return {
        "id": session.id,
        "title": session.title,
        "created_at": session.created_at.isoformat()
    }

@router.get("")
def list_sessions(user_id: str = "dev_user_1", db: Session = Depends(get_db)):
    sessions = db.query(ChatSession).filter(ChatSession.user_id == user_id).order_by(ChatSession.updated_at.desc()).all()
    return [
        {
            "id": s.id,
            "title": s.title,
            "created_at": s.created_at.isoformat(),
            "updated_at": s.updated_at.isoformat()
        }
        for s in sessions
    ]

@router.get("/{session_id}/messages")
def get_session_messages(session_id: str, db: Session = Depends(get_db)):
    session = db.query(ChatSession).filter(ChatSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=404, detail="Chat session not found")
    messages = db.query(ChatMessage).filter(ChatMessage.session_id == session_id).order_by(ChatMessage.created_at.asc()).all()
    return [
        {
            "id": m.id,
            "sender": m.sender,
            "content": m.content,
            "created_at": m.created_at.isoformat()
        }
        for m in messages
    ]
