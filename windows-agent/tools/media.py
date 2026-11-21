import subprocess
from typing import Dict, Any

def search_youtube(query: str = "") -> Dict[str, Any]:
    q = (query or "").strip()
    if not q or q.lower() == "youtube":
        url = "https://www.youtube.com"
    else:
        url = f"https://www.youtube.com/results?search_query={q.replace(' ', '+')}"
    try:
        subprocess.Popen(["cmd.exe", "/c", "start", "", url], shell=False)
        return {"status": "SUCCESS", "query": q, "url": url}
    except Exception as e:
        return {"error": f"Failed to launch YouTube: {e}"}

def open_browser(url: str = "https://www.google.com", query: str = "", **kwargs) -> Dict[str, Any]:
    target_url = (url or "").strip()
    if not target_url:
        q = (query or "").strip()
        if q:
            target_url = f"https://www.google.com/search?q={q.replace(' ', '+')}"
        else:
            target_url = "https://www.google.com"

    if not target_url.startswith("http"):
        target_url = f"https://{target_url}"

    try:
        subprocess.Popen(["cmd.exe", "/c", "start", "", target_url], shell=False)
        return {"status": "SUCCESS", "url": target_url}
    except Exception as e:
        return {"error": f"Failed to open browser: {e}"}
