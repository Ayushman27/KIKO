import os
import json
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from app.core.config import settings

router = APIRouter(prefix="/settings", tags=["Settings"])

CONFIG_FILE = os.path.join(settings.STORAGE_DIR, "config_llm.json")

class LLMConfigRequest(BaseModel):
    selected_provider: str = "ollama"  # openai, anthropic, gemini, groq, ollama, local, rule
    openai_api_key: Optional[str] = ""
    openai_model: Optional[str] = "gpt-4o"
    anthropic_api_key: Optional[str] = ""
    anthropic_model: Optional[str] = "claude-3-5-sonnet-20240620"
    gemini_api_key: Optional[str] = ""
    gemini_model: Optional[str] = "gemini-1.5-flash"
    groq_api_key: Optional[str] = ""
    groq_model: Optional[str] = "llama-3.1-70b-versatile"
    ollama_base_url: Optional[str] = "http://localhost:11434"
    ollama_model: Optional[str] = "qwen3:4b"
    ollama_timeout: Optional[float] = 120.0

def load_llm_config() -> dict:
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data
        except Exception:
            pass
    return {
        "selected_provider": getattr(settings, "DEFAULT_LLM_PROVIDER", "ollama"),
        "openai_api_key": getattr(settings, "OPENAI_API_KEY", "") or "",
        "openai_model": getattr(settings, "OPENAI_MODEL", "gpt-4o"),
        "anthropic_api_key": getattr(settings, "ANTHROPIC_API_KEY", "") if hasattr(settings, "ANTHROPIC_API_KEY") else "",
        "anthropic_model": "claude-3-5-sonnet-20240620",
        "gemini_api_key": getattr(settings, "GEMINI_API_KEY", "") if hasattr(settings, "GEMINI_API_KEY") else "",
        "gemini_model": "gemini-1.5-flash",
        "groq_api_key": getattr(settings, "GROQ_API_KEY", "") if hasattr(settings, "GROQ_API_KEY") else "",
        "groq_model": "llama-3.1-70b-versatile",
        "ollama_base_url": getattr(settings, "OLLAMA_BASE_URL", "http://localhost:11434"),
        "ollama_model": getattr(settings, "OLLAMA_MODEL", "qwen3:4b"),
        "ollama_timeout": getattr(settings, "OLLAMA_TIMEOUT", 120.0),
    }

def save_llm_config(cfg: dict):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)

@router.get("/llm")
def get_llm_settings():
    return load_llm_config()

@router.post("/llm")
def update_llm_settings(req: LLMConfigRequest):
    cfg = req.dict()
    save_llm_config(cfg)
    
    # Update runtime settings
    settings.DEFAULT_LLM_PROVIDER = req.selected_provider
    if req.openai_api_key: settings.OPENAI_API_KEY = req.openai_api_key
    if req.openai_model: settings.OPENAI_MODEL = req.openai_model
    if req.ollama_base_url: settings.OLLAMA_BASE_URL = req.ollama_base_url
    if req.ollama_model: settings.OLLAMA_MODEL = req.ollama_model
    
    return {"status": "SUCCESS", "message": "LLM Provider and API key settings updated successfully.", "config": cfg}
