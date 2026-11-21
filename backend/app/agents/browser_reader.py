import logging
import re
from typing import Dict, Any, List, Optional
from bs4 import BeautifulSoup
try:
    import trafilatura
except Exception:
    trafilatura = None
from playwright.async_api import Page, Error as PlaywrightError

logger = logging.getLogger("kiko.browser.reader")

class BrowserReader:
    """Extracts structured, readable, boilerplate-free content from Playwright pages."""

    @staticmethod
    async def read_page(page: Page, mode: str = "all") -> Dict[str, Any]:
        """
        Extracts structured webpage information:
        - URL and title
        - Headings (H1-H3)
        - Main text / article content
        - Interactive elements (buttons, inputs, links)
        - Security / CAPTCHA checks
        """
        try:
            url = page.url
            title = await page.title()

            # Check if actually empty blank page
            page_content = await page.content()
            if (not url or url == "about:blank") and len(page_content.strip()) <= 40:
                return {
                    "success": False,
                    "url": url,
                    "title": title or "Blank Page",
                    "error": "The active page is blank. Please navigate to a valid URL first."
                }

            # 1. Evaluate page in-browser using Playwright DOM evaluation for dynamic & visible content
            dom_data = await page.evaluate("""() => {
                // Helper to check if element is visible
                function isVisible(elem) {
                    if (!elem) return false;
                    const style = window.getComputedStyle(elem);
                    return style && style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0' && elem.offsetWidth > 0 && elem.offsetHeight > 0;
                }

                // Collect Headings
                const headings = [];
                document.querySelectorAll('h1, h2, h3').forEach(h => {
                    if (isVisible(h)) {
                        const txt = h.innerText.trim();
                        if (txt.length > 0 && txt.length < 200) {
                            headings.push({ tag: h.tagName.toLowerCase(), text: txt });
                        }
                    }
                });

                // Collect Links (filter navigation boilerplate and empty hrefs)
                const links = [];
                const seenLinks = new Set();
                document.querySelectorAll('a[href]').forEach(a => {
                    if (isVisible(a)) {
                        const txt = a.innerText.trim();
                        const href = a.getAttribute('href');
                        if (txt.length > 1 && href && !href.startsWith('javascript:') && !href.startsWith('#')) {
                            try {
                                const fullUrl = new URL(href, document.baseURI).href;
                                if (!seenLinks.has(fullUrl) && links.length < 60) {
                                    seenLinks.add(fullUrl);
                                    links.push({ text: txt.replace(/\\s+/g, ' ').substring(0, 100), url: fullUrl });
                                }
                            } catch (e) {}
                        }
                    }
                });

                // Collect Input Fields & Forms
                const inputs = [];
                document.querySelectorAll('input, textarea, select').forEach(inp => {
                    if (isVisible(inp) && inp.type !== 'hidden') {
                        const name = inp.getAttribute('name') || inp.getAttribute('id') || inp.getAttribute('placeholder') || inp.getAttribute('aria-label') || '';
                        inputs.push({
                            type: inp.tagName.toLowerCase() === 'textarea' ? 'textarea' : (inp.getAttribute('type') || 'text'),
                            name: name,
                            placeholder: inp.getAttribute('placeholder') || '',
                            value: inp.value ? inp.value.substring(0, 50) : '',
                            required: inp.hasAttribute('required')
                        });
                    }
                });

                // Collect Buttons
                const buttons = [];
                document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"]').forEach(btn => {
                    if (isVisible(btn)) {
                        const label = (btn.innerText || btn.getAttribute('aria-label') || btn.getAttribute('value') || '').trim();
                        if (label.length > 0 && label.length < 80) {
                            buttons.push(label.replace(/\\s+/g, ' '));
                        }
                    }
                });

                // Collect Metadata
                let metaDesc = '';
                const descElem = document.querySelector('meta[name="description"]') || document.querySelector('meta[property="og:description"]');
                if (descElem) {
                    metaDesc = descElem.getAttribute('content') || '';
                }

                return {
                    headings: headings.slice(0, 25),
                    links: links.slice(0, 40),
                    inputs: inputs.slice(0, 20),
                    buttons: [...new Set(buttons)].slice(0, 20),
                    description: metaDesc.substring(0, 300)
                };
            }""")

            # 2. Extract Full Clean Text and Article Content
            raw_html = await page.content()
            
            # Check for CAPTCHA or blocking gates
            captcha_detected = False
            captcha_reason = ""
            html_lower = raw_html.lower()
            if any(term in html_lower for term in [
                "recaptcha", "g-recaptcha", "cf-turnstile", "hcaptcha", "challenges.cloudflare.com",
                "please verify you are human", "verify you are a human", "bot detection"
            ]):
                captcha_detected = True
                captcha_reason = "CAPTCHA / Bot detection challenge encountered."

            # Article extraction using trafilatura
            article_text = ""
            try:
                extracted = trafilatura.extract(raw_html, include_links=False, include_images=False, output_format="txt")
                if extracted:
                    article_text = extracted.strip()
            except Exception as te:
                logger.debug(f"Trafilatura extraction fallback: {te}")

            # BeautifulSoup fallback for visible text
            soup = BeautifulSoup(raw_html, "html.parser")
            # Remove scripts, styles, svg, and metadata tags
            for elem in soup(["script", "style", "svg", "noscript", "iframe", "head"]):
                elem.extract()

            visible_text = soup.get_text(separator="\n", strip=True)
            # Remove excessive blank lines
            clean_visible_text = re.sub(r'\n{3,}', '\n\n', visible_text).strip()

            # Choose main text
            main_text = article_text if (len(article_text) > 200) else clean_visible_text
            # Limit length for Gemini context (keep top 6000 chars of substantive content)
            truncated_text = main_text[:6000] if len(main_text) > 6000 else main_text

            return {
                "success": True,
                "url": url,
                "title": title,
                "description": dom_data.get("description", ""),
                "headings": dom_data.get("headings", []),
                "main_content": truncated_text,
                "character_count": len(main_text),
                "is_truncated": len(main_text) > 6000,
                "links": dom_data.get("links", []),
                "inputs": dom_data.get("inputs", []),
                "buttons": dom_data.get("buttons", []),
                "captcha_detected": captcha_detected,
                "captcha_reason": captcha_reason
            }

        except PlaywrightError as pe:
            logger.error(f"Error reading page: {pe}")
            return {
                "success": False,
                "url": page.url,
                "title": "Error",
                "error": f"Failed to read webpage content: {str(pe)}"
            }
        except Exception as e:
            logger.error(f"Unexpected reader error: {e}")
            return {
                "success": False,
                "url": page.url,
                "title": "Error",
                "error": f"Content extraction error: {str(e)}"
            }

browser_reader = BrowserReader()
