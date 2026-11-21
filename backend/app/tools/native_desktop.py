import os
import subprocess
import time
import webbrowser
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger("kiko.native_desktop")

def open_application(app_name: str) -> Dict[str, Any]:
    """
    Natively opens a Windows desktop application directly on the host machine.
    Handles Notepad, Calculator, Chrome, Explorer, Paint, Camera, Settings,
    plus Start Menu installed shortcuts.
    """
    import re
    app_lower = app_name.lower().strip()
    clean_app = re.sub(
        r'\b(can you|please|kindly|open|launch|start|run|in|on|my|the|a|an|laptop|pc|desktop|computer|windows|kiko|koko|coco|cico|co|ko|ki|eco|echo)\b',
        '',
        app_lower,
        flags=re.IGNORECASE
    ).strip()

    if not clean_app:
        clean_app = app_lower

    logger.info(f"[NATIVE_DESKTOP] Opening Windows application: '{clean_app}' (original: '{app_name}')")

    # 1. Check if window is already open using pygetwindow
    try:
        import pygetwindow as gw
        matching = [w for w in gw.getAllWindows() if clean_app in w.title.lower()]
        if matching:
            win = matching[0]
            try:
                win.restore()
                win.activate()
            except Exception:
                pass
            return {
                "status": "SUCCESS",
                "success": True,
                "message": f"Brought open application '{clean_app.title()}' to front.",
                "active_application": clean_app.title(),
                "active_window": win.title
            }
    except Exception:
        pass

    # 2. Known Windows Executables & URIs
    try:
        def _launch_cmd(target: str):
            try:
                subprocess.Popen(["cmd.exe", "/c", "start", "", target], shell=False)
            except Exception:
                try:
                    os.startfile(target)
                except Exception:
                    subprocess.Popen([target])

        if "notepad" in clean_app:
            _launch_cmd("notepad.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened Notepad on your laptop.", "active_application": "Notepad"}

        elif any(k in clean_app for k in ["calc", "calculator"]):
            _launch_cmd("calc.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened Calculator on your laptop.", "active_application": "Calculator"}

        elif any(k in clean_app for k in ["chrome", "google chrome"]):
            _launch_cmd("chrome.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened Google Chrome.", "active_application": "Google Chrome"}

        elif any(k in clean_app for k in ["paint", "mspaint"]):
            _launch_cmd("mspaint.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened Paint on your laptop.", "active_application": "Paint"}

        elif any(k in clean_app for k in ["camera", "cam"]):
            _launch_cmd("microsoft.windows.camera:")
            return {"status": "SUCCESS", "success": True, "message": "Opened Camera on your laptop.", "active_application": "Camera"}

        elif any(k in clean_app for k in ["setting", "settings"]):
            _launch_cmd("ms-settings:")
            return {"status": "SUCCESS", "success": True, "message": "Opened Windows Settings.", "active_application": "Settings"}

        elif any(k in clean_app for k in ["explorer", "file explorer", "my files", "files"]):
            _launch_cmd("explorer.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened File Explorer.", "active_application": "File Explorer"}

        elif any(k in clean_app for k in ["cmd", "command prompt"]):
            _launch_cmd("cmd.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened Command Prompt.", "active_application": "Command Prompt"}

        elif any(k in clean_app for k in ["terminal", "powershell"]):
            _launch_cmd("powershell.exe")
            return {"status": "SUCCESS", "success": True, "message": "Opened Terminal.", "active_application": "Terminal"}

        elif "whatsapp" in clean_app:
            _launch_cmd("whatsapp:")
            return {"status": "SUCCESS", "success": True, "message": "Opened WhatsApp.", "active_application": "WhatsApp"}

        elif "spotify" in clean_app:
            _launch_cmd("spotify:")
            return {"status": "SUCCESS", "success": True, "message": "Opened Spotify.", "active_application": "Spotify"}

        # Check known web services (Netflix, YouTube, Prime, Hotstar, ChatGPT, etc.)
        web_services = {
            "netflix": "https://www.netflix.com",
            "youtube": "https://www.youtube.com",
            "google": "https://www.google.com",
            "amazon": "https://www.amazon.com",
            "flipkart": "https://www.flipkart.com",
            "github": "https://github.com",
            "reddit": "https://www.reddit.com",
            "twitter": "https://x.com",
            "x": "https://x.com",
            "chatgpt": "https://chatgpt.com",
            "hotstar": "https://www.hotstar.com",
            "prime": "https://www.primevideo.com",
            "wikipedia": "https://www.wikipedia.org",
            "facebook": "https://www.facebook.com",
            "instagram": "https://www.instagram.com",
            "linkedin": "https://www.linkedin.com",
            "gmail": "https://mail.google.com",
            "twitch": "https://www.twitch.tv",
        }
        for ws, url in web_services.items():
            if ws in clean_app:
                _launch_cmd(url)
                return {"status": "SUCCESS", "success": True, "message": f"Opened {ws.title()} in your browser.", "active_application": ws.title(), "url": url}

        # 3. Search Windows Start Menu for shortcut files (.lnk)
        start_dirs = [
            r"C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
            os.path.expandvars(r"%APPDATA%\Microsoft\Windows\Start Menu\Programs")
        ]
        for sdir in start_dirs:
            if os.path.exists(sdir):
                for root, _, files in os.walk(sdir):
                    for f in files:
                        if f.lower().endswith(".lnk") and clean_app in f.lower():
                            full_path = os.path.join(root, f)
                            logger.info(f"[NATIVE_DESKTOP] Launching Start Menu shortcut: {full_path}")
                            _launch_cmd(full_path)
                            return {
                                "status": "SUCCESS",
                                "success": True,
                                "message": f"Opened {f[:-4]} on your laptop.",
                                "active_application": f[:-4]
                            }

        # 4. General fallback: if not an exe, open in browser to avoid Windows popup error
        if clean_app.endswith(".exe"):
            _launch_cmd(clean_app)
            return {"status": "SUCCESS", "success": True, "message": f"Launched {clean_app.title()}.", "active_application": clean_app.title()}
        elif "." in clean_app:
            _launch_cmd(f"https://{clean_app}")
            return {"status": "SUCCESS", "success": True, "message": f"Opened {clean_app} in browser.", "active_application": clean_app.title()}
        else:
            search_url = f"https://www.google.com/search?q={clean_app.replace(' ', '+')}"
            _launch_cmd(search_url)
            return {"status": "SUCCESS", "success": True, "message": f"Opened '{clean_app.title()}' in browser.", "active_application": clean_app.title()}

    except Exception as e:
        logger.error(f"[NATIVE_DESKTOP] Error opening application '{app_name}': {e}")
        return {"status": "FAILED", "success": False, "error": str(e), "message": f"Could not launch {app_name}: {e}"}


def close_application(app_name: str) -> Dict[str, Any]:
    import re
    clean = re.sub(r'^(close|kill|terminate|stop)\s+', '', app_name.lower().strip(), flags=re.IGNORECASE).strip()
    if not clean.endswith(".exe"):
        exe_name = f"{clean}.exe"
    else:
        exe_name = clean
    try:
        subprocess.run(["taskkill", "/F", "/IM", exe_name], capture_output=True, text=True)
        return {"status": "SUCCESS", "success": True, "message": f"Closed {clean.title()}."}
    except Exception as e:
        return {"status": "FAILED", "success": False, "error": str(e)}


def keyboard_type(text: str, append_line: bool = False, target_app: str = "notepad") -> Dict[str, Any]:
    """Types or pastes text into the target application window via native automation."""
    try:
        from app.tools.desktop_type import type_text
        ok = type_text(text, target_app=target_app, append_line=append_line)
        if ok:
            return {
                "status": "SUCCESS",
                "success": True,
                "typed": text,
                "active_application": target_app.title()
            }
    except Exception as e:
        logger.warning(f"[NATIVE_DESKTOP] desktop_type import/run error: {e}")

    try:
        import pyautogui
        import pyperclip
        pyautogui.FAILSAFE = False
        pyperclip.copy(text)
        time.sleep(0.2)
        pyautogui.hotkey('ctrl', 'v')
        return {"status": "SUCCESS", "success": True, "typed": text, "active_application": target_app.title()}
    except Exception as ex:
        logger.error(f"[NATIVE_DESKTOP] keyboard_type fallback failed: {ex}")
        return {"status": "FAILED", "success": False, "error": str(ex)}


def save_document(file_name: str, target_app: str = "notepad") -> Dict[str, Any]:
    """Saves the active document in the target application with the given file name."""
    try:
        from app.tools.desktop_type import save_document as dt_save
        ok = dt_save(file_name, target_app=target_app)
        if ok:
            return {
                "status": "SUCCESS",
                "success": True,
                "saved_file": file_name,
                "active_document": file_name,
                "active_application": target_app.title()
            }
    except Exception as e:
        logger.warning(f"[NATIVE_DESKTOP] save_document error: {e}")

    return {"status": "FAILED", "success": False, "error": "Unable to save document."}


def keyboard_press(key: str) -> Dict[str, Any]:
    try:
        import pyautogui
        pyautogui.FAILSAFE = False
        pyautogui.press(key.lower())
        return {"status": "SUCCESS", "success": True, "key": key}
    except Exception:
        key_map = {"enter": "{ENTER}", "tab": "{TAB}", "esc": "{ESC}", "space": " "}
        k = key_map.get(key.lower(), key)
        cmd = f"$ws = New-Object -ComObject WScript.Shell; $ws.SendKeys('{k}')"
        subprocess.run(["powershell", "-Command", cmd], capture_output=True)
        return {"status": "SUCCESS", "success": True, "key": key}


def take_screenshot() -> Dict[str, Any]:
    try:
        import pyautogui
        pyautogui.FAILSAFE = False
        from app.core.config import settings
        out_dir = os.path.join(os.getcwd(), "storage", "screenshots")
        os.makedirs(out_dir, exist_ok=True)
        fname = f"screenshot_{int(time.time())}.png"
        fpath = os.path.join(out_dir, fname)
        pyautogui.screenshot(fpath)
        return {"status": "SUCCESS", "success": True, "path": fpath, "filename": fname}
    except Exception as e:
        return {"status": "FAILED", "success": False, "error": str(e)}


def search_youtube(query: str) -> Dict[str, Any]:
    clean_q = (query or "").strip()
    if not clean_q or clean_q.lower() == "youtube":
        url = "https://www.youtube.com"
    else:
        url = f"https://www.youtube.com/results?search_query={clean_q.replace(' ', '+')}"
    
    try:
        subprocess.Popen(["cmd.exe", "/c", "start", "", url], shell=False)
    except Exception:
        webbrowser.open(url)

    return {"status": "SUCCESS", "success": True, "query": clean_q, "url": url}


def open_browser(url: str = "https://www.google.com") -> Dict[str, Any]:
    clean_url = (url or "https://www.google.com").strip()
    if not clean_url.startswith("http"):
        clean_url = f"https://{clean_url}"
    try:
        subprocess.Popen(["cmd.exe", "/c", "start", "", clean_url], shell=False)
        return {"status": "SUCCESS", "success": True, "url": clean_url, "message": f"Opened browser: {clean_url}"}
    except Exception as e:
        webbrowser.open(clean_url)
        return {"status": "SUCCESS", "success": True, "url": clean_url}


async def execute_native_desktop_tool(tool_name: str, params: Dict[str, Any]) -> Dict[str, Any]:
    """Dispatches a tool call directly to native Windows desktop APIs."""
    t = tool_name.lower().strip()
    if t in ["open_application", "launch_app"]:
        app = params.get("app_name") or params.get("name") or params.get("app") or ""
        return open_application(app)
    elif t in ["open_browser", "open_url", "search_web"]:
        url = params.get("url") or (f"https://www.google.com/search?q={params.get('query', '')}" if params.get('query') else "https://www.google.com")
        return open_browser(url)
    elif t in ["close_application", "kill_app"]:
        app = params.get("app_name") or params.get("name") or ""
        return close_application(app)
    elif t in ["keyboard_type", "type_text"]:
        text = params.get("text", "")
        append = params.get("append_line", False)
        app = params.get("app_name", "notepad")
        return keyboard_type(text, append_line=append, target_app=app)
    elif t in ["save_document", "save_file"]:
        fn = params.get("file_name") or params.get("name") or "document.txt"
        app = params.get("app_name", "notepad")
        return save_document(fn, target_app=app)
    elif t in ["keyboard_press", "press_key"]:
        key = params.get("key", "enter")
        return keyboard_press(key)
    elif t in ["take_screenshot", "screenshot"]:
        return take_screenshot()
    elif t in ["search_youtube", "play_youtube"]:
        q = params.get("query") or params.get("search_query") or ""
        return search_youtube(q)

    return {"status": "UNHANDLED", "success": False, "tool": tool_name}
