from typing import Dict, Any, List, Optional
from pydantic import BaseModel
from app.permissions.engine import PermissionLevel

class ToolParameter(BaseModel):
    name: str
    type: str
    description: str
    required: bool = True

class Tool(BaseModel):
    name: str
    description: str
    category: str # File, Desktop, Browser, Media, Communication, Job, System, Memory, RAG, Mobile
    permission_level: PermissionLevel
    target_device: str = "laptop" # laptop, mobile, backend
    parameters: List[ToolParameter] = []

class ToolRegistry:
    def __init__(self):
        self._tools: Dict[str, Tool] = {}
        self._register_default_tools()

    def register(self, tool: Tool):
        self._tools[tool.name] = tool

    def get_tool(self, name: str) -> Optional[Tool]:
        return self._tools.get(name)

    def list_tools(self) -> List[Dict[str, Any]]:
        return [tool.dict() for tool in self._tools.values()]

    def _register_default_tools(self):
        # File Tools
        self.register(Tool(
            name="search_files",
            description="Search user's files by query or path",
            category="File",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="query", type="string", description="Filename or pattern to search"),
                ToolParameter(name="directory", type="string", description="Search directory", required=False)
            ]
        ))
        self.register(Tool(
            name="read_file",
            description="Read content of a text/document file",
            category="File",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="path", type="string", description="File path")]
        ))
        self.register(Tool(
            name="create_folder",
            description="Create a folder on the user's computer",
            category="File",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="path", type="string", description="Directory path to create")]
        ))
        self.register(Tool(
            name="create_file",
            description="Create a file with initial content",
            category="File",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="path", type="string", description="File path"),
                ToolParameter(name="content", type="string", description="File text content")
            ]
        ))
        self.register(Tool(
            name="move_file",
            description="Move a file from source to destination",
            category="File",
            permission_level=PermissionLevel.MEDIUM,
            parameters=[
                ToolParameter(name="source", type="string", description="Source path"),
                ToolParameter(name="destination", type="string", description="Destination path")
            ]
        ))
        self.register(Tool(
            name="copy_file",
            description="Copy a file from source to destination",
            category="File",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="source", type="string", description="Source path"),
                ToolParameter(name="destination", type="string", description="Destination path")
            ]
        ))
        self.register(Tool(
            name="delete_file",
            description="Delete a file or directory",
            category="File",
            permission_level=PermissionLevel.HIGH,
            parameters=[ToolParameter(name="path", type="string", description="File path to delete")]
        ))

        # Desktop Tools
        self.register(Tool(
            name="open_application",
            description="Open a desktop application on Windows",
            category="Desktop",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="app_name", type="string", description="Application name e.g. chrome, notepad, calc")]
        ))
        self.register(Tool(
            name="close_application",
            description="Close a desktop application",
            category="Desktop",
            permission_level=PermissionLevel.MEDIUM,
            parameters=[ToolParameter(name="app_name", type="string", description="Application process name")]
        ))
        self.register(Tool(
            name="keyboard_type",
            description="Simulate keyboard text typing",
            category="Desktop",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="text", type="string", description="Text to type")]
        ))
        self.register(Tool(
            name="keyboard_press",
            description="Simulate key press (e.g. enter, tab, ctrl+c)",
            category="Desktop",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="key", type="string", description="Key or shortcut name")]
        ))
        self.register(Tool(
            name="save_document",
            description="Save the currently open document in desktop app with specified filename",
            category="Desktop",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="file_name", type="string", description="Filename e.g. myname.txt or report.docx")]
        ))
        self.register(Tool(
            name="take_screenshot",
            description="Take a screenshot of the user's desktop screen",
            category="Desktop",
            permission_level=PermissionLevel.LOW,
            parameters=[]
        ))

        # Browser Tools
        self.register(Tool(
            name="open_browser",
            description="Open Playwright persistent interactive web browser",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="url", type="string", description="URL to open", required=False)]
        ))
        self.register(Tool(
            name="search_web",
            description="Perform a web search query on Google",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="query", type="string", description="Search query string")]
        ))
        self.register(Tool(
            name="navigate_to_url",
            description="Navigate the browser to a specific URL",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="url", type="string", description="Destination URL")]
        ))
        self.register(Tool(
            name="read_page",
            description="Extract visible webpage content, headings, articles, links, and forms",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="mode", type="string", description="Mode: 'all', 'text', or 'article'", required=False)]
        ))
        self.register(Tool(
            name="click_element",
            description="Click a webpage element by numbered reference or selector",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="element_ref", type="string", description="Element reference e.g. '[1]'")]
        ))
        self.register(Tool(
            name="type_text",
            description="Type text into an input field or search bar",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="element_ref", type="string", description="Target element reference e.g. '[1]'"),
                ToolParameter(name="text", type="string", description="Text to enter"),
                ToolParameter(name="press_enter", type="boolean", description="Whether to press Enter", required=False)
            ]
        ))
        self.register(Tool(
            name="scroll_page",
            description="Scroll webpage up or down",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="direction", type="string", description="Scroll direction: 'down' or 'up'", required=False),
                ToolParameter(name="amount", type="integer", description="Pixels to scroll", required=False)
            ]
        ))
        self.register(Tool(
            name="press_key",
            description="Press a keyboard key in the browser",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="key", type="string", description="Key name e.g. 'Enter', 'Escape'")]
        ))
        self.register(Tool(
            name="get_interactive_elements",
            description="Inspect the page and list numbered interactive elements",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[]
        ))
        self.register(Tool(
            name="manage_tabs",
            description="List, open, switch, or close browser tabs",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="action", type="string", description="Action: 'list', 'open', 'switch', 'close'"),
                ToolParameter(name="tab_index", type="integer", description="Index of tab", required=False),
                ToolParameter(name="url", type="string", description="URL for new tab", required=False)
            ]
        ))
        self.register(Tool(
            name="get_browser_state",
            description="Get current URL, title, open tabs, and visible content preview",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[]
        ))
        self.register(Tool(
            name="autonomous_browser_task",
            description="Execute an autonomous multi-step browser research, navigation, and reading workflow",
            category="Browser",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="instruction", type="string", description="Detailed browser instruction or research objective")]
        ))

        # Media Tools
        self.register(Tool(
            name="search_youtube",
            description="Search YouTube videos and open playback",
            category="Media",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="query", type="string", description="YouTube video search term")]
        ))

        # Communication Tools
        self.register(Tool(
            name="send_email",
            description="Draft and send an email via configured provider",
            category="Communication",
            permission_level=PermissionLevel.HIGH,
            parameters=[
                ToolParameter(name="recipient", type="string", description="Recipient email address"),
                ToolParameter(name="subject", type="string", description="Email subject"),
                ToolParameter(name="body", type="string", description="Email body text")
            ]
        ))
        self.register(Tool(
            name="read_email",
            description="Search and read recent emails",
            category="Communication",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="query", type="string", description="Search keyword")]
        ))

        # Job Tools
        self.register(Tool(
            name="search_jobs",
            description="Search online job portals for matching roles",
            category="Job",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="keywords", type="string", description="Role title or keywords"),
                ToolParameter(name="location", type="string", description="Job location filter", required=False)
            ]
        ))
        self.register(Tool(
            name="fill_job_application",
            description="Pre-fill a job application form and attach resume",
            category="Job",
            permission_level=PermissionLevel.MEDIUM,
            parameters=[
                ToolParameter(name="job_title", type="string", description="Target role title"),
                ToolParameter(name="company", type="string", description="Target company name"),
                ToolParameter(name="resume_path", type="string", description="Path to user resume file")
            ]
        ))
        self.register(Tool(
            name="submit_job_application",
            description="Submit job application to employer",
            category="Job",
            permission_level=PermissionLevel.HIGH,
            parameters=[
                ToolParameter(name="job_id", type="string", description="Job application tracking ID"),
                ToolParameter(name="company", type="string", description="Company name")
            ]
        ))

        # RAG Tools
        self.register(Tool(
            name="search_personal_documents",
            description="RAG search across indexed personal files",
            category="RAG",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="query", type="string", description="Question or query string")]
        ))

        # Mobile Tools
        self.register(Tool(
            name="search_youtube_mobile",
            description="Search and open YouTube videos directly on mobile phone",
            category="Mobile",
            permission_level=PermissionLevel.LOW,
            target_device="mobile",
            parameters=[ToolParameter(name="query", type="string", description="YouTube query string")]
        ))
        self.register(Tool(
            name="open_mobile_app",
            description="Open an application on mobile phone",
            category="Mobile",
            permission_level=PermissionLevel.LOW,
            target_device="mobile",
            parameters=[ToolParameter(name="app_name", type="string", description="Mobile app name e.g. youtube, camera, browser")]
        ))
        self.register(Tool(
            name="open_url_mobile",
            description="Open a website URL on mobile phone",
            category="Mobile",
            permission_level=PermissionLevel.LOW,
            target_device="mobile",
            parameters=[ToolParameter(name="url", type="string", description="URL to open on mobile phone")]
        ))

        # Device & Status Tools
        self.register(Tool(
            name="get_battery_status",
            description="Get current battery percentage and charging status of phone or laptop",
            category="System",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="target_device", type="string", description="laptop or mobile", required=False)]
        ))
        self.register(Tool(
            name="battery_info",
            description="Fetch battery information for specified device",
            category="System",
            permission_level=PermissionLevel.LOW,
            parameters=[ToolParameter(name="device", type="string", description="laptop or phone", required=False)]
        ))
        self.register(Tool(
            name="sync_clipboard",
            description="Copy or sync text to specified target device clipboard",
            category="System",
            permission_level=PermissionLevel.LOW,
            parameters=[
                ToolParameter(name="text", type="string", description="Text to copy to clipboard"),
                ToolParameter(name="target_device", type="string", description="laptop or phone", required=False)
            ]
        ))
        self.register(Tool(
            name="send_file",
            description="Transfer a file securely between laptop and phone",
            category="System",
            permission_level=PermissionLevel.MEDIUM,
            parameters=[
                ToolParameter(name="file_path", type="string", description="Path or filename to transfer"),
                ToolParameter(name="target_device", type="string", description="laptop or phone", required=False)
            ]
        ))

tool_registry = ToolRegistry()
