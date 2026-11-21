import re
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime

logger = logging.getLogger("kiko.context")

class ActiveContext:
    def __init__(self, user_id: str = "default_user"):
        self.user_id = user_id
        self.active_application: Optional[str] = None
        self.active_window: Optional[str] = None
        self.active_document: Optional[str] = None
        self.active_file_path: Optional[str] = None
        self.active_folder: Optional[str] = None
        self.active_browser: Optional[str] = None
        self.active_url: Optional[str] = None
        self.last_action: Optional[str] = None
        self.last_command: Optional[str] = None
        self.last_tool: Optional[str] = None
        self.last_tool_result: Optional[Dict[str, Any]] = None
        self.entities: Dict[str, Any] = {}
        self.session_status: str = "ACTIVE"
        self.last_updated: datetime = datetime.utcnow()

    def update(self, updates: Dict[str, Any]):
        for key, value in updates.items():
            if value is not None and hasattr(self, key):
                setattr(self, key, value)
        self.last_updated = datetime.utcnow()
        logger.info(f"[CONTEXT] Updated active context for '{self.user_id}': App='{self.active_application}', Doc='{self.active_document}', LastAction='{self.last_action}'")

    def to_dict(self) -> Dict[str, Any]:
        return {
            "active_application": self.active_application,
            "active_window": self.active_window,
            "active_document": self.active_document,
            "active_file_path": self.active_file_path,
            "active_folder": self.active_folder,
            "active_browser": self.active_browser,
            "active_url": self.active_url,
            "last_action": self.last_action,
            "last_command": self.last_command,
            "last_tool": self.last_tool,
            "last_tool_result": self.last_tool_result,
            "entities": self.entities,
            "session_status": self.session_status,
            "last_updated": self.last_updated.isoformat()
        }

class ActiveContextManager:
    def __init__(self):
        self._contexts: Dict[str, ActiveContext] = {}

    def get_context(self, user_id: str = "default_user") -> ActiveContext:
        if user_id not in self._contexts:
            self._contexts[user_id] = ActiveContext(user_id=user_id)
        return self._contexts[user_id]

    def update_context(self, user_id: str, updates: Dict[str, Any]):
        ctx = self.get_context(user_id)
        ctx.update(updates)

    def classify_intent(self, command: str, ctx: ActiveContext) -> str:
        text_lower = command.lower().strip()
        
        # Pronouns or reference terms indicating continuation
        continuation_patterns = [
            r'\b(it|this|that|there|below it|above it|next line|same file|same notepad|same document|same app|the previous one|below|save it)\b'
        ]
        
        has_reference = any(re.search(pat, text_lower) for pat in continuation_patterns)
        
        if has_reference and ctx.active_application:
            return "CONTINUATION"
        elif any(k in text_lower for k in ["no,", "actually", "instead", "change"]):
            return "MODIFICATION"
        elif any(k in text_lower for k in ["open", "launch", "create new"]) and not any(k in text_lower for k in ["below", "same"]):
            return "NEW_TASK"
        elif ctx.active_application and any(k in text_lower for k in ["write", "type", "add", "append", "save"]):
            return "CONTINUATION"
        else:
            return "NEW_TASK"

    def resolve_references(self, command: str, user_id: str = "default_user") -> Dict[str, Any]:
        """
        Resolves pronouns ('it', 'this', 'below it', 'same file', 'there') 
        using current Active Context into structured intent description.
        """
        ctx = self.get_context(user_id)
        intent_category = self.classify_intent(command, ctx)
        text_lower = command.lower().strip()
        resolved_command = command

        logger.info(f"[RESOLVER] user_id='{user_id}', active_app='{ctx.active_application}', raw='{command}' -> Category: '{intent_category}', Resolved: '{resolved_command}'")

        target_app = ctx.active_application if intent_category in ["CONTINUATION", "MODIFICATION"] else None
        target_doc = ctx.active_document if intent_category in ["CONTINUATION", "MODIFICATION"] else None
        is_append = False

        if intent_category in ["CONTINUATION", "MODIFICATION"]:
            if "below" in text_lower or "next line" in text_lower:
                is_append = True
            
            # Replace pronouns with concrete app/doc terms for downstream tools
            if re.search(r'\b(it|this|that|same notepad|same document|same file)\b', text_lower):
                if ctx.active_application:
                    resolved_command = re.sub(r'\b(it|this|that|same notepad|same document|same file)\b', f"in {ctx.active_application}", command, flags=re.IGNORECASE)
            
            if "there" in text_lower and ctx.active_folder:
                resolved_command = re.sub(r'\bthere\b', f"in {ctx.active_folder}", resolved_command, flags=re.IGNORECASE)

            # Ensure active_application is explicitly in resolved_command so Router & Planner target the active app!
            if ctx.active_application and ctx.active_application.lower() not in resolved_command.lower():
                resolved_command = f"{resolved_command} in {ctx.active_application}"

        # Device selection continuation handling (e.g. user sends "in my laptop" following "open youtube and play hi")
        is_device_spec_only = bool(re.match(r'^(?:in|on|at|for|to)?\s*(?:my\s+)?(?:laptop|pc|desktop|phone|mobile|android)$', text_lower))
        if is_device_spec_only and ctx.last_command:
            resolved_command = f"{ctx.last_command} {command}"
            logger.info(f"[RESOLVER] Merged device choice with last command: '{resolved_command}'")

        return {
            "category": intent_category,
            "raw_command": command,
            "resolved_command": resolved_command,
            "target_app": target_app or ("notepad" if "notepad" in text_lower else None),
            "target_doc": target_doc,
            "is_append": is_append,
            "active_context": ctx.to_dict()
        }

active_context_manager = ActiveContextManager()
