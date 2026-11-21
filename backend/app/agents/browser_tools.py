import re
import logging
from typing import Dict, Any, List, Optional, Tuple
from urllib.parse import urlparse
from playwright.async_api import Page, Locator, Error as PlaywrightError
from app.agents.browser_session import browser_session_manager, BrowserSession
from app.agents.browser_reader import browser_reader
from app.agents.browser_vision import browser_vision

logger = logging.getLogger("kiko.browser.tools")

BLOCKED_HOSTS = {
    "169.254.169.254", # AWS/GCP metadata
    "metadata.google.internal"
}

class BrowserToolDispatcher:
    """Dispatches validated browser actions on the active persistent Playwright session."""

    def __init__(self):
        # Maps session_id -> { element_id -> selector / locator info }
        self._element_registries: Dict[str, Dict[int, Dict[str, Any]]] = {}

    def _validate_url(self, url: str) -> Tuple[bool, str]:
        """Ensures the destination URL is safe and valid HTTP/HTTPS."""
        clean = url.strip()
        parsed = urlparse(clean)

        if parsed.scheme:
            if parsed.scheme.lower() not in ["http", "https", "about"]:
                return False, f"Unsupported protocol '{parsed.scheme}'. Only HTTP and HTTPS are permitted."
        else:
            clean = f"https://{clean}"
            parsed = urlparse(clean)

        hostname = (parsed.hostname or "").lower()
        if hostname in BLOCKED_HOSTS:
            return False, f"Access to '{hostname}' is blocked for security reasons."

        return True, clean

    async def get_or_create_session(self, session_id: Optional[str] = None) -> BrowserSession:
        return await browser_session_manager.get_or_create_session(session_id=session_id)

    # ── Tool 1: navigate_to_url ──────────────────────────────────────────────
    async def navigate_to_url(self, url: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        valid, safe_url = self._validate_url(url)
        if not valid:
            return {"success": False, "status": "BLOCKED", "error": safe_url}

        session = await self.get_or_create_session(session_id)
        result = await session.navigate(safe_url)
        # Clear element registry on new navigation
        self._element_registries[session.session_id] = {}
        return result

    # ── Tool 2: read_page ────────────────────────────────────────────────────
    async def read_page(self, mode: str = "all", session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()
        return await browser_reader.read_page(page, mode=mode)

    # ── Tool 3: take_screenshot ──────────────────────────────────────────────
    async def take_screenshot(self, full_page: bool = False, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()
        return await browser_vision.capture_screenshot(page, full_page=full_page)

    # ── Tool 8: get_interactive_elements ─────────────────────────────────────
    async def get_interactive_elements(self, session_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Discovers all visible interactive elements (inputs, buttons, links, selects),
        assigns grounded numbers [1], [2], etc., and stores their reliable locators.
        """
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()

        raw_elements = await page.evaluate("""() => {
            function isVisible(elem) {
                if (!elem) return false;
                const style = window.getComputedStyle(elem);
                return style && style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && elem.offsetWidth > 0 && elem.offsetHeight > 0;
            }

            const candidates = document.querySelectorAll('button, a[href], input, textarea, select, [role="button"], [role="link"], [role="textbox"], [role="searchbox"]');
            const items = [];
            let counter = 1;

            candidates.forEach(elem => {
                if (!isVisible(elem)) return;
                if (counter > 60) return; // Top 60 most relevant interactive elements

                const tag = elem.tagName.toLowerCase();
                let type = 'unknown';
                let name = '';
                let selector = '';

                if (tag === 'a') {
                    type = 'Link';
                    name = (elem.innerText || elem.getAttribute('title') || '').trim();
                    const href = elem.getAttribute('href');
                    if (!name && href) name = href;
                } else if (tag === 'button' || elem.getAttribute('role') === 'button') {
                    type = 'Button';
                    name = (elem.innerText || elem.getAttribute('aria-label') || elem.getAttribute('title') || elem.getAttribute('value') || '').trim();
                } else if (tag === 'input') {
                    const inpType = (elem.getAttribute('type') || 'text').toLowerCase();
                    if (['button', 'submit'].includes(inpType)) {
                        type = 'Button';
                        name = (elem.value || elem.getAttribute('aria-label') || '').trim();
                    } else {
                        type = 'Textbox';
                        name = (elem.getAttribute('placeholder') || elem.getAttribute('aria-label') || elem.getAttribute('name') || elem.getAttribute('id') || inpType).trim();
                    }
                } else if (tag === 'textarea') {
                    type = 'Textbox';
                    name = (elem.getAttribute('placeholder') || elem.getAttribute('aria-label') || elem.getAttribute('name') || '').trim();
                } else if (tag === 'select') {
                    type = 'Dropdown';
                    name = (elem.getAttribute('name') || elem.getAttribute('aria-label') || '').trim();
                }

                if (!name) name = tag;
                name = name.replace(/\\s+/g, ' ').substring(0, 80);

                // Build unique selector
                if (elem.id) {
                    selector = `#${CSS.escape(elem.id)}`;
                } else if (elem.getAttribute('name')) {
                    selector = `${tag}[name="${CSS.escape(elem.getAttribute('name'))}"]`;
                } else if (elem.getAttribute('aria-label')) {
                    selector = `[aria-label="${CSS.escape(elem.getAttribute('aria-label'))}"]`;
                } else if (tag === 'a' && elem.getAttribute('href') && elem.getAttribute('href').length < 80) {
                    selector = `a[href="${CSS.escape(elem.getAttribute('href'))}"]`;
                } else {
                    selector = `${tag}:has-text("${name.substring(0, 30).replace(/"/g, '')}")`;
                }

                const rect = elem.getBoundingClientRect();
                items.push({
                    index: counter,
                    type: type,
                    label: name,
                    selector: selector,
                    x: Math.round(rect.x + rect.width / 2),
                    y: Math.round(rect.y + rect.height / 2),
                    disabled: elem.disabled || elem.hasAttribute('disabled')
                });
                counter++;
            });

            return items;
        }""")

        # Store in session element registry
        reg: Dict[int, Dict[str, Any]] = {}
        formatted_list = []
        for item in raw_elements:
            idx = item["index"]
            reg[idx] = item
            formatted_list.append(f"[{idx}] {item['type']}: \"{item['label']}\"")

        self._element_registries[session.session_id] = reg
        return {
            "success": True,
            "count": len(raw_elements),
            "elements": raw_elements,
            "formatted": formatted_list,
            "message": f"Discovered {len(raw_elements)} interactive elements on {page.url}"
        }

    def _resolve_element_locator(self, page: Page, session_id: str, element_ref: Any) -> Locator:
        """Resolves an element reference (number e.g. 1, string e.g. '[1]', or CSS text selector) to a Playwright Locator."""
        ref_str = str(element_ref).strip()
        num_match = re.search(r'\[?(\d+)\]?', ref_str)
        
        reg = self._element_registries.get(session_id, {})
        if num_match:
            idx = int(num_match.group(1))
            if idx in reg:
                item = reg[idx]
                selector = item.get("selector")
                if selector:
                    try:
                        return page.locator(selector).first
                    except Exception:
                        pass
                # Fallback to role / text
                label = item.get("label", "")
                elem_type = item.get("type", "")
                if elem_type == "Button":
                    return page.get_by_role("button", name=label).first
                elif elem_type == "Link":
                    return page.get_by_role("link", name=label).first
                elif elem_type == "Textbox":
                    return page.get_by_role("textbox", name=label).first
                return page.get_by_text(label).first

        # If selector or raw label supplied directly
        try:
            return page.locator(ref_str).first
        except Exception:
            return page.get_by_text(ref_str).first

    # ── Tool 4: click_element ────────────────────────────────────────────────
    async def click_element(self, element_ref: Any, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()
        prev_url = page.url

        try:
            locator = self._resolve_element_locator(page, session.session_id, element_ref)
            await locator.scroll_into_view_if_needed(timeout=4000)
            await locator.click(timeout=6000)
            
            # Brief settling wait
            try:
                await page.wait_for_load_state("domcontentloaded", timeout=3000)
            except Exception:
                pass

            curr_url = page.url
            curr_title = await page.title()
            url_changed = (curr_url != prev_url)

            return {
                "success": True,
                "status": "SUCCESS",
                "element_ref": str(element_ref),
                "previous_url": prev_url,
                "current_url": curr_url,
                "current_title": curr_title,
                "url_changed": url_changed,
                "message": f"Clicked element '{element_ref}'. Current URL: {curr_url}"
            }
        except PlaywrightError as pe:
            logger.warning(f"Click failed for '{element_ref}': {pe}")
            return {
                "success": False,
                "status": "FAILED",
                "element_ref": str(element_ref),
                "error": str(pe),
                "message": f"Could not click element '{element_ref}': {str(pe)}"
            }

    # ── Tool 5: type_text ────────────────────────────────────────────────────
    async def type_text(self, element_ref: Any, text: str, press_enter: bool = False, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()

        try:
            locator = self._resolve_element_locator(page, session.session_id, element_ref)
            await locator.scroll_into_view_if_needed(timeout=4000)
            await locator.click(timeout=4000)
            # Fill text cleanly
            await locator.fill(text)
            
            if press_enter:
                await locator.press("Enter")
                try:
                    await page.wait_for_load_state("domcontentloaded", timeout=4000)
                except Exception:
                    pass

            return {
                "success": True,
                "status": "SUCCESS",
                "element_ref": str(element_ref),
                "typed_text": text,
                "current_url": page.url,
                "message": f"Typed '{text}' into '{element_ref}'" + (" and pressed Enter." if press_enter else ".")
            }
        except PlaywrightError as pe:
            logger.warning(f"Typing failed for '{element_ref}': {pe}")
            return {
                "success": False,
                "status": "FAILED",
                "element_ref": str(element_ref),
                "error": str(pe),
                "message": f"Failed to type into element '{element_ref}': {str(pe)}"
            }

    # ── Tool 6: scroll_page ──────────────────────────────────────────────────
    async def scroll_page(self, direction: str = "down", amount: int = 600, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()

        delta_y = amount if direction.lower() == "down" else -amount
        try:
            await page.mouse.wheel(0, delta_y)
            await page.wait_for_timeout(300) # Let smooth scroll settle
            
            scroll_y = await page.evaluate("() => window.scrollY")
            max_scroll = await page.evaluate("() => document.body.scrollHeight - window.innerHeight")
            
            return {
                "success": True,
                "status": "SUCCESS",
                "direction": direction,
                "amount": amount,
                "current_scroll_y": scroll_y,
                "max_scroll": max_scroll,
                "message": f"Scrolled {direction} by {amount}px (Position: {scroll_y}/{max_scroll})"
            }
        except Exception as e:
            return {"success": False, "status": "FAILED", "error": str(e)}

    # ── Tool 7: press_key ────────────────────────────────────────────────────
    async def press_key(self, key: str, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()

        try:
            await page.keyboard.press(key)
            return {
                "success": True,
                "status": "SUCCESS",
                "key": key,
                "message": f"Pressed key '{key}'"
            }
        except Exception as e:
            return {"success": False, "status": "FAILED", "error": str(e)}

    # ── Tool 9: manage_tabs ──────────────────────────────────────────────────
    async def manage_tabs(self, action: str, tab_index: Optional[int] = None, url: Optional[str] = None, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        act = action.lower().strip()
        if act == "list":
            tabs = await session.get_tabs()
            return {"success": True, "tabs": tabs, "count": len(tabs)}
        elif act == "open" or act == "new":
            return await session.new_tab(url=url)
        elif act == "switch":
            idx = tab_index if tab_index is not None else 0
            return await session.switch_tab(idx)
        elif act == "close":
            return await session.close_tab(tab_index)
        else:
            return {"success": False, "error": f"Unknown tab action '{action}'. Valid: list, open, switch, close"}

    # ── Tool 10: get_browser_state ───────────────────────────────────────────
    async def get_browser_state(self, session_id: Optional[str] = None) -> Dict[str, Any]:
        session = await self.get_or_create_session(session_id)
        page = await session.ensure_active_page()

        title = await page.title()
        url = page.url
        tabs = await session.get_tabs()
        
        # Read brief content snippet
        reader_res = await browser_reader.read_page(page, mode="text")
        content_snippet = reader_res.get("main_content", "")[:1000]

        return {
            "success": True,
            "session_id": session.session_id,
            "current_url": url,
            "page_title": title,
            "active_tab_index": session.active_page_index,
            "total_tabs": len(tabs),
            "content_preview": content_snippet,
            "headings": reader_res.get("headings", [])[:5],
            "buttons": reader_res.get("buttons", [])[:8],
            "message": f"Browser active at {url} ('{title}')"
        }

browser_tools = BrowserToolDispatcher()
