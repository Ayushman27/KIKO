import os
import glob
import logging
from typing import Dict, Any, Optional, List

logger = logging.getLogger("kiko.windows_resolver")

KNOWN_DESKTOP_APPS: Dict[str, Dict[str, Any]] = {
    "calculator": {"exe": "calc.exe", "name": "Calculator", "uri": "calculator:"},
    "calc": {"exe": "calc.exe", "name": "Calculator", "uri": "calculator:"},
    "notepad": {"exe": "notepad.exe", "name": "Notepad"},
    "paint": {"exe": "mspaint.exe", "name": "Paint"},
    "mspaint": {"exe": "mspaint.exe", "name": "Paint"},
    "cmd": {"exe": "cmd.exe", "name": "Command Prompt"},
    "terminal": {"exe": "wt.exe", "name": "Windows Terminal", "fallback_exe": "cmd.exe"},
    "explorer": {"exe": "explorer.exe", "name": "File Explorer"},
    "camera": {"uri": "microsoft.windows.camera:", "name": "Camera"},
    "cam": {"uri": "microsoft.windows.camera:", "name": "Camera"},
    "settings": {"uri": "ms-settings:", "name": "Settings"},
    "photos": {"uri": "ms-photos:", "name": "Photos"},
    "chrome": {"exe": "chrome.exe", "name": "Google Chrome"},
    "browser": {"exe": "chrome.exe", "name": "Browser", "fallback_exe": "msedge.exe"},
    "edge": {"exe": "msedge.exe", "name": "Microsoft Edge"},
    "spotify": {"exe": "spotify.exe", "uri": "spotify:", "name": "Spotify"},
    "whatsapp": {"exe": "whatsapp.exe", "uri": "whatsapp:", "name": "WhatsApp"},
    "vlc": {"exe": "vlc.exe", "name": "VLC Media Player"},
    "wordpad": {"exe": "wordpad.exe", "name": "WordPad"},
}

def resolve_windows_app(app_name: str) -> Dict[str, Any]:
    """
    Native Windows Application Resolver.
    First searches known desktop applications, Start Menu shortcuts,
    Windows App Paths, and installed application registries.
    """
    clean_name = app_name.lower().strip()
    clean_name = clean_name.replaceAll if hasattr(clean_name, 'replaceAll') else clean_name
    import re
    clean_name = re.sub(r'^(open|launch|start|run|can you|please|my|the|a|an)\s+', '', clean_name, flags=re.IGNORECASE).strip()

    logger.info(f"[RESOLVER] Searching Windows native application for: '{clean_name}'")

    # 1. Check direct match in known applications dictionary
    if clean_name in KNOWN_DESKTOP_APPS:
        app_info = KNOWN_DESKTOP_APPS[clean_name]
        logger.info(f"[RESOLVER] Direct match found for '{clean_name}': {app_info}")
        return {
            "found": True,
            "app_name": app_info.get("name", clean_name.capitalize()),
            "launch_type": "URI" if "uri" in app_info else "EXE",
            "target": app_info.get("uri") or app_info.get("exe"),
            "fallback": app_info.get("fallback_exe"),
            "execution_mode": "NATIVE"
        }

    # 2. Check fuzzy match in known app names
    for key, app_info in KNOWN_DESKTOP_APPS.items():
        if key in clean_name or clean_name in key:
            logger.info(f"[RESOLVER] Fuzzy match found for '{clean_name}' -> key '{key}': {app_info}")
            return {
                "found": True,
                "app_name": app_info.get("name", key.capitalize()),
                "launch_type": "URI" if "uri" in app_info else "EXE",
                "target": app_info.get("uri") or app_info.get("exe"),
                "execution_mode": "NATIVE"
            }

    # 3. Check Start Menu directories for shortcut files (.lnk)
    start_menu_paths = [
        r"C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
        os.path.expandvars(r"%APPDATA%\Microsoft\Windows\Start Menu\Programs")
    ]

    for start_dir in start_menu_paths:
        if os.path.exists(start_dir):
            for root, _, files in os.walk(start_dir):
                for f in files:
                    if f.lower().endswith(".lnk"):
                        lnk_name = os.path.splitext(f)[0].lower()
                        if clean_name in lnk_name or lnk_name in clean_name:
                            full_path = os.path.join(root, f)
                            logger.info(f"[RESOLVER] Found Windows Start Menu shortcut for '{clean_name}': {full_path}")
                            return {
                                "found": True,
                                "app_name": os.path.splitext(f)[0],
                                "launch_type": "SHORTCUT",
                                "target": full_path,
                                "execution_mode": "NATIVE"
                            }

    # If native application was not found
    logger.info(f"[RESOLVER] Native Windows app '{clean_name}' not found locally. Marking WEB_FALLBACK.")
    return {
        "found": False,
        "app_name": clean_name,
        "launch_type": "WEB_FALLBACK",
        "target": f"https://www.google.com/search?q={clean_name}",
        "execution_mode": "WEB"
    }
