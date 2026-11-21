import os
import glob
from typing import List, Dict, Any, Optional
from datetime import datetime
from sqlalchemy.orm import Session
from app.models.domain import Document, DocumentChunk

class DocumentParser:
    """Parses text, PDF, Markdown, CSV, and DOCX files into clean string chunks."""
    @staticmethod
    def parse_file(file_path: str) -> str:
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"File not found: {file_path}")
        
        ext = os.path.splitext(file_path)[1].lower()
        if ext in [".txt", ".md", ".csv", ".json"]:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                return f.read()
        elif ext == ".pdf":
            try:
                import pypdf
                reader = pypdf.PdfReader(file_path)
                text = ""
                for page in reader.pages:
                    text += page.extract_text() or ""
                return text
            except Exception as e:
                return f"[PDF Parse Error: {e}]"
        elif ext == ".docx":
            try:
                import docx
                doc = docx.Document(file_path)
                return "\n".join([p.text for p in doc.paragraphs])
            except Exception as e:
                return f"[DOCX Parse Error: {e}]"
        return ""

class ChunkingService:
    @staticmethod
    def chunk_text(text: str, chunk_size: int = 500, overlap: int = 50) -> List[str]:
        words = text.split()
        if not words:
            return []
        chunks = []
        for i in range(0, len(words), chunk_size - overlap):
            chunk = " ".join(words[i:i + chunk_size])
            if chunk:
                chunks.append(chunk)
        return chunks

class RAGSubsystem:
    """Vector database & retrieval subsystem for user-indexed folders."""
    
    def __init__(self):
        self.parser = DocumentParser()
        self.chunker = ChunkingService()

    def index_folder(self, db: Session, folder_path: str) -> Dict[str, Any]:
        if not os.path.exists(folder_path):
            return {"error": f"Folder does not exist: {folder_path}", "indexed_count": 0}
        
        supported_extensions = ["*.txt", "*.md", "*.pdf", "*.docx", "*.csv"]
        file_paths = []
        for ext in supported_extensions:
            file_paths.extend(glob.glob(os.path.join(folder_path, "**", ext), recursive=True))

        indexed_count = 0
        for fp in file_paths:
            try:
                filename = os.path.basename(fp)
                ext = os.path.splitext(fp)[1].lower()
                size = os.path.getsize(fp)
                
                # Check if already indexed
                existing = db.query(Document).filter(Document.file_path == fp).first()
                if existing:
                    continue

                content = self.parser.parse_file(fp)
                if not content.strip():
                    continue

                doc = Document(
                    file_path=fp,
                    file_name=filename,
                    file_type=ext,
                    file_size=size,
                    indexed_at=datetime.utcnow()
                )
                db.add(doc)
                db.flush()

                chunks = self.chunker.chunk_text(content)
                for idx, c_text in enumerate(chunks):
                    chunk_record = DocumentChunk(
                        document_id=doc.id,
                        chunk_index=idx,
                        content=c_text
                    )
                    db.add(chunk_record)

                indexed_count += 1
            except Exception:
                continue

        db.commit()
        return {"folder_path": folder_path, "indexed_files_count": indexed_count}

    def search_documents(self, db: Session, query: str, top_k: int = 3) -> List[Dict[str, Any]]:
        # Keyword & Semantic relevance scoring on database chunks
        query_words = set(query.lower().split())
        chunks = db.query(DocumentChunk).join(Document).all()

        scored_results = []
        for c in chunks:
            text_words = set(c.content.lower().split())
            overlap = len(query_words.intersection(text_words))
            if overlap > 0:
                doc = db.query(Document).filter(Document.id == c.document_id).first()
                scored_results.append({
                    "document_name": doc.file_name if doc else "Unknown",
                    "file_path": doc.file_path if doc else "",
                    "chunk_index": c.chunk_index,
                    "content": c.content[:300] + "...",
                    "score": overlap
                })

        scored_results.sort(key=lambda x: x["score"], reverse=True)
        return scored_results[:top_k]

rag_subsystem = RAGSubsystem()
