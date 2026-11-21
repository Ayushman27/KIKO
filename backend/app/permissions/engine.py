from enum import Enum
from typing import Dict, Any

class PermissionLevel(str, Enum):
    LOW = "LOW"            # Non-destructive (read files, create folders, open youtube)
    MEDIUM = "MEDIUM"      # Low-impact actions (move file, send draft, download)
    HIGH = "HIGH"          # High-impact actions (delete files, send email, submit job application)
    CRITICAL = "CRITICAL"  # High-risk (financial, system config, password change)

class PermissionEngine:
    def __init__(self):
        # User dynamic override policy map
        self.auto_approved_categories = {"File", "Media", "Desktop"}
        self.always_ask_levels = {PermissionLevel.HIGH, PermissionLevel.CRITICAL}

    def requires_approval(self, permission_level: PermissionLevel, tool_name: str, parameters: Dict[str, Any]) -> bool:
        if permission_level in self.always_ask_levels:
            return True
        if tool_name in ["delete_file", "send_email", "submit_job_application", "execute_system_command"]:
            return True
        return False

permission_engine = PermissionEngine()
