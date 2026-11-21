import abc
import logging
from typing import Dict, Any, List

logger = logging.getLogger("kiko.communication")

class EmailProvider(abc.ABC):
    @abc.abstractmethod
    async def send_email(self, recipient: str, subject: str, body: str) -> bool:
        pass

    @abc.abstractmethod
    async def search_email(self, query: str) -> List[Dict[str, Any]]:
        pass

class GmailProvider(EmailProvider):
    async def send_email(self, recipient: str, subject: str, body: str) -> bool:
        logger.info(f"[GmailProvider] Email drafted for {recipient}: {subject}")
        return True

    async def search_email(self, query: str) -> List[Dict[str, Any]]:
        return [{"from": "client@example.com", "subject": f"Inquiry about {query}", "snippet": "Hello, following up on..."}]

class OutlookProvider(EmailProvider):
    async def send_email(self, recipient: str, subject: str, body: str) -> bool:
        logger.info(f"[OutlookProvider] Email drafted for {recipient}: {subject}")
        return True

    async def search_email(self, query: str) -> List[Dict[str, Any]]:
        return []

class CommunicationAgent:
    """Communication agent supporting configurable transparent reply policies."""
    
    def __init__(self, provider: EmailProvider = None):
        self.provider = provider or GmailProvider()
        self.reply_policy = "DRAFT_ONLY" # AUTO_REPLY, DRAFT_ONLY, ALWAYS_ASK

    async def draft_response(self, incoming_msg: str, sender: str) -> Dict[str, Any]:
        draft_text = f"Hi {sender}, I am Ayushman's AI assistant. I have received your message ('{incoming_msg}') and notified him."
        return {
            "sender": sender,
            "incoming_message": incoming_msg,
            "draft_reply": draft_text,
            "policy": self.reply_policy,
            "requires_approval": True
        }

communication_agent = CommunicationAgent()
