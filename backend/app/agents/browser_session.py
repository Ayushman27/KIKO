import os
import sys
import logging
import asyncio
from typing import Dict, Any, List, Optional
from playwright.async_api import async_playwright, Playwright, Browser, BrowserContext, Page, Error as PlaywrightError

logger = logging.getLogger("kiko.browser.session")

if sys.platform == "win32":
    try:
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
    except Exception:
        pass

class BrowserSession:
    """Encapsulates a persistent Playwright browser context, tracking tabs and active page."""
    
    def __init__(self, session_id: str, browser: Browser, context: BrowserContext, headless: bool = False):
        self.session_id = session_id
        self.browser = browser
        self.context = context
        self.headless = headless
        self.pages: List[Page] = []
        self.active_page_index: int = 0
        self.is_closed: bool = False
        self.last_action_time: float = asyncio.get_event_loop().time()
        self.research_sources: List[Dict[str, Any]] = []

    @property
    def active_page(self) -> Page:
        if not self.pages:
            raise RuntimeError(f"No pages open in browser session '{self.session_id}'")
        if self.active_page_index >= len(self.pages):
            self.active_page_index = len(self.pages) - 1
        return self.pages[self.active_page_index]

    async def ensure_active_page(self) -> Page:
        """Ensures at least one valid, unclosed page is available."""
        # Filter out closed pages
        self.pages = [p for p in self.pages if not p.is_closed()]
        if not self.pages:
            page = await self.context.new_page()
            self.pages.append(page)
            self.active_page_index = 0
            self._setup_page_event_listeners(page)
        return self.active_page

    def _setup_page_event_listeners(self, page: Page):
        """Monitors page close or crash events."""
        def on_close(p):
            logger.info(f"[SESSION {self.session_id}] Tab closed: {p.url}")
            if p in self.pages:
                self.pages.remove(p)
                if self.active_page_index >= len(self.pages) and self.pages:
                    self.active_page_index = len(self.pages) - 1
        page.on("close", on_close)

    async def navigate(self, url: str, timeout: int = 30000) -> Dict[str, Any]:
        """Navigates the active page to a given URL with proper network/DOM wait."""
        page = await self.ensure_active_page()
        clean_url = url.strip()
        if not (clean_url.startswith("http://") or clean_url.startswith("https://") or clean_url.startswith("about:")):
            clean_url = f"https://{clean_url}"

        logger.info(f"[SESSION {self.session_id}] Navigating to: {clean_url}")
        self.last_action_time = asyncio.get_event_loop().time()
        
        try:
            # First try domcontentloaded, then wait for load or network idle safely
            response = await page.goto(clean_url, wait_until="domcontentloaded", timeout=timeout)
            try:
                await page.wait_for_load_state("load", timeout=5000)
            except Exception:
                pass # Many heavy websites never reach pure 'load' state, domcontentloaded is sufficient
            
            title = await page.title()
            final_url = page.url
            status_code = response.status if response else 200
            
            return {
                "success": True,
                "status": "SUCCESS",
                "url": final_url,
                "title": title,
                "http_status": status_code,
                "message": f"Successfully navigated to {final_url} (Title: '{title}')"
            }
        except PlaywrightError as pe:
            logger.warning(f"[SESSION {self.session_id}] Navigation warning: {pe}")
            # Even if wait timed out, check if URL loaded partially
            try:
                curr_url = page.url
                curr_title = await page.title()
                if curr_url and curr_url != "about:blank":
                    return {
                        "success": True,
                        "status": "PARTIAL_SUCCESS",
                        "url": curr_url,
                        "title": curr_title,
                        "message": f"Page loaded with partial timeout: {curr_url}"
                    }
            except Exception:
                pass
            return {
                "success": False,
                "status": "FAILED",
                "url": clean_url,
                "error": str(pe),
                "message": f"Failed to navigate to {clean_url}: {str(pe)}"
            }

    async def get_tabs(self) -> List[Dict[str, Any]]:
        """Lists all open tabs in this session."""
        self.pages = [p for p in self.pages if not p.is_closed()]
        results = []
        for idx, p in enumerate(self.pages):
            try:
                title = await p.title()
                results.append({
                    "index": idx,
                    "url": p.url,
                    "title": title,
                    "is_active": idx == self.active_page_index
                })
            except Exception:
                results.append({
                    "index": idx,
                    "url": p.url,
                    "title": "Untitled",
                    "is_active": idx == self.active_page_index
                })
        return results

    async def new_tab(self, url: Optional[str] = None) -> Dict[str, Any]:
        """Opens a new tab in the current browser context."""
        page = await self.context.new_page()
        self.pages.append(page)
        self.active_page_index = len(self.pages) - 1
        self._setup_page_event_listeners(page)
        
        if url:
            return await self.navigate(url)
        return {
            "success": True,
            "status": "SUCCESS",
            "tab_index": self.active_page_index,
            "url": "about:blank",
            "message": "Opened new blank tab"
        }

    async def switch_tab(self, tab_index: int) -> Dict[str, Any]:
        """Switches active focus to another open tab."""
        self.pages = [p for p in self.pages if not p.is_closed()]
        if 0 <= tab_index < len(self.pages):
            self.active_page_index = tab_index
            page = self.pages[tab_index]
            await page.bring_to_front()
            title = await page.title()
            return {
                "success": True,
                "status": "SUCCESS",
                "active_tab": tab_index,
                "url": page.url,
                "title": title,
                "message": f"Switched to tab #{tab_index}: '{title}' ({page.url})"
            }
        return {
            "success": False,
            "status": "FAILED",
            "message": f"Tab index {tab_index} out of range (open tabs: {len(self.pages)})"
        }

    async def close_tab(self, tab_index: Optional[int] = None) -> Dict[str, Any]:
        """Closes a tab. If omitted, closes the active tab."""
        self.pages = [p for p in self.pages if not p.is_closed()]
        idx = self.active_page_index if tab_index is None else tab_index
        if 0 <= idx < len(self.pages):
            target_page = self.pages[idx]
            await target_page.close()
            self.pages = [p for p in self.pages if not p.is_closed()]
            if self.active_page_index >= len(self.pages) and self.pages:
                self.active_page_index = len(self.pages) - 1
            return {
                "success": True,
                "status": "SUCCESS",
                "message": f"Closed tab #{idx}. Remaining open tabs: {len(self.pages)}"
            }
        return {
            "success": False,
            "status": "FAILED",
            "message": f"Invalid tab index: {idx}"
        }

    async def close(self):
        """Gracefully closes all pages, context, and browser instance."""
        if self.is_closed:
            return
        self.is_closed = True
        try:
            await self.context.close()
        except Exception:
            pass
        try:
            await self.browser.close()
        except Exception:
            pass
        logger.info(f"[SESSION {self.session_id}] Browser session closed.")


class BrowserSessionManager:
    """Manages persistent browser sessions across tasks and multi-step interactions."""
    
    def __init__(self):
        self._playwright: Optional[Playwright] = None
        self._pw_loop: Optional[asyncio.AbstractEventLoop] = None
        self._sessions: Dict[str, BrowserSession] = {}
        self._default_session_id = "kiko_default_browser"

    def _get_lock(self) -> asyncio.Lock:
        loop = asyncio.get_running_loop()
        if not hasattr(self, "_current_loop") or self._current_loop != loop:
            self._current_loop = loop
            self._lock = asyncio.Lock()
        return self._lock

    async def _ensure_playwright(self) -> Playwright:
        """Initializes the Playwright driver for the active running event loop."""
        loop = asyncio.get_running_loop()
        if self._playwright and self._pw_loop != loop:
            for s in list(self._sessions.values()):
                s.is_closed = True
            self._sessions.clear()
            self._playwright = None

        if not self._playwright:
            self._playwright = await async_playwright().start()
            self._pw_loop = loop
        return self._playwright

    async def get_or_create_session(
        self,
        session_id: Optional[str] = None,
        headless: Optional[bool] = None
    ) -> BrowserSession:
        """Retrieves an existing session or starts a new persistent Chromium session."""
        async with self._get_lock():
            sid = session_id or self._default_session_id
            
            # Check existing session
            if sid in self._sessions:
                sess = self._sessions[sid]
                if not sess.is_closed and sess.browser.is_connected():
                    await sess.ensure_active_page()
                    return sess
                else:
                    logger.info(f"Session '{sid}' is disconnected or closed. Recreating...")
                    await sess.close()
                    del self._sessions[sid]

            # Determine headless mode: check env or parameter (default to visible False so user can watch if desired, or headless=False)
            if headless is None:
                env_headless = os.getenv("KIKO_BROWSER_HEADLESS", "false").lower()
                headless = (env_headless == "true" or env_headless == "1")

            pw = await self._ensure_playwright()

            # Launch browser: try Chrome channel, then Edge channel, then bundled Chromium
            browser = None
            launch_channels = ["chrome", "msedge", None]
            last_err = None

            for channel in launch_channels:
                try:
                    kwargs: Dict[str, Any] = {
                        "headless": headless,
                        "args": [
                            "--disable-blink-features=AutomationControlled",
                            "--no-default-browser-check",
                            "--no-first-run",
                            "--disable-infobars"
                        ]
                    }
                    if channel:
                        kwargs["channel"] = channel
                    
                    logger.info(f"Launching Playwright Chromium (channel={channel}, headless={headless})...")
                    browser = await pw.chromium.launch(**kwargs)
                    logger.info(f"Browser launched successfully with channel={channel}")
                    break
                except Exception as e:
                    last_err = e
                    logger.warning(f"Could not launch browser with channel={channel}: {e}")

            if not browser:
                raise RuntimeError(f"Failed to launch browser across all channels: {last_err}")

            # Create clean, isolated context (never import personal cookies or profiles)
            context = await browser.new_context(
                viewport={"width": 1280, "height": 800},
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                locale="en-US"
            )

            session = BrowserSession(session_id=sid, browser=browser, context=context, headless=headless)
            # Create initial page
            page = await context.new_page()
            session.pages.append(page)
            session.active_page_index = 0
            session._setup_page_event_listeners(page)

            self._sessions[sid] = session
            return session

    async def get_session(self, session_id: Optional[str] = None) -> Optional[BrowserSession]:
        sid = session_id or self._default_session_id
        return self._sessions.get(sid)

    async def close_session(self, session_id: Optional[str] = None):
        async with self._get_lock():
            sid = session_id or self._default_session_id
            if sid in self._sessions:
                sess = self._sessions[sid]
                await sess.close()
                del self._sessions[sid]

    async def close_all(self):
        """Closes all active sessions and shuts down the Playwright driver."""
        async with self._get_lock():
            for sid, sess in list(self._sessions.items()):
                try:
                    await sess.close()
                except Exception:
                    pass
            self._sessions.clear()
            if self._playwright:
                try:
                    await self._playwright.stop()
                except Exception:
                    pass
                self._playwright = None

# Global singleton
browser_session_manager = BrowserSessionManager()
