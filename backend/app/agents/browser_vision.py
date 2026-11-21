import base64
import logging
from typing import Dict, Any, Optional
import httpx
from playwright.async_api import Page, Error as PlaywrightError
from app.core.config import settings

logger = logging.getLogger("kiko.browser.vision")

class BrowserVision:
    """Handles screenshot capture and multimodal vision analysis via Gemini."""

    @staticmethod
    async def capture_screenshot(page: Page, full_page: bool = False) -> Dict[str, Any]:
        """Captures viewport screenshot and returns base64 PNG data along with metadata."""
        try:
            viewport = page.viewport_size or {"width": 1280, "height": 800}
            screenshot_bytes = await page.screenshot(full_page=full_page, type="png")
            b64_img = base64.b64encode(screenshot_bytes).decode("utf-8")
            
            return {
                "success": True,
                "url": page.url,
                "title": await page.title(),
                "viewport": viewport,
                "full_page": full_page,
                "image_base64": b64_img,
                "mime_type": "image/png",
                "byte_size": len(screenshot_bytes),
                "message": f"Captured screenshot of {page.url} ({viewport['width']}x{viewport['height']})"
            }
        except PlaywrightError as pe:
            logger.error(f"Screenshot capture failed: {pe}")
            return {
                "success": False,
                "url": page.url,
                "error": str(pe),
                "message": f"Failed to take screenshot: {str(pe)}"
            }

    @staticmethod
    async def analyze_screenshot(
        image_b64: str,
        question: str,
        api_key: Optional[str] = None,
        model: Optional[str] = None
    ) -> Dict[str, Any]:
        """Uses Gemini Multimodal API to analyze the captured browser screenshot."""
        key = api_key or getattr(settings, "GEMINI_API_KEY", "")
        if not key:
            return {
                "success": False,
                "error": "Gemini API key not configured for vision analysis."
            }

        candidate_models = [
            model or "gemini-3.5-flash-lite",
            "gemini-3.5-flash-lite",
            "gemini-3.5-flash",
            "gemini-3.8-flash",
            "gemini-flash-latest",
        ]
        seen = set()
        models = [m for m in candidate_models if not (m in seen or seen.add(m))]

        prompt_text = (
            "You are a browser automation visual assistant. Analyze the provided webpage screenshot.\n"
            f"User Question / Goal: {question}\n\n"
            "Provide:\n"
            "1. Visual Summary: Key sections, dialogs, modals, popups, or notices visible.\n"
            "2. Identified Elements: Names/locations of buttons, search boxes, input fields, and links relevant to the goal.\n"
            "3. State Verification: Did the last action succeed, is the page loading, or is an error/challenge visible?"
        )

        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"text": prompt_text},
                        {
                            "inline_data": {
                                "mime_type": "image/png",
                                "data": image_b64
                            }
                        }
                    ]
                }
            ]
        }

        async with httpx.AsyncClient() as client:
            for mod in models:
                model_path = mod if mod.startswith("models/") else f"models/{mod}"
                url = f"https://generativelanguage.googleapis.com/v1beta/{model_path}:generateContent?key={key}"
                try:
                    resp = await client.post(url, json=payload, timeout=40.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        analysis_text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                        return {
                            "success": True,
                            "analysis": analysis_text,
                            "model": mod
                        }
                    elif resp.status_code in [404, 500, 502, 503, 504]:
                        continue
                    else:
                        logger.warning(f"Vision API returned HTTP {resp.status_code}: {resp.text}")
                except Exception as e:
                    logger.error(f"Vision analysis error on {mod}: {e}")
                    continue

        return {
            "success": False,
            "error": "Failed to analyze screenshot via Gemini Vision API."
        }

browser_vision = BrowserVision()
