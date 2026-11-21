import sys
import time
import argparse
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("desktop_type")

def focus_target_window(target_app: str = "notepad") -> bool:
    try:
        import pygetwindow as gw
        candidates = [
            w for w in gw.getAllWindows()
            if any(k in w.title.lower() for k in [target_app.lower(), "notepad", "untitled", "document", "editor"])
        ]
        if candidates:
            win = candidates[0]
            logger.info(f"Target window found: '{win.title}'")
            try:
                win.restore()
            except Exception:
                pass
            try:
                win.activate()
            except Exception:
                pass
            time.sleep(0.4)
            return True
        else:
            logger.warning(f"No specific window found for '{target_app}', targeting active window.")
            return False
    except Exception as e:
        logger.warning(f"Error focusing window: {e}")
        return False

def type_text(text: str, target_app: str = "notepad", append_line: bool = False) -> bool:
    try:
        import pyautogui
        import pyperclip
        import pygetwindow as gw
        pyautogui.FAILSAFE = False

        time.sleep(0.3)

        # 1. Focus target window
        focus_target_window(target_app)

        # 2. Click inside canvas to ensure edit focus
        try:
            candidates = [
                w for w in gw.getAllWindows()
                if any(k in w.title.lower() for k in [target_app.lower(), "notepad", "untitled", "document", "editor"])
            ]
            if candidates:
                win = candidates[0]
                cx = win.left + max(80, min(300, win.width // 2))
                cy = win.top + max(120, min(300, win.height // 2))
                pyautogui.click(cx, cy)
                time.sleep(0.2)
        except Exception:
            pass

        # 3. Append newline if requested
        if append_line or text.startswith("\n"):
            pyautogui.hotkey("ctrl", "end")
            time.sleep(0.1)
            pyautogui.press("enter")
            time.sleep(0.1)
            text = text.lstrip("\n")

        # 4. Paste via clipboard
        try:
            pyperclip.copy(text)
            time.sleep(0.2)
            pyautogui.hotkey("ctrl", "v")
            time.sleep(0.3)
            logger.info("Successfully pasted text into window via clipboard Ctrl+V")
            return True
        except Exception as pe:
            logger.warning(f"Clipboard paste failed ({pe}), falling back to direct write.")
            pyautogui.write(text, interval=0.02)
            return True

    except Exception as e:
        logger.error(f"Error in type_text: {e}")
        return False

def save_document(file_name: str, target_app: str = "notepad") -> bool:
    try:
        import pyautogui
        import pyperclip
        pyautogui.FAILSAFE = False

        focus_target_window(target_app)
        time.sleep(0.3)

        pyautogui.hotkey("ctrl", "s")
        time.sleep(0.8)

        pyperclip.copy(file_name)
        time.sleep(0.2)
        pyautogui.hotkey("ctrl", "v")
        time.sleep(0.2)
        pyautogui.press("enter")
        time.sleep(0.5)
        logger.info(f"Saved document as '{file_name}'")
        return True
    except Exception as e:
        logger.error(f"Error saving document: {e}")
        return False

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Desktop window text and save utility")
    parser.add_argument("--text", type=str, default="", help="Text to type/paste")
    parser.add_argument("--app", type=str, default="notepad", help="Target application name")
    parser.add_argument("--append", action="store_true", help="Append to end of document")
    parser.add_argument("--save", type=str, default="", help="Save document with filename")
    args = parser.parse_args()

    if args.save:
        ok = save_document(args.save, target_app=args.app)
    else:
        ok = type_text(args.text, target_app=args.app, append_line=args.append)
    sys.exit(0 if ok else 1)
