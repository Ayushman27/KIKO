from typing import Dict, Any, List, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from app.models.domain import MemoryItem

class MemoryManager:
    """Manages working memory, episodic history, and persistent user preferences."""
    
    def save_preference(self, db: Session, key: str, value: str, category: str = "preference") -> MemoryItem:
        existing = db.query(MemoryItem).filter(MemoryItem.category == category, MemoryItem.key == key).first()
        if existing:
            existing.value = value
            existing.updated_at = datetime.utcnow()
            db.commit()
            db.refresh(existing)
            return existing
        else:
            item = MemoryItem(category=category, key=key, value=value)
            db.add(item)
            db.commit()
            db.refresh(item)
            return item

    def get_preference(self, db: Session, key: str, category: str = "preference") -> Optional[str]:
        item = db.query(MemoryItem).filter(MemoryItem.category == category, MemoryItem.key == key).first()
        return item.value if item else None

    def list_memory(self, db: Session, category: Optional[str] = None) -> List[Dict[str, Any]]:
        query = db.query(MemoryItem)
        if category:
            query = query.filter(MemoryItem.category == category)
        items = query.all()
        return [
            {
                "id": item.id,
                "category": item.category,
                "key": item.key,
                "value": item.value,
                "updated_at": item.updated_at.isoformat() if item.updated_at else None
            }
            for item in items
        ]

memory_manager = MemoryManager()
