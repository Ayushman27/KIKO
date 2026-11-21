from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from app.database.session import get_db
from app.memory.manager import memory_manager

router = APIRouter(prefix="/memory", tags=["Memory"])

class MemorySaveRequest(BaseModel):
    category: str
    key: str
    value: str

@router.get("")
def list_memory(category: Optional[str] = None, db: Session = Depends(get_db)):
    return memory_manager.list_memory(db, category)

@router.post("")
def save_memory(req: MemorySaveRequest, db: Session = Depends(get_db)):
    item = memory_manager.save_preference(db, req.key, req.value, req.category)
    return {"status": "SUCCESS", "id": item.id, "key": item.key, "value": item.value}
