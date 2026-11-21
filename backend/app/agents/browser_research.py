import datetime
import logging
from typing import Dict, Any, List, Optional

logger = logging.getLogger("kiko.browser.research")

class ResearchSource:
    def __init__(self, title: str, url: str, content: str, step: int):
        self.title = title
        self.url = url
        self.content = content
        self.step = step
        self.timestamp = datetime.datetime.utcnow().isoformat()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "title": self.title,
            "url": self.url,
            "excerpt": (self.content[:400] + "...") if len(self.content) > 400 else self.content,
            "character_count": len(self.content),
            "step": self.step,
            "timestamp": self.timestamp
        }

class ResearchMemoryManager:
    """Tracks sources, extracted passages, and visited evidence across multi-step research tasks."""

    def __init__(self):
        # Maps task_id -> List[ResearchSource]
        self._task_sources: Dict[str, List[ResearchSource]] = {}

    def add_source(self, task_id: str, title: str, url: str, content: str, step: int):
        if not url or url.startswith("about:"):
            return
        if task_id not in self._task_sources:
            self._task_sources[task_id] = []
        
        # Avoid duplicate URL entries for the same task
        existing = next((s for s in self._task_sources[task_id] if s.url == url), None)
        if existing:
            # Update content if newer content is longer
            if len(content) > len(existing.content):
                existing.content = content
                existing.title = title or existing.title
            return

        source = ResearchSource(title=title, url=url, content=content, step=step)
        self._task_sources[task_id].append(source)
        logger.info(f"[RESEARCH {task_id}] Added genuine source #{len(self._task_sources[task_id])}: '{title}' ({url})")

    def get_sources(self, task_id: str) -> List[Dict[str, Any]]:
        sources = self._task_sources.get(task_id, [])
        return [s.to_dict() for s in sources]

    def build_research_context(self, task_id: str, max_chars: int = 5000) -> str:
        """Compresses collected evidence into a clean, concise research context for Gemini."""
        sources = self._task_sources.get(task_id, [])
        if not sources:
            return "No web sources visited yet."

        context_parts = []
        chars_used = 0
        for s in sources:
            snippet = s.content[:1500] if len(s.content) > 1500 else s.content
            entry = f"--- Source: {s.title} ({s.url}) ---\n{snippet}\n"
            if chars_used + len(entry) > max_chars:
                break
            context_parts.append(entry)
            chars_used += len(entry)

        return "\n".join(context_parts)

    def clear(self, task_id: str):
        self._task_sources.pop(task_id, None)

research_memory = ResearchMemoryManager()
