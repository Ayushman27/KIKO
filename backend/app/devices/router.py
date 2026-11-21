import re
import logging
from typing import Dict, Any, List, Optional
from app.devices.registry import device_registry, Device
from app.tools.windows_app_resolver import resolve_windows_app

logger = logging.getLogger("kiko.router")

class RouteResult:
    def __init__(
        self,
        origin_device: str,
        target_device: str,
        device_id: Optional[str] = None,
        intent: str = "GENERAL",
        app_name: str = "",
        required_capability: str = "general",
        execution_mode: str = "NATIVE",
        confidence: float = 1.0,
        is_offline_error: bool = False,
        error_message: str = "",
        is_ambiguous: bool = False,
        ambiguous_prompt: str = "",
        ambiguous_options: List[str] = None
    ):
        self.origin_device = origin_device
        self.target_device = target_device
        self.device_id = device_id
        self.intent = intent
        self.app_name = app_name
        self.required_capability = required_capability
        self.execution_mode = execution_mode
        self.confidence = float(confidence)
        self.is_offline_error = is_offline_error
        self.error_message = error_message
        self.is_ambiguous = is_ambiguous
        self.ambiguous_prompt = ambiguous_prompt
        self.ambiguous_options = ambiguous_options or []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "origin_device": self.origin_device,
            "target_device": self.target_device,
            "device_id": self.device_id,
            "intent": self.intent,
            "app_name": self.app_name,
            "required_capability": self.required_capability,
            "execution_mode": self.execution_mode,
            "confidence": self.confidence,
            "is_offline_error": self.is_offline_error,
            "error_message": self.error_message,
            "is_ambiguous": self.is_ambiguous,
            "ambiguous_prompt": self.ambiguous_prompt,
            "ambiguous_options": self.ambiguous_options
        }

class DeviceRouter:
    """Central Device Intent & Task Routing Service."""

    PHONE_KEYWORDS = [
        "phone", "my phone", "on phone", "in phone", "from phone", "phone's", 
        "mobile", "on my mobile", "smartphone", "on my smartphone", "in my phone",
        "phone camera", "mobile phone", "my mobile"
    ]

    LAPTOP_KEYWORDS = [
        "laptop", "my laptop", "on laptop", "in laptop", "pc", "my pc", 
        "computer", "my computer", "desktop", "on my desktop", "windows", "windows pc"
    ]

    def extract_intent(self, command: str) -> Dict[str, Any]:
        text = command.lower().strip()
        
        # Determine action intent type
        intent = "GENERAL"
        capability = "general"
        app_name = ""

        if "camera" in text or "take photo" in text or "take a photo" in text:
            intent = "OPEN_APP"
            capability = "camera"
            app_name = "camera"
        elif "youtube" in text:
            intent = "SEARCH_YOUTUBE"
            capability = "apps"
            app_name = "youtube"
        elif any(k in text for k in ["calculator", "calc"]):
            intent = "OPEN_APP"
            capability = "apps"
            app_name = "calculator"
        elif "whatsapp" in text:
            intent = "OPEN_APP"
            capability = "apps"
            app_name = "whatsapp"
        elif "spotify" in text:
            intent = "OPEN_APP"
            capability = "apps"
            app_name = "spotify"
        elif "instagram" in text:
            intent = "OPEN_APP"
            capability = "apps"
            app_name = "instagram"
        elif "notepad" in text:
            intent = "OPEN_APP"
            capability = "apps"
            app_name = "notepad"
        elif "chrome" in text or "browser" in text or any(ws in text for ws in ["netflix", "amazon", "flipkart", "github", "reddit", "twitter", "chatgpt", "hotstar", "wikipedia", "prime video"]):
            intent = "OPEN_BROWSER"
            capability = "browser"
            app_name = "browser"
        elif any(k in text for k in ["open", "launch", "start", "run", "write", "type", "add", "save"]):
            intent = "OPEN_APP"
            capability = "apps"
            match = re.search(r'(?:open|launch|start|run|write|type|add|save)\s+(?:the\s+|my\s+|a\s+|an\s+|in\s+)?([a-zA-Z0-9_\-\.]+)', text)
            raw = match.group(1).strip() if match else "app"
            app_name = re.sub(r'\b(app|apps|in|on|my|the|a|an|phone|mobile|laptop|pc|desktop|kiko|koko|coco|cico|co|ko|ki|eco|echo)\b', '', raw, flags=re.IGNORECASE).strip() or raw

        return {
            "intent": intent,
            "capability": capability,
            "app_name": app_name
        }

    def route_command(
        self,
        user_id: str,
        command: str,
        origin_device: str = "BROWSER",
        session_context: Optional[dict] = None
    ) -> RouteResult:
        text_lower = command.lower().strip()
        intent_info = self.extract_intent(command)
        intent = intent_info["intent"]
        capability = intent_info["capability"]
        app_name = intent_info["app_name"]

        logger.info(f"[ROUTER] Routing command: '{command}' (Origin: {origin_device})")

        # ----------------------------------------------------
        # PRIORITY 1: Explicit device mentioned by user
        # ----------------------------------------------------
        # Clean text by removing search terms that contain 'phone' as part of another word (e.g. iphone, microphone, headphone)
        clean_text_for_device_matching = re.sub(r'\b(iphone|microphone|headphone|earphone|cellphone|telephone|gramophone)\b', '', text_lower, flags=re.IGNORECASE)

        is_phone_explicit = any(re.search(r'\b' + re.escape(kw) + r'\b', clean_text_for_device_matching, re.IGNORECASE) for kw in self.PHONE_KEYWORDS)
        is_laptop_explicit = any(re.search(r'\b' + re.escape(kw) + r'\b', text_lower, re.IGNORECASE) for kw in self.LAPTOP_KEYWORDS)

        # Check explicit prepositional target patterns (e.g., "in laptop", "on laptop", "on my pc" vs "in phone", "in my phone")
        laptop_target_match = re.search(r'\b(in|on|from|to|my)\s+(laptop|pc|desktop|computer|windows)\b', text_lower, re.IGNORECASE)
        phone_target_match = re.search(r'\b(in|on|from|to|my)\s+(phone|mobile|android|smartphone)\b', clean_text_for_device_matching, re.IGNORECASE)

        if laptop_target_match and not phone_target_match:
            is_phone_explicit = False
            is_laptop_explicit = True
        elif phone_target_match and not laptop_target_match:
            is_phone_explicit = True
            is_laptop_explicit = False

        if is_phone_explicit:
            logger.info("[ROUTER] Explicit target detected: PHONE")
            phone_devices = device_registry.get_devices_by_type("ANDROID_PHONE", online_only=True) + device_registry.get_devices_by_type("MOBILE", online_only=True)
            if not phone_devices:
                from app.websocket.manager import manager as ws_manager
                if ws_manager.mobile_clients:
                    dev = device_registry.register_device("mobile_app", "ANDROID_PHONE", "Ayushman's Phone", "android", ["camera", "microphone", "apps", "browser", "notifications"])
                    phone_devices = [dev]

            if not phone_devices:
                # Phone is OFFLINE! Crucial Rule 11: Do NOT automatically switch devices without permission!
                logger.warning("[ROUTER] User explicitly requested Phone, but no phone device is online!")
                return RouteResult(
                    origin_device=origin_device,
                    target_device="ANDROID_PHONE",
                    is_offline_error=True,
                    error_message="Your phone is currently offline. Please connect it first.",
                    intent=intent,
                    app_name=app_name,
                    required_capability=capability
                )
            target_dev = phone_devices[0]
            return RouteResult(
                origin_device=origin_device,
                target_device=target_dev.device_type,
                device_id=target_dev.device_id,
                intent=intent,
                app_name=app_name,
                required_capability=capability,
                execution_mode="NATIVE"
            )

        if is_laptop_explicit:
            logger.info("[ROUTER] Explicit target detected: LAPTOP / WINDOWS_PC")
            laptop_devices = device_registry.get_devices_by_type("WINDOWS_PC", online_only=True)
            if not laptop_devices:
                logger.warning("[ROUTER] User explicitly requested Laptop, but no Windows PC is online!")
                return RouteResult(
                    origin_device=origin_device,
                    target_device="WINDOWS_PC",
                    is_offline_error=True,
                    error_message="Your laptop is currently offline. Please connect it first.",
                    intent=intent,
                    app_name=app_name,
                    required_capability=capability
                )
            target_dev = laptop_devices[0]
            return RouteResult(
                origin_device=origin_device,
                target_device=target_dev.device_type,
                device_id=target_dev.device_id,
                intent=intent,
                app_name=app_name,
                required_capability=capability,
                execution_mode="NATIVE"
            )

        # ----------------------------------------------------
        # PRIORITY 2: Context of current task/session chain
        # ----------------------------------------------------
        from app.context.manager import active_context_manager
        ctx = active_context_manager.get_context(user_id)

        pref_device = None
        if session_context and session_context.get("preferred_target_device"):
            pref_device = session_context["preferred_target_device"].upper()
        elif ctx and ctx.active_application:
            pref_device = "WINDOWS_PC"

        if pref_device:
            logger.info(f"[ROUTER] Using active context target device: {pref_device}")
            matched_devices = device_registry.get_devices_by_type(pref_device, online_only=True)
            if matched_devices:
                target_dev = matched_devices[0]
                return RouteResult(
                    origin_device=origin_device,
                    target_device=target_dev.device_type,
                    device_id=target_dev.device_id,
                    intent=intent,
                    app_name=app_name,
                    required_capability=capability
                )

        # ----------------------------------------------------
        # PRIORITY 3: Capability & Native Application Availability
        # ----------------------------------------------------
        laptop_devices = device_registry.get_devices_by_type("WINDOWS_PC", online_only=True)
        phone_devices = device_registry.get_devices_by_type("ANDROID_PHONE", online_only=True) + device_registry.get_devices_by_type("MOBILE", online_only=True)

        laptop_online = len(laptop_devices) > 0
        phone_online = len(phone_devices) > 0

        # If request originates from Windows Desktop app, default to WINDOWS_PC unless user explicitly asks for Phone
        if origin_device in ["WINDOWS_DESKTOP", "WINDOWS_PC", "LAPTOP", "DESKTOP"] and not is_phone_explicit:
            logger.info(f"[ROUTER] Request originates from {origin_device}. Targeting WINDOWS_PC.")
            dev_id = laptop_devices[0].device_id if laptop_devices else "windows_local_host"
            return RouteResult(
                origin_device=origin_device,
                target_device="WINDOWS_PC",
                device_id=dev_id,
                intent=intent,
                app_name=app_name,
                required_capability=capability,
                execution_mode="NATIVE"
            )

        # If app is desktop-only native app like Calculator or Notepad
        if app_name in ["calculator", "calc", "notepad", "cmd", "terminal", "paint", "explorer", "wordpad", "powershell"]:
            dev_id = laptop_devices[0].device_id if laptop_devices else "windows_local_host"
            return RouteResult(
                origin_device=origin_device,
                target_device="WINDOWS_PC",
                device_id=dev_id,
                intent=intent,
                app_name=app_name,
                required_capability=capability,
                execution_mode="NATIVE"
            )

        # ----------------------------------------------------
        # PRIORITY 4: Ask User if ambiguous & multiple devices online
        # ----------------------------------------------------
        if laptop_online and phone_online:
            # Both devices online and command is ambiguous (e.g. "Open camera", "Open WhatsApp", "Open YouTube")
            logger.info(f"[ROUTER] Ambiguous command '{command}' with both Laptop and Phone online. Requesting user selection.")
            prompt_text = f"Which device would you like me to use for '{command}' — your laptop or your phone?"
            return RouteResult(
                origin_device=origin_device,
                target_device="AMBIGUOUS",
                is_ambiguous=True,
                ambiguous_prompt=prompt_text,
                ambiguous_options=["Laptop", "Phone"],
                intent=intent,
                app_name=app_name,
                required_capability=capability
            )

        # Fallback if only 1 device is online
        if laptop_online:
            return RouteResult(
                origin_device=origin_device,
                target_device="WINDOWS_PC",
                device_id=laptop_devices[0].device_id,
                intent=intent,
                app_name=app_name,
                required_capability=capability
            )
        elif phone_online:
            return RouteResult(
                origin_device=origin_device,
                target_device="ANDROID_PHONE",
                device_id=phone_devices[0].device_id,
                intent=intent,
                app_name=app_name,
                required_capability=capability
            )

        # Default fallback
        return RouteResult(
            origin_device=origin_device,
            target_device="WINDOWS_PC",
            intent=intent,
            app_name=app_name,
            required_capability=capability
        )

device_router = DeviceRouter()
