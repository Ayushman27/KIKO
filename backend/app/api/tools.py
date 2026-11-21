from fastapi import APIRouter
from app.tools.registry import tool_registry

router = APIRouter(prefix="/tools", tags=["Tools"])

@router.get("")
def list_tools():
    return tool_registry.list_tools()
