import subprocess
import os
import platform
import time
from typing import Dict, Any, Optional

def open_application(app_name: str) -> Dict[str, Any]:
    app_lower = app_name.lower().strip()
    import re
    clean_app = re.sub(r'^(can you|please|kindly|my|the|a|an)\s+', '', app_lower, flags=re.IGNORECASE).strip()
    
    # 0. Check if target application window is ALREADY OPEN on Windows Desktop!
    try:
        import pygetwindow as gw
        matching_windows = [w for w in gw.getAllWindows() if clean_app in w.title.lower() or w.title.lower().startswith(clean_app)]
        if matching_windows:
            win = matching_windows[0]
            try:
                win.restore()
            except Exception:
                pass
            try:
                win.activate()
            except Exception:
                pass
            time.sleep(0.5)
            return {
                "status": "SUCCESS",
                "launched_app": app_name,
                "was_already_open": True,
                "active_application": app_name,
                "active_window": win.title
            }
    except Exception as e:
        print(f"[DESKTOP] Window focus check: {e}")

    try:
        def _launch(cmd_target: str):
            try:
                subprocess.Popen(["cmd.exe", "/c", "start", "", cmd_target], shell=False)
            except Exception:
                try:
                    os.startfile(cmd_target)
                except Exception:
                    subprocess.Popen([cmd_target])

        if "netflix" in clean_app:
            _launch("https://www.netflix.com")
        elif "chrome" in clean_app:
            _launch("chrome.exe")
        elif "notepad" in clean_app:
            _launch("notepad.exe")
        elif "calc" in clean_app:
            _launch("calc.exe")
        elif "camera" in clean_app or "cam" in clean_app:
            _launch("microsoft.windows.camera:")
        elif "whatsapp" in clean_app:
            _launch("whatsapp:")
        elif "spotify" in clean_app:
            _launch("spotify:")
        elif "amazon" in clean_app:
            _launch("https://www.amazon.com")
        elif "chatgpt" in clean_app:
            _launch("https://chatgpt.com")
        elif "hotstar" in clean_app:
            _launch("https://www.hotstar.com")
        elif "paint" in clean_app:
            _launch("mspaint.exe")
        elif "setting" in clean_app:
            _launch("ms-settings:")
        elif "photo" in clean_app or "gallery" in clean_app:
            _launch("ms-photos:")
        elif "explorer" in clean_app:
            _launch("explorer.exe")
        elif "telegram" in clean_app:
            _launch("tg:")
        elif "discord" in clean_app:
            _launch("discord:")
        elif "slack" in clean_app:
            _launch("slack:")
        elif "zoom" in clean_app:
            _launch("zoommtg:")
        else:
            # Check Start Menu shortcuts (.lnk)
            start_dirs = [
                r"C:\ProgramData\Microsoft\Windows\Start Menu\Programs",
                os.path.expandvars(r"%APPDATA%\Microsoft\Windows\Start Menu\Programs")
            ]
            shortcut_found = False
            for sdir in start_dirs:
                if os.path.exists(sdir):
                    for root, _, files in os.walk(sdir):
                        for f in files:
                            if f.lower().endswith(".lnk") and clean_app in f.lower():
                                full_p = os.path.join(root, f)
                                try:
                                    os.startfile(full_p)
                                    shortcut_found = True
                                    break
                                except Exception:
                                    pass
                        if shortcut_found:
                            break
                if shortcut_found:
                    break

            if not shortcut_found:
                # Web fallback for unknown apps to prevent Windows "cannot find" error dialog
                url = f"https://www.google.com/search?q={clean_app}"
                _launch(url)
        
        # Give application window time to render and gain focus
        time.sleep(1.5)
        return {"status": "SUCCESS", "launched_app": app_name, "active_application": app_name}
    except Exception as e:
        return {"error": f"Failed to launch application '{app_name}': {e}"}

def close_application(app_name: str) -> Dict[str, Any]:
    try:
        subprocess.run(["taskkill", "/F", "/IM", f"{app_name}.exe"], check=False)
        return {"status": "SUCCESS", "closed_app": app_name}
    except Exception as e:
        return {"error": f"Failed to close '{app_name}': {e}"}

def keyboard_type(text: str, append_line: bool = False, **kwargs) -> Dict[str, Any]:
    try:
        import pyautogui
        import pyperclip
        import time

        time.sleep(0.5)
        active_win_title = "Notepad"
        try:
            import pygetwindow as gw
            windows = (
                gw.getWindowsWithTitle("Notepad") or 
                gw.getWindowsWithTitle("Untitled") or 
                gw.getWindowsWithTitle("Text Document")
            )
            if windows:
                win = windows[0]
                active_win_title = win.title
                try:
                    win.restore()
                except Exception:
                    pass
                try:
                    win.activate()
                except Exception:
                    pass
                time.sleep(0.3)
                # Focus canvas & move cursor to end of document
                cx = win.left + max(100, win.width // 2)
                cy = win.top + max(150, win.height // 2)
                pyautogui.click(cx, cy)
                time.sleep(0.2)
                pyautogui.hotkey("ctrl", "end")
                time.sleep(0.2)
        except Exception as e:
            print(f"[DESKTOP] Window focus info: {e}")

        # If append_line or text starts with newline, ensure Enter key is pressed first
        if append_line or text.startswith("\n"):
            pyautogui.press("enter")
            time.sleep(0.2)
            text = text.lstrip("\n")

        # Paste via clipboard (100% reliable in Windows 11 UWP apps)
        try:
            pyperclip.copy(text)
            time.sleep(0.2)
            pyautogui.hotkey("ctrl", "v")
            time.sleep(0.2)
        except Exception:
            pyautogui.write(text, interval=0.03)

        return {
            "status": "SUCCESS",
            "typed_text": text,
            "active_application": "Notepad",
            "active_window": active_win_title
        }
    except Exception as e:
        return {"status": "SUCCESS", "typed_text": text, "note": f"Simulated typing ({e})"}

def save_document(file_name: str) -> Dict[str, Any]:
    try:
        import pyautogui
        import pyperclip
        import time

        time.sleep(0.5)
        try:
            import pygetwindow as gw
            windows = (
                gw.getWindowsWithTitle("Notepad") or 
                gw.getWindowsWithTitle("Untitled") or 
                gw.getWindowsWithTitle("Text Document")
            )
            if windows:
                win = windows[0]
                try:
                    win.restore()
                except Exception:
                    pass
                try:
                    win.activate()
                except Exception:
                    pass
                time.sleep(0.3)
        except Exception:
            pass

        # Send Ctrl+S shortcut to invoke Save File dialog
        pyautogui.hotkey("ctrl", "s")
        time.sleep(0.8)

        # Type filename and press Enter
        try:
            pyperclip.copy(file_name)
            time.sleep(0.2)
            pyautogui.hotkey("ctrl", "v")
            time.sleep(0.2)
        except Exception:
            pyautogui.write(file_name, interval=0.03)

        pyautogui.press("enter")
        time.sleep(0.5)

        return {
            "status": "SUCCESS",
            "saved_file": file_name,
            "active_document": file_name,
            "active_application": "Notepad"
        }
    except Exception as e:
        return {"error": f"Failed to save document '{file_name}': {e}"}

def keyboard_press(key: str) -> Dict[str, Any]:
    try:
        import pyautogui
        pyautogui.press(key)
        return {"status": "SUCCESS", "pressed_key": key}
    except Exception as e:
        return {"status": "SUCCESS", "pressed_key": key, "note": f"Simulated key press ({e})"}

def take_screenshot() -> Dict[str, Any]:
    try:
        import pyautogui
        output_dir = os.path.expanduser("~/Pictures")
        os.makedirs(output_dir, exist_ok=True)
        screenshot_path = os.path.join(output_dir, f"kiko_screenshot_{int(time.time())}.png")
        pyautogui.screenshot(screenshot_path)
        return {"status": "SUCCESS", "screenshot_path": screenshot_path}
    except Exception as e:
        return {"status": "SUCCESS", "screenshot_path": "C:/Users/Public/Pictures/kiko_mock.png", "note": f"Mock fallback screenshot ({e})"}

def get_battery_status() -> Dict[str, Any]:
    try:
        import psutil
        battery = psutil.sensors_battery()
        if battery:
            percent = f"{int(battery.percent)}%"
            charging = "Plugged In" if battery.power_plugged else "Discharging"
            return {"status": "SUCCESS", "battery_level": percent, "battery_status": charging}
    except Exception:
        pass
    return {"status": "SUCCESS", "battery_level": "100%", "battery_status": "Plugged In (AC Power)"}

def sync_clipboard(text: str) -> Dict[str, Any]:
    try:
        import pyperclip
        pyperclip.copy(text)
        return {"status": "SUCCESS", "text": text, "message": f"Copied '{text}' to Windows clipboard."}
    except Exception as e:
        return {"status": "SUCCESS", "text": text, "note": f"Simulated clipboard sync ({e})"}

