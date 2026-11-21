import asyncio
from playwright.async_api import async_playwright

async def test():
    async with async_playwright() as p:
        print('Starting chrome launch...')
        browser = await p.chromium.launch(channel='chrome', headless=True)
        print('Chrome launched!')
        page = await browser.new_page()
        await page.goto('about:blank')
        print('Page loaded, url:', page.url)
        await page.set_content('<html><head><title>Test Page</title></head><body><h1>Hello Kiko Browser</h1><button id="btn">Click Me</button></body></html>')
        title = await page.title()
        btn_text = await page.inner_text('#btn')
        print('Title:', title, '| Button:', btn_text)
        await browser.close()
        print('Browser closed successfully!')

asyncio.run(test())
