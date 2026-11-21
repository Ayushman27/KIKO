import json
import logging
import asyncio
from typing import Dict, Any, List, Optional
import httpx
from datetime import datetime

from app.core.config import settings
from app.websocket.manager import manager as ws_manager
from app.agents.browser_session import browser_session_manager, BrowserSession
from app.agents.browser_tools import browser_tools
from app.agents.browser_reader import browser_reader
from app.agents.browser_vision import browser_vision
from app.agents.browser_research import research_memory

logger = logging.getLogger("kiko.browser.agent")

BROWSER_TOOL_DECLARATIONS = [
    {
        "name": "navigate_to_url",
        "description": "Navigate the browser to a specific URL (e.g. https://www.google.com or documentation link).",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "url": {"type": "STRING", "description": "The destination HTTP/HTTPS URL"}
            },
            "required": ["url"]
        }
    },
    {
        "name": "read_page",
        "description": "Extract structured visible text, headings, paragraphs, and links from the current webpage.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "mode": {"type": "STRING", "description": "Mode: 'all', 'text', or 'article'", "enum": ["all", "text", "article"]}
            }
        }
    },
    {
        "name": "click_element",
        "description": "Click an interactive element using its numbered reference [1], [2], or descriptive text/selector.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "element_ref": {"type": "STRING", "description": "Numbered reference like '[1]' or selector from get_interactive_elements"}
            },
            "required": ["element_ref"]
        }
    },
    {
        "name": "type_text",
        "description": "Fill text into an input field or search box using its reference [1], [2], etc.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "element_ref": {"type": "STRING", "description": "Numbered reference like '[1]' for the input box"},
                "text": {"type": "STRING", "description": "Text to enter into the field"},
                "press_enter": {"type": "BOOLEAN", "description": "Whether to hit Enter after typing (useful for search bars)"}
            },
            "required": ["element_ref", "text"]
        }
    },
    {
        "name": "scroll_page",
        "description": "Scroll the webpage to view more content.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "direction": {"type": "STRING", "description": "'down' or 'up'", "enum": ["down", "up"]},
                "amount": {"type": "INTEGER", "description": "Scroll distance in pixels (default 600)"}
            }
        }
    },
    {
        "name": "press_key",
        "description": "Press a keyboard key (e.g. 'Enter', 'Tab', 'Escape', 'ArrowDown').",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "key": {"type": "STRING", "description": "Name of the key"}
            },
            "required": ["key"]
        }
    },
    {
        "name": "take_screenshot",
        "description": "Capture a screenshot of the current webpage for visual inspection.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "full_page": {"type": "BOOLEAN", "description": "Whether to capture full scrollable page"}
            }
        }
    },
    {
        "name": "finish_task",
        "description": "Call this when you have successfully collected the information or completed the user's objective.",
        "parameters": {
            "type": "OBJECT",
            "properties": {
                "answer": {"type": "STRING", "description": "Complete, comprehensive, grounded answer to the user's request based on actual visited pages."},
                "sources": {"type": "ARRAY", "items": {"type": "STRING"}, "description": "List of actual URLs visited and read to answer the question."}
            },
            "required": ["answer"]
        }
    }
]

class BrowserAgent:
    """
    Autonomous Browser Agent powered by Google Gemini and Playwright.
    Executes the OBSERVE -> REASON -> ACT -> VERIFY -> REPEAT loop.
    """

    def __init__(self):
        self._cancelled_tasks: set = set()

    def cancel_task(self, task_id: str):
        """Signals cancellation to an active browser task."""
        self._cancelled_tasks.add(task_id)
        logger.info(f"[BROWSER AGENT] Task '{task_id}' marked for cancellation.")

    async def open_url(self, url: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        """Direct URL navigation with persistent session."""
        return await browser_tools.navigate_to_url(url, session_id=session_id)

    async def search_web(self, query: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        """Direct web search with persistent session."""
        search_url = f"https://www.google.com/search?q={query.replace(' ', '+')}"
        return await browser_tools.navigate_to_url(search_url, session_id=session_id)

    async def execute_autonomous_task(
        self,
        task_id: str,
        user_intent: str,
        session_id: Optional[str] = None,
        max_turns: int = 12
    ) -> Dict[str, Any]:
        """
        Executes an autonomous multi-step browser workflow:
        OBSERVE -> REASON -> ACT -> VERIFY -> REPEAT
        """
        sid = session_id or f"task_session_{task_id}"
        self._cancelled_tasks.discard(task_id)

        api_key = getattr(settings, "GEMINI_API_KEY", "")
        if not api_key:
            return {
                "success": False,
                "status": "FAILED",
                "error": "Gemini API key is not configured. Cannot perform autonomous browser navigation."
            }

        logger.info(f"[BROWSER AGENT] Starting autonomous browser task {task_id}: '{user_intent}'")
        
        # 1. Initialize Browser Session
        await ws_manager.broadcast({
            "event": "TASK_PROGRESS",
            "task_id": task_id,
            "browser_event": "BROWSER_LAUNCHED",
            "message": f"🌐 Launching persistent Chromium browser session for: '{user_intent}'",
            "timestamp": datetime.utcnow().isoformat()
        })

        try:
            session = await browser_tools.get_or_create_session(session_id=sid)
        except Exception as e:
            return {
                "success": False,
                "status": "FAILED",
                "error": f"Failed to launch browser: {str(e)}"
            }

        # Initial Navigation if not on a page
        page = await session.ensure_active_page()
        if not page.url or page.url == "about:blank":
            await ws_manager.broadcast({
                "event": "TASK_PROGRESS",
                "task_id": task_id,
                "browser_event": "BROWSER_NAVIGATING",
                "message": "🌐 Opening Google Search...",
                "timestamp": datetime.utcnow().isoformat()
            })
            await session.navigate("https://www.google.com")

        history: List[Dict[str, Any]] = []
        action_log: List[Dict[str, Any]] = []
        final_answer = ""
        visited_urls: List[str] = []

        system_instruction = (
            "You are KIKO Autonomous Browser Agent. You can inspect webpages, click buttons and links, "
            "fill search boxes, scroll, and read webpage contents to complete the user's objective.\n\n"
            "CRITICAL RULES:\n"
            "1. Grounding: Rely strictly on real content read from the browser. Never fabricate answers or URLs.\n"
            "2. Interactive Elements: When clicking or typing, pass the numbered element reference like '[1]' or '[2]'.\n"
            "3. Multi-Step Execution: If searching Google, first type the query and submit, then inspect search results, "
            "then click the official documentation or best matching link, then read its content.\n"
            "4. Completion: When you have sufficient evidence to answer the user's question, call 'finish_task' with "
            "your detailed answer and the list of actual source URLs visited."
        )

        # ── OBSERVE -> REASON -> ACT -> VERIFY -> REPEAT LOOP ─────────────────
        for turn in range(1, max_turns + 1):
            if task_id in self._cancelled_tasks:
                logger.info(f"[BROWSER AGENT] Task {task_id} cancelled by user.")
                await ws_manager.broadcast({
                    "event": "TASK_FAILED",
                    "task_id": task_id,
                    "message": "Task cancelled by user.",
                    "timestamp": datetime.utcnow().isoformat()
                })
                return {"success": False, "status": "CANCELLED", "message": "Task cancelled by user."}

            # ── 1. OBSERVE ───────────────────────────────────────────────────
            page = await session.ensure_active_page()
            curr_url = page.url
            curr_title = await page.title()
            if curr_url and curr_url not in visited_urls and not curr_url.startswith("about:"):
                visited_urls.append(curr_url)

            # Discover real interactive elements
            elements_data = await browser_tools.get_interactive_elements(session_id=sid)
            elements_list = elements_data.get("formatted", [])[:35] # Top 35 visible interactive items

            # Extract visible content
            reader_data = await browser_reader.read_page(page, mode="all")
            content_snippet = reader_data.get("main_content", "")[:3500]

            # Save to research memory if on a content-rich page
            if len(content_snippet) > 150 and curr_url != "https://www.google.com/":
                research_memory.add_source(task_id, curr_title, curr_url, content_snippet, step=turn)

            # Broadcast live state to Flutter UI
            await ws_manager.broadcast({
                "event": "TASK_PROGRESS",
                "task_id": task_id,
                "browser_event": "BROWSER_PAGE_LOADED",
                "current_url": curr_url,
                "page_title": curr_title,
                "step": turn,
                "message": f"🌐 [{turn}/{max_turns}] Browser at: {curr_title} ({curr_url})",
                "timestamp": datetime.utcnow().isoformat()
            })

            # ── 2. REASON (Gemini) ───────────────────────────────────────────
            observation_text = (
                f"--- TURN {turn}/{max_turns} ---\n"
                f"User Goal: {user_intent}\n"
                f"Current Page Title: {curr_title}\n"
                f"Current Page URL: {curr_url}\n"
                f"Recent Actions Executed: {json.dumps(action_log[-3:])}\n\n"
                f"Webpage Content Excerpt:\n{content_snippet}\n\n"
                f"Interactive Elements on Page:\n" + "\n".join(elements_list[:30]) + "\n\n"
                "Select the next browser action to perform towards completing the user goal. "
                "If you have gathered enough information to fully answer the request, call finish_task."
            )

            tool_call = await self._query_gemini_for_action(
                system_instruction=system_instruction,
                observation=observation_text,
                history=history,
                api_key=api_key
            )

            if not tool_call:
                logger.warning(f"[BROWSER AGENT] Turn {turn}: Gemini did not return a valid tool call. Reading page...")
                tool_call = {"name": "read_page", "args": {"mode": "all"}}

            action_name = tool_call.get("name", "read_page")
            action_args = tool_call.get("args", {})

            # ── Check for Task Completion ───────────────────────────────────
            if action_name == "finish_task":
                final_answer = action_args.get("answer", "")
                sources = action_args.get("sources", visited_urls)
                logger.info(f"[BROWSER AGENT] Task {task_id} completed successfully by agent!")
                
                # Take final screenshot for visual confirmation
                screenshot_res = await browser_tools.take_screenshot(session_id=sid)
                
                await ws_manager.broadcast({
                    "event": "TASK_COMPLETED",
                    "task_id": task_id,
                    "response": final_answer,
                    "message": f"Browser task completed: {final_answer[:120]}...",
                    "sources": sources,
                    "screenshot_b64": screenshot_res.get("image_base64") if screenshot_res.get("success") else None,
                    "timestamp": datetime.utcnow().isoformat()
                })
                return {
                    "success": True,
                    "status": "COMPLETED",
                    "answer": final_answer,
                    "sources": sources,
                    "visited_urls": visited_urls,
                    "action_log": action_log
                }

            # ── 3. ACT ───────────────────────────────────────────────────────
            await ws_manager.broadcast({
                "event": "TASK_PROGRESS",
                "task_id": task_id,
                "browser_event": "BROWSER_ACTION_EXECUTING",
                "action": action_name,
                "parameters": action_args,
                "message": f"⚡ Action: {action_name} with {action_args}",
                "timestamp": datetime.utcnow().isoformat()
            })

            action_result = await self._execute_tool(action_name, action_args, session_id=sid)

            # ── 4. VERIFY ────────────────────────────────────────────────────
            # Give page a moment to react
            await asyncio.sleep(1.0)
            verify_page = await session.ensure_active_page()
            new_url = verify_page.url
            new_title = await verify_page.title()
            
            verification_note = (
                f"Action '{action_name}' executed. Result: {action_result.get('status', 'SUCCESS')}. "
                f"New URL: {new_url} (Changed: {new_url != curr_url})"
            )

            action_log.append({
                "turn": turn,
                "action": action_name,
                "args": action_args,
                "result": action_result.get("message", "OK"),
                "verification": verification_note
            })

            history.append({"role": "user", "text": observation_text})
            history.append({"role": "model", "action": action_name, "args": action_args, "result": verification_note})

        # Max turns reached: summarize whatever evidence was collected
        summary_context = research_memory.build_research_context(task_id)
        fallback_answer = f"Completed research on {user_intent}. Visited: {', '.join(visited_urls[:4])}.\n\nEvidence Summary:\n{summary_context[:1000]}"
        
        await ws_manager.broadcast({
            "event": "TASK_COMPLETED",
            "task_id": task_id,
            "response": fallback_answer,
            "message": "Browser task reached max steps. Returning collected findings.",
            "sources": visited_urls,
            "timestamp": datetime.utcnow().isoformat()
        })

        return {
            "success": True,
            "status": "COMPLETED",
            "answer": fallback_answer,
            "sources": visited_urls,
            "action_log": action_log
        }

    async def _execute_tool(self, action_name: str, args: Dict[str, Any], session_id: str) -> Dict[str, Any]:
        """Dispatches an action to browser_tools."""
        try:
            if action_name == "navigate_to_url":
                return await browser_tools.navigate_to_url(args.get("url", ""), session_id=session_id)
            elif action_name == "read_page":
                return await browser_tools.read_page(mode=args.get("mode", "all"), session_id=session_id)
            elif action_name == "click_element":
                return await browser_tools.click_element(args.get("element_ref"), session_id=session_id)
            elif action_name == "type_text":
                return await browser_tools.type_text(
                    element_ref=args.get("element_ref"),
                    text=args.get("text", ""),
                    press_enter=args.get("press_enter", True),
                    session_id=session_id
                )
            elif action_name == "scroll_page":
                return await browser_tools.scroll_page(
                    direction=args.get("direction", "down"),
                    amount=args.get("amount", 600),
                    session_id=session_id
                )
            elif action_name == "press_key":
                return await browser_tools.press_key(args.get("key", "Enter"), session_id=session_id)
            elif action_name == "take_screenshot":
                return await browser_tools.take_screenshot(full_page=args.get("full_page", False), session_id=session_id)
            else:
                return {"success": False, "status": "UNKNOWN_TOOL", "error": f"Unknown tool: {action_name}"}
        except Exception as e:
            logger.error(f"Error executing browser tool '{action_name}': {e}")
            return {"success": False, "status": "FAILED", "error": str(e)}

    async def _query_gemini_for_action(
        self,
        system_instruction: str,
        observation: str,
        history: List[Dict[str, Any]],
        api_key: str
    ) -> Optional[Dict[str, Any]]:
        """Sends observation to Gemini and parses the next function call."""
        candidate_models = [
            "gemini-3.5-flash-lite",
            "gemini-3.5-flash",
            "gemini-3.8-flash",
            "gemini-flash-latest"
        ]

        contents = [
            {"role": "user", "parts": [{"text": f"System Instruction: {system_instruction}"}]},
            {"role": "model", "parts": [{"text": "Understood. I will control the browser to achieve the user's goal."}]}
        ]

        # Add recent conversation turns
        for h in history[-4:]:
            contents.append({"role": "user", "parts": [{"text": h.get("text", "")}]})
            contents.append({"role": "model", "parts": [{"text": f"Executed action: {h.get('action')} ({h.get('args')}) -> {h.get('result')}"}]})

        contents.append({"role": "user", "parts": [{"text": observation}]})

        payload = {
            "contents": contents,
            "tools": [{"function_declarations": BROWSER_TOOL_DECLARATIONS}],
            "tool_config": {"function_calling_config": {"mode": "AUTO"}}
        }

        async with httpx.AsyncClient() as client:
            for mod in candidate_models:
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{mod}:generateContent?key={api_key}"
                try:
                    resp = await client.post(url, json=payload, timeout=30.0)
                    if resp.status_code == 200:
                        data = resp.json()
                        candidates = data.get("candidates", [])
                        if not candidates:
                            continue
                        parts = candidates[0].get("content", {}).get("parts", [])
                        for part in parts:
                            if "functionCall" in part:
                                fc = part["functionCall"]
                                return {"name": fc.get("name"), "args": fc.get("args", {})}
                            
                            # Fallback if model answered in text with JSON code block
                            text = part.get("text", "").strip()
                            if "```json" in text:
                                try:
                                    clean_j = text.split("```json")[1].split("```")[0].strip()
                                    parsed = json.loads(clean_j)
                                    if "name" in parsed or "action" in parsed:
                                        return {
                                            "name": parsed.get("name", parsed.get("action")),
                                            "args": parsed.get("args", parsed.get("parameters", {}))
                                        }
                                except Exception:
                                    pass
                    elif resp.status_code in [404, 500, 502, 503, 504]:
                        continue
                    else:
                        logger.warning(f"Gemini API returned HTTP {resp.status_code}: {resp.text}")
                except Exception as e:
                    logger.error(f"Gemini error with model {mod}: {e}")
                    continue

        return None

browser_agent = BrowserAgent()
