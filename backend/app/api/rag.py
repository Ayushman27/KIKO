from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from pydantic import BaseModel
from app.database.session import get_db
from app.rag.subsystem import rag_subsystem

router = APIRouter(prefix="/rag", tags=["RAG"])

class IndexFolderRequest(BaseModel):
    folder_path: str

class SearchDocumentsRequest(BaseModel):
    query: str

@router.post("/index")
def index_folder(req: IndexFolderRequest, db: Session = Depends(get_db)):
    res = rag_subsystem.index_folder(db, req.folder_path)
    return res

@router.post("/search")
def search_documents(req: SearchDocumentsRequest, db: Session = Depends(get_db)):
    res = rag_subsystem.search_documents(db, req.query)
    return {"query": req.query, "results": res}
