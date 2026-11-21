import abc
import json
import httpx
import logging
from typing import Dict, Any, List, Optional
from app.core.config import settings

logger = logging.getLogger("kiko.ai")

class AIProvider(abc.ABC):
    @abc.abstractmethod
    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None, chat_history: Optional[List[Dict[str, str]]] = None) -> str:
        pass

    @abc.abstractmethod
    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        pass


class OpenAIProvider(AIProvider):
    def __init__(self, api_key: str = None, model: str = None):
        self.api_key = api_key or getattr(settings, "OPENAI_API_KEY", "")
        self.model = model or getattr(settings, "OPENAI_MODEL", "gpt-4o")

    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None, chat_history: Optional[List[Dict[str, str]]] = None) -> str:
        if not self.api_key:
            logger.warning("[LLM] OpenAI API key not configured.")
            return "I'm having trouble connecting to my AI service. OpenAI API key is not configured."
        
        masked_key = self.api_key[:4] + "..." + self.api_key[-4:] if len(self.api_key) > 8 else "***"
        logger.info(f"[LLM] Sending request to OpenAI (Model: {self.model}, Key: {masked_key})...")
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        if chat_history:
            for turn in chat_history[-10:]:
                messages.append({"role": turn.get("role", "user"), "content": turn.get("content", "")})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": self.model,
            "messages": messages,
            "temperature": 0.3
        }
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post("https://api.openai.com/v1/chat/completions", json=payload, headers=headers, timeout=30.0)
                logger.info(f"[LLM RAW RESPONSE RECEIVED] HTTP Status: {resp.status_code}")
                if resp.status_code == 200:
                    data = resp.json()
                    parsed_text = data["choices"][0]["message"]["content"].strip()
                    logger.info(f"[LLM PARSED RESPONSE] {parsed_text}")
                    return parsed_text
                else:
                    logger.error(f"[LLM ERROR] OpenAI HTTP {resp.status_code}: {resp.text}")
                    return "I'm having trouble connecting to my AI service. Please check your OpenAI API key."
        except Exception as e:
            logger.error(f"[LLM CONNECTION ERROR] {e}")
            return "I'm having trouble connecting to my AI service."

    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        sys_msg = (
            "You are the KIKO Task Orchestrator. Convert the user's intent into a JSON array of tool execution steps.\n"
            "Each step must be an object with: 'step_number', 'tool_name', 'parameters' (dict), and 'description'.\n"
            f"Active Context: {json.dumps(active_context or {})}\n"
            f"Available tools: {json.dumps(available_tools)}"
        )
        resp_text = await self.generate_response(user_intent, system_prompt=sys_msg)
        try:
            if "```json" in resp_text:
                resp_text = resp_text.split("```json")[1].split("```")[0].strip()
            elif "```" in resp_text:
                resp_text = resp_text.split("```")[1].split("```")[0].strip()
            return json.loads(resp_text)
        except Exception:
            return RuleFallbackProvider().plan_task_sync(user_intent, active_context=active_context)

class OllamaProvider(AIProvider):
    """Ollama local LLM provider — uses /api/chat endpoint.
    Default model: qwen3:4b (configured via OLLAMA_MODEL env var or LLM settings).
    Automatically strips Qwen3 <think>...</think> reasoning tokens from responses.
    """

    def __init__(self, base_url: str = None, model: str = None):
        self.base_url = (base_url or getattr(settings, "OLLAMA_BASE_URL", "http://localhost:11434")).rstrip("/")
        self.model = model or getattr(settings, "OLLAMA_MODEL", "qwen3:4b")
        self.timeout = float(getattr(settings, "OLLAMA_TIMEOUT", 120.0))

    @staticmethod
    def _strip_think_tokens(text: str) -> str:
        """Remove Qwen3 <think>...</think> reasoning tokens from output."""
        import re
        # Remove think blocks including newlines inside them
        cleaned = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
        return cleaned.strip()

    async def check_health(self) -> Dict[str, Any]:
        """Check if Ollama service is running and the configured model is available."""
        try:
            async with httpx.AsyncClient() as client:
                # Check service
                resp = await client.get(f"{self.base_url}/api/tags", timeout=5.0)
                if resp.status_code != 200:
                    return {"online": False, "model_available": False, "error": f"Ollama HTTP {resp.status_code}"}
                models_data = resp.json().get("models", [])
                available_models = [m.get("name", "") for m in models_data]
                # Check if configured model is in available list (handle tag variations)
                model_available = any(
                    self.model == m or self.model.split(":")[0] == m.split(":")[0]
                    for m in available_models
                )
                return {
                    "online": True,
                    "model_available": model_available,
                    "configured_model": self.model,
                    "available_models": available_models
                }
        except Exception as e:
            return {"online": False, "model_available": False, "error": str(e)}

    async def generate_response(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        chat_history: Optional[List[Dict[str, str]]] = None
    ) -> str:
        logger.info(f"[LLM] Sending request to Ollama (URL: {self.base_url}, Model: {self.model})...")
        url = f"{self.base_url}/api/chat"

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        if chat_history:
            for turn in chat_history[-10:]:
                messages.append({
                    "role": turn.get("role", "user"),
                    "content": turn.get("content", "")
                })
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
            "options": {
                "num_ctx": 2048,
                "temperature": 0.7
            }
        }

        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post(url, json=payload, timeout=min(self.timeout, 12.0))
                logger.info(f"[LLM RAW RESPONSE RECEIVED] HTTP Status: {resp.status_code}")
                if resp.status_code == 200:
                    data = resp.json()
                    msg = data.get("message", {})
                    raw_text = msg.get("content", "").strip()
                    if not raw_text and msg.get("thinking"):
                        raw_text = msg.get("thinking", "").strip()
                    parsed_text = self._strip_think_tokens(raw_text) or raw_text
                    if not parsed_text:
                        return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)
                    logger.info(f"[LLM PARSED RESPONSE] {parsed_text[:200]}..." if len(parsed_text) > 200 else f"[LLM PARSED RESPONSE] {parsed_text}")
                    return parsed_text
                elif resp.status_code == 404:
                    logger.error(f"[LLM ERROR] Ollama model '{self.model}' not found. Run: ollama pull {self.model}")
                    return f"⚠️ Model '{self.model}' is not installed. Please run: ollama pull {self.model}"
                else:
                    logger.error(f"[LLM ERROR] Ollama HTTP {resp.status_code}: {resp.text}")
                    return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)
        except httpx.ConnectError:
            logger.error(f"[LLM CONNECTION ERROR] Ollama is not running at {self.base_url}")
            return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)
        except httpx.TimeoutException:
            logger.warning("[LLM TIMEOUT] Ollama generation took >20s on CPU. Returning responsive fallback.")
            return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)
        except Exception as e:
            logger.error(f"[LLM CONNECTION ERROR] Ollama: {e}")
            return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)

    async def plan_task(
        self,
        user_intent: str,
        available_tools: List[Dict[str, Any]],
        active_context: Optional[Dict[str, Any]] = None
    ) -> List[Dict[str, Any]]:
        """Use Qwen3 to plan a structured tool execution sequence.
        Falls back to RuleFallbackProvider if JSON parsing fails after retries.
        """
        sys_msg = (
            "You are KIKO Task Orchestrator. Convert the user's intent into a JSON array of tool execution steps.\n"
            "RESPOND WITH ONLY THE JSON ARRAY. No explanation, no markdown fences, no extra text.\n"
            "Each step MUST be a JSON object with EXACTLY these keys:\n"
            "  - step_number (integer)\n"
            "  - tool_name (string, one of the available tools)\n"
            "  - parameters (object with tool-specific keys)\n"
            "  - target_device (string: 'laptop' or 'mobile')\n"
            "  - description (string, human-readable)\n"
            f"Active Context: {json.dumps(active_context or {})}\n"
            f"Available tools: {json.dumps([{k: v for k, v in t.items() if k in ['name', 'description', 'parameters']} for t in available_tools[:20]])}"
        )

        for attempt in range(1):
            try:
                resp_text = await self.generate_response(user_intent, system_prompt=sys_msg)
                # Strip any residual markdown fences
                if "```json" in resp_text:
                    resp_text = resp_text.split("```json")[1].split("```")[0].strip()
                elif "```" in resp_text:
                    resp_text = resp_text.split("```")[1].split("```")[0].strip()
                parsed = json.loads(resp_text)
                if isinstance(parsed, list) and len(parsed) > 0:
                    logger.info(f"[LLM] Ollama plan_task succeeded with {len(parsed)} steps")
                    return parsed
            except Exception as e:
                logger.warning(f"[LLM] Ollama plan_task attempt failed: {e}")

        logger.warning("[LLM] Ollama plan_task falling back to RuleFallbackProvider")
        return RuleFallbackProvider().plan_task_sync(user_intent, active_context=active_context)

class LocalLLMProvider(AIProvider):
    def __init__(self, base_url: str = None, model: str = None):
        self.base_url = base_url or getattr(settings, "LOCAL_LLM_URL", "http://localhost:8000/v1")
        self.model = model or getattr(settings, "LOCAL_LLM_MODEL", "local-model")

    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        logger.info(f"[LLM] Sending request to Local LLM (URL: {self.base_url})...")
        headers = {"Content-Type": "application/json"}
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {"model": self.model, "messages": messages}
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post(f"{self.base_url}/chat/completions", json=payload, headers=headers, timeout=30.0)
                logger.info(f"[LLM RAW RESPONSE RECEIVED] HTTP Status: {resp.status_code}")
                if resp.status_code == 200:
                    parsed_text = resp.json()["choices"][0]["message"]["content"].strip()
                    logger.info(f"[LLM PARSED RESPONSE] {parsed_text}")
                    return parsed_text
                return "I'm having trouble connecting to my AI service."
        except Exception as e:
            logger.error(f"[LLM CONNECTION ERROR] Local LLM: {e}")
            return "I'm having trouble connecting to my AI service."

    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        return RuleFallbackProvider().plan_task_sync(user_intent, active_context=active_context)

class RuleFallbackProvider(AIProvider):
    """Deterministically plans tasks for common user commands when offline or in test mode."""
    
    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None, chat_history: Optional[List[Dict[str, str]]] = None) -> str:
        prompt_lower = prompt.lower().strip()
        logger.info(f"[LLM] RuleFallbackProvider processing prompt: '{prompt}'")

        # Context Check from Chat History
        if chat_history and len(chat_history) > 0:
            last_turn = chat_history[-1]
            last_text = last_turn.get("content", "").lower()
            if "which device" in last_text or "laptop or your phone" in last_text:
                if any(w in prompt_lower for w in ["laptop", "pc", "desktop"]):
                    return "Understood! I will use your laptop."
                elif any(w in prompt_lower for w in ["phone", "mobile"]):
                    return "Understood! I will use your phone."
        
        # 1. Wellness Questions
        if any(w in prompt_lower for w in ["how are you", "how r u", "how do you do", "how is it going", "how's it going", "what's up", "whats up"]):
            return "I am doing great, Ayushman! Thanks for asking. How can I assist you today?"
        
        # 2. Greetings
        elif any(g in prompt_lower for g in ["hello", "hi", "hey", "greetings", "good morning", "good evening"]):
            return "Hi Ayushman! How can I assist you today?"
            
        # 3. Identity & Creator Questions
        elif any(i in prompt_lower for i in ["who are you", "what is your name", "who made you", "who created you", "tell me about yourself"]):
            return "I am KIKO, your personal AI assistant created by Ayushman. I can control your laptop, open mobile apps, perform web searches, and execute tasks for you!"
            
        # 4. Capability Questions
        elif any(c in prompt_lower for c in ["what can you do", "help me", "your capabilities", "what features"]):
            return "I can open apps like YouTube, Instagram, or Notepad, take screenshots, create folders, search files, play music, and answer your questions!"
            
        # 5. Trivia / Math / Jokes
        elif "2 + 2" in prompt_lower or "2+2" in prompt_lower:
            return "2 + 2 is equal to 4."
        elif "joke" in prompt_lower:
            return "Why don't scientists trust atoms? Because they make up everything!"

        # 6. Gratitude & Farewells
        elif any(t in prompt_lower for t in ["thank you", "thanks", "bye", "goodbye", "see you"]):
            return "You're very welcome, Ayushman! Let me know if you need anything else."
            
        # Default Conversational Response
        return f"I'm right here to assist you, Ayushman! How can I help you with '{prompt}'?"

    def plan_task_sync(self, user_intent: str, active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        import re
        text_lower = user_intent.lower().strip()
        active_app = active_context.get("active_application") if (active_context and isinstance(active_context, dict)) else None
        
        clean_text_for_mobile = re.sub(r'\b(iphone|microphone|headphone|earphone|cellphone|telephone|gramophone)\b', '', text_lower, flags=re.IGNORECASE)
        is_laptop_explicit = any(k in text_lower for k in ["on laptop", "in laptop", "on pc", "on desktop", "windows pc", "my laptop", "my pc"])
        is_mobile_explicit = any(k in clean_text_for_mobile for k in ["in mobile", "on mobile", "on phone", "in phone", "mobile phone", "my mobile", "my phone", "in my phone"])

        # 0. Save Document Rule ("save it as myname.txt" or "save myname.txt")
        if "save" in text_lower:
            fn_match = re.search(r'(?:as|name|to|file)\s+[\'"]?([a-zA-Z0-9_\-\.]+\.[a-zA-Z0-9]+|[\w\-]+)', user_intent, re.IGNORECASE)
            file_name = fn_match.group(1).strip() if fn_match else "document.txt"
            if not file_name.endswith((".txt", ".doc", ".docx", ".pdf", ".png")):
                file_name += ".txt"
            return [
                {
                    "step_number": 1,
                    "tool_name": "save_document",
                    "target_device": "laptop",
                    "parameters": {"file_name": file_name},
                    "description": f"Save active document as '{file_name}'"
                }
            ]

        # 1. YouTube commands
        if "youtube" in text_lower:
            # Clean query: handles "search scout op in youtube", "for scout Op in YouTube", "scout op on youtube"
            yt_clean = re.sub(r'^(search|play|open|find|look\s+for|for)\s+', '', user_intent, flags=re.IGNORECASE).strip()
            yt_clean = re.sub(r'\s+(?:in|on|at|from)\s+youtube.*$', '', yt_clean, flags=re.IGNORECASE).strip()
            yt_clean = re.sub(r'\s+youtube.*$', '', yt_clean, flags=re.IGNORECASE).strip()
            yt_clean = re.sub(r'^(youtube)\s+', '', yt_clean, flags=re.IGNORECASE).strip()
            clean_query = re.sub(r'\b(app|video|videos|song|songs|channel|in|on|at|browser|my|the)\b', '', yt_clean, flags=re.IGNORECASE).strip()
            
            if is_mobile_explicit:
                return [
                    {
                        "step_number": 1,
                        "tool_name": "search_youtube_mobile",
                        "target_device": "mobile",
                        "parameters": {"query": clean_query},
                        "description": f"Open YouTube and search '{clean_query}' on mobile phone" if clean_query else "Open YouTube app on mobile phone"
                    }
                ]
            else:
                return [
                    {
                        "step_number": 1,
                        "tool_name": "search_youtube",
                        "target_device": "laptop",
                        "parameters": {"query": clean_query or ""},
                        "description": f"Search YouTube for '{clean_query}' on laptop" if clean_query else "Open YouTube in browser on laptop"
                    }
                ]

        # 2. Dynamic Create Folder (Laptop)
        if any(k in text_lower for k in ["folder", "directory"]) and any(k in text_lower for k in ["create", "make", "new", "add"]):
            folder_name = ""
            target_location = ""
            
            named_match = re.search(r'(?:named|called)\s+[\'"]?([^\'"]+?)[\'"]?\s+(?:inside|in|on|at|under)\s+(.+)', user_intent, re.IGNORECASE)
            if named_match:
                folder_name = named_match.group(1).strip()
                target_location = named_match.group(2).strip(" '.")
            else:
                in_match = re.search(r'(?:folder|directory)\s+[\'"]?([^\'"]+?)[\'"]?\s+(?:inside|in|on|at|under)\s+(.+)', user_intent, re.IGNORECASE)
                if in_match:
                    folder_name = in_match.group(1).strip()
                    target_location = in_match.group(2).strip(" '.")
                else:
                    raw = re.sub(r'^(create|make)\s+(a\s+)?(folder|directory)\s*', '', user_intent, flags=re.IGNORECASE).strip()
                    folder_name = raw.strip(" '.")
            
            path = f"{target_location}/{folder_name}" if (target_location and folder_name) else (folder_name or "New Folder")

            return [
                {
                    "step_number": 1,
                    "tool_name": "create_folder",
                    "target_device": "laptop",
                    "parameters": {"path": path},
                    "description": f"Create folder '{folder_name}' at path '{path}'"
                }
            ]

        # 2.4 Multi-Step Autonomous Browser Research & Navigation
        # Handles tasks like "Open Google, search for LangGraph, open official docs, read persistence and explain it"
        is_autonomous_browser = (
            any(k in text_lower for k in ["explain", "summarize", "analyze", "research", "compare", "report", "read the"]) and
            any(b in text_lower for b in ["browser", "google", "documentation", "docs", "website", "web", "online", "github", "langgraph", "fastapi"])
        ) or (
            "open" in text_lower and any(s in text_lower for s in ["search", "find"]) and any(e in text_lower for e in ["explain", "read", "summarize"])
        ) or ("autonomous" in text_lower and "browser" in text_lower)

        if is_autonomous_browser:
            return [
                {
                    "step_number": 1,
                    "tool_name": "autonomous_browser_task",
                    "target_device": "laptop",
                    "parameters": {"instruction": user_intent},
                    "description": f"Autonomous browser research & navigation: '{user_intent}'"
                }
            ]

        # 2.5 Browser & Web Service Requests
        # Handles "open Netflix in my browser", "open something in browser", "open chatgpt in browser", "open netflix", etc.
        web_service_map = {
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
            "openai": "https://chatgpt.com",
            "hotstar": "https://www.hotstar.com",
            "disney": "https://www.hotstar.com",
            "prime video": "https://www.primevideo.com",
            "primevideo": "https://www.primevideo.com",
            "wikipedia": "https://www.wikipedia.org",
            "facebook": "https://www.facebook.com",
            "instagram": "https://www.instagram.com",
            "linkedin": "https://www.linkedin.com",
            "gmail": "https://mail.google.com",
            "twitch": "https://www.twitch.tv",
            "spotify": "https://open.spotify.com",
            "whatsapp": "https://web.whatsapp.com",
            "pinterest": "https://www.pinterest.com",
            "imdb": "https://www.imdb.com",
            "quora": "https://www.quora.com",
            "medium": "https://medium.com",
            "stackoverflow": "https://stackoverflow.com",
            "stack overflow": "https://stackoverflow.com",
        }

        is_browser_explicit = any(k in text_lower for k in [
            "in my browser", "in the browser", "in browser", "on browser", "on my browser",
            "in chrome", "in edge", "in firefox", "using browser", "web browser", "open browser", "launch browser"
        ])
        has_domain = bool(re.search(r'\b[a-zA-Z0-9_\-]+\.(?:com|org|net|in|io|co|ai|tv|gov|edu)\b', text_lower))
        has_web_service = any(re.search(r'\b' + re.escape(ws) + r'\b', text_lower) for ws in web_service_map)

        if is_browser_explicit or has_domain or (has_web_service and not any(d in text_lower for d in ["notepad", "calc", "calculator", "paint", "explorer", "camera", "cmd", "terminal"])):
            target_url = ""
            display_name = ""

            domain_match = re.search(r'([a-zA-Z0-9_\-]+\.(?:com|org|net|in|io|co|ai|tv|gov|edu)[^\s]*)', text_lower)
            if domain_match:
                d = domain_match.group(1).strip()
                target_url = d if d.startswith("http") else f"https://{d}"
                display_name = d
            else:
                for ws, url in web_service_map.items():
                    if re.search(r'\b' + re.escape(ws) + r'\b', text_lower):
                        target_url = url
                        display_name = ws.title()
                        break

            if not target_url:
                query = re.sub(r'^(open|launch|browse|search|find|look\s+for|go\s+to)\s+', '', text_lower, flags=re.IGNORECASE).strip()
                query = re.sub(r'\s+(?:in|on|using|through)\s+(?:my\s+|the\s+)?(?:web\s+)?(?:browser|chrome|edge|firefox).*$', '', query, flags=re.IGNORECASE).strip()
                query = re.sub(r'\s+in\s+my\s+browser.*$', '', query, flags=re.IGNORECASE).strip()
                query = query.strip(" '\"")
                if not query or query in ["browser", "web browser", "my browser", "chrome", "edge"]:
                    target_url = "https://www.google.com"
                    display_name = "Browser"
                else:
                    target_url = f"https://www.google.com/search?q={query.replace(' ', '+')}"
                    display_name = query

            target_device = "mobile" if is_mobile_explicit else "laptop"
            tool_name = "open_url_mobile" if target_device == "mobile" else "open_browser"
            return [
                {
                    "step_number": 1,
                    "tool_name": tool_name,
                    "target_device": target_device,
                    "parameters": {"url": target_url, "query": display_name},
                    "description": f"Open {display_name} in browser on {target_device}"
                }
            ]

        # 3. Dynamic Open Application / Typing (Desktop vs Mobile)
        elif ("open" in text_lower or "launch" in text_lower or "write" in text_lower or "type" in text_lower or "add" in text_lower or "notepad" in text_lower or active_app) and not "url" in text_lower:
            clean_intent = re.sub(r'^(can you|please|kindly)\s+', '', user_intent, flags=re.IGNORECASE).strip()
            
            # Detect app name accurately
            desktop_apps = [
                "notepad", "calculator", "calc", "cmd", "terminal", "explorer", "paint", "wordpad",
                "camera", "cam", "chrome", "whatsapp", "spotify", "telegram", "discord", "slack",
                "zoom", "settings", "photos", "gallery", "vscode", "code"
            ]

            app_name = ""

            # Step A: Check if explicit "open/launch <app>" is in user_intent
            open_match = re.search(r'(?:open|launch)\s+(?:the\s+|my\s+|a\s+|an\s+)?([a-zA-Z0-9_\-\.]+)', clean_intent, re.IGNORECASE)
            if open_match:
                candidate = open_match.group(1).strip().lower()
                if candidate not in ["in", "on", "my", "the", "a", "an", "laptop", "pc", "phone", "mobile", "desktop"]:
                    app_name = candidate

            # Step B: Scan clean_intent for known desktop/mobile apps
            if not app_name:
                for d in desktop_apps:
                    if d in clean_intent.lower():
                        app_name = d
                        break

            # Step C: Only fall back to active_app if this is NOT an explicit "open/launch" command
            is_open_cmd = any(k in text_lower for k in ["open", "launch"])
            if not app_name and active_app and not is_open_cmd:
                app_name = active_app.lower()

            # Step D: Final fallback regex or default
            if not app_name:
                app_match = re.search(r'(?:write|type|in|into)\s+(?:the\s+|my\s+|a\s+|an\s+|that\s+)?([a-zA-Z0-9_\-\.]+)', clean_intent, re.IGNORECASE)
                if app_match:
                    cand = app_match.group(1).strip().lower()
                    if cand not in ["in", "on", "my", "the", "a", "an", "laptop", "pc", "phone", "mobile"]:
                        app_name = cand
            
            if not app_name:
                app_name = "notepad"

            is_desktop_app = any(d in app_name.lower() for d in desktop_apps) or app_name in ["whatsapp", "spotify", "telegram", "discord", "slack", "zoom", "chrome", "notepad", "calc", "calculator", "explorer", "paint", "camera"]

            if is_laptop_explicit or (is_desktop_app and not is_mobile_explicit):
                steps = [
                    {
                        "step_number": 1,
                        "tool_name": "open_application",
                        "target_device": "laptop",
                        "parameters": {"app_name": app_name},
                        "description": f"Open application '{app_name}' on laptop"
                    }
                ]

                if any(k in text_lower for k in ["type", "write", "add", "append", "note", "joke", "poem", "below"]):
                    text_to_type = ""
                    quoted = re.search(r'[\'"]([^\'"]+)[\'"]', clean_intent)
                    if quoted:
                        text_to_type = quoted.group(1).strip()
                    elif "joke" in text_lower:
                        text_to_type = "Why do programmers prefer dark mode?\nBecause light attracts bugs! 🐛\n\n— KIKO AI"
                    elif "poem" in text_lower:
                        text_to_type = "Roses are red, violets are blue,\nKIKO is here, to assist you! ✨\n\n— KIKO AI"
                    else:
                        extracted_match = re.search(r'(?:type|write|add|append)\s+[\'"]?(.+?)[\'"]?(?:\s+(?:below|above|in|into|same|notepad|it).*)?$', clean_intent, re.IGNORECASE)
                        if extracted_match:
                            raw_ext = extracted_match.group(1).strip()
                            clean_ext = re.sub(r'\b(below|it|in|that|same|notepad|document|on|laptop)\b', '', raw_ext, flags=re.IGNORECASE).strip()
                            text_to_type = clean_ext if clean_ext else raw_ext
                        else:
                            text_to_type = clean_intent

                    is_below = any(k in text_lower for k in ["below", "next line", "under"])
                    if is_below and not text_to_type.startswith("\n"):
                        text_to_type = f"\n{text_to_type}"

                    steps.append({
                        "step_number": 2,
                        "tool_name": "keyboard_type",
                        "target_device": "laptop",
                        "parameters": {"text": text_to_type, "append_line": is_below, "app_name": app_name},
                        "description": f"Type generated text into {app_name}"
                    })

                return steps
            else:
                # Dynamically target mobile phone for ANY app request!
                return [
                    {
                        "step_number": 1,
                        "tool_name": "open_mobile_app",
                        "target_device": "mobile",
                        "parameters": {"app_name": app_name},
                        "description": f"Open application '{app_name}' on mobile phone"
                    }
                ]

        # 4. Dynamic File Search (Laptop)
        elif any(k in text_lower for k in ["find", "search file", "search for"]):
            search_match = re.search(r'(?:find|search\s+for)\s+[\'"]?([^\'"]+?)[\'"]?\s+(?:in|inside|under)\s+(.+)', user_intent, re.IGNORECASE)
            if search_match:
                query = search_match.group(1).strip()
                directory = search_match.group(2).strip(" '.")
            else:
                raw_q = re.sub(r'^(find|search\s+for|search)\s*', '', user_intent, flags=re.IGNORECASE).strip()
                query = raw_q if raw_q else "document"
                directory = "Documents"

            return [
                {
                    "step_number": 1,
                    "tool_name": "search_files",
                    "target_device": "laptop",
                    "parameters": {"query": query, "directory": directory},
                    "description": f"Search files for '{query}' in '{directory}'"
                }
            ]

        # 5. Screenshot (Laptop)
        elif "screenshot" in text_lower:
            return [
                {
                    "step_number": 1,
                    "tool_name": "take_screenshot",
                    "target_device": "laptop",
                    "parameters": {},
                    "description": "Capture desktop screenshot"
                }
            ]

        # Default Mobile / Web Search
        target_dev = "laptop" if is_laptop_explicit else "mobile"
        tool_n = "search_web" if target_dev == "laptop" else "open_url_mobile"
        return [
            {
                "step_number": 1,
                "tool_name": tool_n,
                "target_device": target_dev,
                "parameters": {"query": user_intent, "url": f"https://www.google.com/search?q={user_intent}"},
                "description": f"Perform search for '{user_intent}'"
            }
        ]

    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        return self.plan_task_sync(user_intent, active_context=active_context)

class AnthropicProvider(AIProvider):
    def __init__(self, api_key: str = None, model: str = None):
        self.api_key = api_key or getattr(settings, "ANTHROPIC_API_KEY", "")
        self.model = model or "claude-3-5-sonnet-20240620"

    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None, chat_history: Optional[List[Dict[str, str]]] = None) -> str:
        if not self.api_key:
            logger.warning("[LLM] Anthropic API key not configured.")
            return "I'm having trouble connecting to my AI service. Anthropic API key is not configured."

        masked_key = self.api_key[:4] + "..." + self.api_key[-4:] if len(self.api_key) > 8 else "***"
        logger.info(f"[LLM] Sending request to Anthropic Claude (Model: {self.model}, Key: {masked_key})...")

        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
        messages = []
        if chat_history:
            for turn in chat_history[-10:]:
                messages.append({"role": turn.get("role", "user"), "content": turn.get("content", "")})
        messages.append({"role": "user", "content": prompt})

        payload = {
            "model": self.model,
            "max_tokens": 1024,
            "system": system_prompt or "",
            "messages": messages
        }
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post("https://api.anthropic.com/v1/messages", json=payload, headers=headers, timeout=30.0)
                logger.info(f"[LLM RAW RESPONSE RECEIVED] HTTP Status: {resp.status_code}")
                if resp.status_code == 200:
                    data = resp.json()
                    parsed_text = data["content"][0]["text"].strip()
                    logger.info(f"[LLM PARSED RESPONSE] {parsed_text}")
                    return parsed_text
                else:
                    logger.error(f"[LLM ERROR] Anthropic HTTP {resp.status_code}: {resp.text}")
                    return "I'm having trouble connecting to my AI service. Please check your Anthropic API key."
        except Exception as e:
            logger.error(f"[LLM CONNECTION ERROR] Anthropic: {e}")
            return "I'm having trouble connecting to my AI service."

    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        return RuleFallbackProvider().plan_task_sync(user_intent, active_context=active_context)

class GeminiProvider(AIProvider):
    def __init__(self, api_key: str = None, model: str = None):
        self.api_key = api_key or getattr(settings, "GEMINI_API_KEY", "")
        self.model = model or "gemini-3.5-flash-lite"

    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None, chat_history: Optional[List[Dict[str, str]]] = None) -> str:
        if not self.api_key:
            logger.warning("[LLM] Gemini API key not configured.")
            return "I'm having trouble connecting to my AI service. Gemini API key is not configured."

        masked_key = self.api_key[:4] + "..." + self.api_key[-4:] if len(self.api_key) > 8 else "***"
        
        candidate_models = [
            self.model or "gemini-3.5-flash-lite",
            "gemini-3.5-flash-lite",
            "gemini-3.5-flash",
            "gemini-3.8-flash",
            "gemini-flash-latest",
        ]
        # Remove duplicates while maintaining order
        seen = set()
        models_to_try = [m for m in candidate_models if not (m in seen or seen.add(m))]

        contents = []
        if system_prompt:
            contents.append({"role": "user", "parts": [{"text": f"System Instructions: {system_prompt}"}]})
            contents.append({"role": "model", "parts": [{"text": "Understood."}]})
        
        if chat_history:
            for turn in chat_history[-10:]:
                role = "user" if turn.get("role") == "user" else "model"
                contents.append({"role": role, "parts": [{"text": turn.get("content", "")}]})

        contents.append({"role": "user", "parts": [{"text": prompt}]})

        payload = {"contents": contents}

        async with httpx.AsyncClient() as client:
            for mod in models_to_try:
                model_path = mod if mod.startswith("models/") else f"models/{mod}"
                url = f"https://generativelanguage.googleapis.com/v1beta/{model_path}:generateContent?key={self.api_key}"
                logger.info(f"[LLM] Sending request to Gemini (Model: {model_path}, Key: {masked_key})...")
                
                try:
                    resp = await client.post(url, json=payload, timeout=30.0)
                    logger.info(f"[LLM RAW RESPONSE RECEIVED] HTTP Status: {resp.status_code}")
                    if resp.status_code == 200:
                        data = resp.json()
                        parsed_text = data["candidates"][0]["content"]["parts"][0]["text"].strip()
                        logger.info(f"[LLM PARSED RESPONSE] {parsed_text}")
                        return parsed_text
                    elif resp.status_code == 429:
                        logger.warning(f"[LLM WARNING] Gemini API Rate Limit reached (HTTP 429). Falling back to RuleFallbackProvider.")
                        return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)
                    elif resp.status_code in [404, 500, 502, 503, 504]:
                        logger.warning(f"[LLM] Model '{model_path}' returned HTTP {resp.status_code}. Trying next candidate model...")
                        continue
                    else:
                        logger.error(f"[LLM ERROR] Gemini HTTP {resp.status_code}: {resp.text}")
                        return "I'm having trouble connecting to my AI service. Please check your Gemini API key."
                except Exception as e:
                    logger.error(f"[LLM CONNECTION ERROR] Gemini model {model_path}: {e}")
                    continue

        return await RuleFallbackProvider().generate_response(prompt, system_prompt, chat_history)

    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        sys_msg = (
            "You are KIKO Task Orchestrator. Convert user intent into a JSON array of tool execution steps.\n"
            "Each step must be an object with: 'step_number', 'tool_name', 'parameters' (dict), 'target_device' ('laptop' or 'mobile'), and 'description'.\n"
            f"Active Context: {json.dumps(active_context or {})}\n"
            "If the user asks to open an app like Notepad and write/type a message, joke, note, poem, or text:\n"
            "  Step 1: tool_name: 'open_application', parameters: {'app_name': 'notepad'}, target_device: 'laptop'\n"
            "  Step 2: tool_name: 'keyboard_type', parameters: {'text': '<GENERATE COMPLETE DETAILED TEXT/JOKE/MESSAGE HERE>'}, target_device: 'laptop'\n"
            "If the user asks to open something in a browser, browse a website, or search the web (e.g. 'open Netflix in my browser', 'open youtube in browser', 'search X in browser'):\n"
            "  Step 1: tool_name: 'open_browser', parameters: {'url': '<FULL_HTTPS_URL_OR_SEARCH_URL>', 'query': '<QUERY_OR_NAME>'}, target_device: 'laptop'\n"
            "If the user asks a multi-step browser navigation, research, reading, or explanation task (e.g. 'Open Google, search for LangGraph, open official docs, read persistence section and explain it' or 'research X online and summarize'):\n"
            "  Step 1: tool_name: 'autonomous_browser_task', parameters: {'instruction': '<USER_INSTRUCTION>'}, target_device: 'laptop'\n"
            f"Available tools: {json.dumps(available_tools)}"
        )
        try:
            resp_text = await self.generate_response(user_intent, system_prompt=sys_msg)
            if "```json" in resp_text:
                resp_text = resp_text.split("```json")[1].split("```")[0].strip()
            elif "```" in resp_text:
                resp_text = resp_text.split("```")[1].split("```")[0].strip()
            parsed = json.loads(resp_text)
            if isinstance(parsed, list) and len(parsed) > 0:
                return parsed
        except Exception as e:
            logger.warning(f"[LLM] Gemini plan_task fallback: {e}")
        return RuleFallbackProvider().plan_task_sync(user_intent, active_context=active_context)

class GroqProvider(AIProvider):
    def __init__(self, api_key: str = None, model: str = None):
        self.api_key = api_key or getattr(settings, "GROQ_API_KEY", "")
        self.model = model or "llama-3.1-70b-versatile"

    async def generate_response(self, prompt: str, system_prompt: Optional[str] = None) -> str:
        if not self.api_key:
            logger.warning("[LLM] Groq API key not configured.")
            return "I'm having trouble connecting to my AI service. Groq API key is not configured."

        masked_key = self.api_key[:4] + "..." + self.api_key[-4:] if len(self.api_key) > 8 else "***"
        logger.info(f"[LLM] Sending request to Groq (Model: {self.model}, Key: {masked_key})...")

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        payload = {"model": self.model, "messages": messages}
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.post("https://api.groq.com/openai/v1/chat/completions", json=payload, headers=headers, timeout=30.0)
                logger.info(f"[LLM RAW RESPONSE RECEIVED] HTTP Status: {resp.status_code}")
                if resp.status_code == 200:
                    parsed_text = resp.json()["choices"][0]["message"]["content"].strip()
                    logger.info(f"[LLM PARSED RESPONSE] {parsed_text}")
                    return parsed_text
                else:
                    logger.error(f"[LLM ERROR] Groq HTTP {resp.status_code}: {resp.text}")
                    return "I'm having trouble connecting to my AI service. Please check your Groq API key."
        except Exception as e:
            logger.error(f"[LLM CONNECTION ERROR] Groq: {e}")
            return "I'm having trouble connecting to my AI service."

    async def plan_task(self, user_intent: str, available_tools: List[Dict[str, Any]], active_context: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        return RuleFallbackProvider().plan_task_sync(user_intent, active_context=active_context)

def get_ai_provider(provider_type: Optional[str] = None) -> AIProvider:
    import logging
    logger = logging.getLogger("kiko.ai")
    try:
        from app.api.settings import load_llm_config
        cfg = load_llm_config()
    except Exception:
        cfg = {}
        
    p_type = (provider_type or cfg.get("selected_provider") or getattr(settings, "DEFAULT_LLM_PROVIDER", "rule")).lower()
    
    gemini_key = cfg.get("gemini_api_key") or getattr(settings, "GEMINI_API_KEY", "") or ""
    openai_key = cfg.get("openai_api_key") or getattr(settings, "OPENAI_API_KEY", "") or ""
    anthropic_key = cfg.get("anthropic_api_key") or getattr(settings, "ANTHROPIC_API_KEY", "") or ""
    groq_key = cfg.get("groq_api_key") or getattr(settings, "GROQ_API_KEY", "") or ""
    
    if p_type == "openai" and openai_key:
        logger.info("[LLM] Selected OpenAIProvider from settings.")
        return OpenAIProvider(api_key=openai_key, model=cfg.get("openai_model"))
    elif p_type == "anthropic" and anthropic_key:
        logger.info("[LLM] Selected AnthropicProvider from settings.")
        return AnthropicProvider(api_key=anthropic_key, model=cfg.get("anthropic_model"))
    elif p_type == "gemini" and gemini_key:
        logger.info("[LLM] Selected GeminiProvider from settings.")
        return GeminiProvider(api_key=gemini_key, model=cfg.get("gemini_model"))
    elif p_type == "groq" and groq_key:
        logger.info("[LLM] Selected GroqProvider from settings.")
        return GroqProvider(api_key=groq_key, model=cfg.get("groq_model"))
    elif p_type == "ollama":
        logger.info("[LLM] Selected OllamaProvider.")
        return OllamaProvider(base_url=cfg.get("ollama_base_url"), model=cfg.get("ollama_model"))
    elif p_type == "local":
        logger.info("[LLM] Selected LocalLLMProvider.")
        return LocalLLMProvider()

    # AUTO-FALLBACK: If selected_provider key was omitted or default was 'rule', check if ANY API key exists!
    if gemini_key:
        logger.info("[LLM] Auto-selected GeminiProvider from active API key.")
        return GeminiProvider(api_key=gemini_key, model=cfg.get("gemini_model") or "gemini-3.5-flash-lite")
    if openai_key:
        logger.info("[LLM] Auto-selected OpenAIProvider from active API key.")
        return OpenAIProvider(api_key=openai_key, model=cfg.get("openai_model") or "gpt-4o")
    if anthropic_key:
        logger.info("[LLM] Auto-selected AnthropicProvider from active API key.")
        return AnthropicProvider(api_key=anthropic_key, model=cfg.get("anthropic_model") or "claude-3-5-sonnet-20240620")
    if groq_key:
        logger.info("[LLM] Auto-selected GroqProvider from active API key.")
        return GroqProvider(api_key=groq_key, model=cfg.get("groq_model") or "llama-3.1-70b-versatile")

    # No cloud key configured — prefer local Ollama (qwen3:4b) over offline rule fallback
    logger.info("[LLM] No external API key found. Defaulting to OllamaProvider (qwen3:4b).")
    return OllamaProvider(
        base_url=cfg.get("ollama_base_url") or getattr(settings, "OLLAMA_BASE_URL", "http://localhost:11434"),
        model=cfg.get("ollama_model") or getattr(settings, "OLLAMA_MODEL", "qwen3:4b")
    )
