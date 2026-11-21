import os
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    PROJECT_NAME: str = "KIKO Personal Agent Platform"
    VERSION: str = "1.1.0"
    API_V1_STR: str = "/api/v1"
    
    SECRET_KEY: str = os.getenv("SECRET_KEY", "kiko_super_secret_jwt_key_change_in_production_2026")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    
    # Database
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./kiko.db")
    
    # AI Providers
    DEFAULT_LLM_PROVIDER: str = os.getenv("DEFAULT_LLM_PROVIDER", "ollama")  # ollama, openai, gemini, anthropic, groq, local, rule
    OPENAI_API_KEY: Optional[str] = os.getenv("OPENAI_API_KEY", "")
    OPENAI_MODEL: str = os.getenv("OPENAI_MODEL", "gpt-4o")
    GEMINI_API_KEY: Optional[str] = os.getenv("GEMINI_API_KEY", "")
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite")
    
    # Ollama / Local LLM (default: qwen3:4b)
    OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://localhost:11434")
    OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "qwen3:4b")
    OLLAMA_TIMEOUT: float = float(os.getenv("OLLAMA_TIMEOUT", "120.0"))  # seconds; Qwen3 may need time to load
    
    LOCAL_LLM_URL: str = os.getenv("LOCAL_LLM_URL", "http://localhost:8000/v1")
    LOCAL_LLM_MODEL: str = os.getenv("LOCAL_LLM_MODEL", "local-model")
    
    # Agent operating mode: 'alpha' | 'g_mode'
    DEFAULT_AGENT_MODE: str = os.getenv("DEFAULT_AGENT_MODE", "alpha")
    
    # Storage & Indexing
    STORAGE_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../data"))
    
    # G Mode: isolated experiment workspace (never overlaps with main codebase)
    G_MODE_WORKSPACE_DIR: str = os.getenv(
        "G_MODE_WORKSPACE_DIR",
        os.path.abspath(os.path.join(os.path.dirname(__file__), "../../data/g_workspace"))
    )
    
    # G Mode resource limits
    G_MODE_MAX_RUNTIME_SECS: int = int(os.getenv("G_MODE_MAX_RUNTIME_SECS", "3600"))  # 1 hour default
    G_MODE_MAX_PARALLEL_EXPERIMENTS: int = int(os.getenv("G_MODE_MAX_PARALLEL_EXPERIMENTS", "2"))
    G_MODE_MAX_RETRIES: int = int(os.getenv("G_MODE_MAX_RETRIES", "3"))
    
    class Config:
        case_sensitive = True

settings = Settings()
os.makedirs(settings.STORAGE_DIR, exist_ok=True)
os.makedirs(settings.G_MODE_WORKSPACE_DIR, exist_ok=True)
