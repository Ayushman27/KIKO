import os

BACKEND_URL = os.getenv("WINDOWS_AGENT_BACKEND_URL", "http://127.0.0.1:8000")
WS_URL = os.getenv("WINDOWS_AGENT_WS_URL", "ws://127.0.0.1:8000/ws/agent")
DEVICE_NAME = os.getenv("DEVICE_NAME", "Ayushman's Windows Laptop")
DEVICE_ID = "windows_laptop_daemon_1"
AUTH_TOKEN = os.getenv("DEVICE_AUTH_TOKEN", "dev_device_token_secret_12345")
def _get_documents_dir() -> str:
    onedrive_docs = os.path.expanduser("~/OneDrive/Documents")
    if os.path.exists(onedrive_docs):
        return onedrive_docs
    return os.path.expanduser("~/Documents")

USER_DOCUMENTS_DIR = _get_documents_dir()
