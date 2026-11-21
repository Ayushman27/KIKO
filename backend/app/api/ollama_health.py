"""
Ollama health check and model management API.
Provides endpoints used by the KIKO frontend to display Ollama connection status.
"""
import logging
from fastapi import APIRouter
from app.ai.providers import OllamaProvider
from app.api.settings import load_llm_config
from app.core.config import settings

logger = logging.getLogger("kiko.ollama_health")
router = APIRouter(prefix="/ollama", tags=["Ollama"])


def _get_ollama_provider() -> OllamaProvider:
    """Get OllamaProvider using current LLM config (URL + model from settings file)."""
    cfg = load_llm_config()
    return OllamaProvider(
        base_url=cfg.get("ollama_base_url") or settings.OLLAMA_BASE_URL,
        model=cfg.get("ollama_model") or settings.OLLAMA_MODEL,
    )


@router.get("/health")
async def ollama_health():
    """
    Check if Ollama is running and whether the configured model (qwen3:4b) is available.
    Returns:
        {
            "online": bool,
            "model_available": bool,
            "configured_model": str,
            "available_models": [str, ...]  // only if online
        }
    """
    provider = _get_ollama_provider()
    result = await provider.check_health()
    logger.info(f"[OLLAMA HEALTH] {result}")
    return result


@router.get("/models")
async def list_ollama_models():
    """List all models currently installed in Ollama."""
    import httpx
    cfg = load_llm_config()
    base_url = (cfg.get("ollama_base_url") or settings.OLLAMA_BASE_URL).rstrip("/")
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{base_url}/api/tags", timeout=5.0)
            if resp.status_code == 200:
                models_data = resp.json().get("models", [])
                return {
                    "online": True,
                    "models": [
                        {
                            "name": m.get("name"),
                            "size": m.get("size"),
                            "modified_at": m.get("modified_at"),
                        }
                        for m in models_data
                    ]
                }
            return {"online": False, "models": [], "error": f"HTTP {resp.status_code}"}
    except Exception as e:
        return {"online": False, "models": [], "error": str(e)}


@router.post("/test")
async def test_ollama_chat():
    """
    Send a minimal test message to Ollama using the configured model.
    Useful for verifying end-to-end chat pipeline without going through task orchestration.
    """
    provider = _get_ollama_provider()
    try:
        response = await provider.generate_response(
            prompt="Say 'Hello from KIKO' in one sentence.",
            system_prompt="You are a helpful assistant. Be very brief."
        )
        return {
            "success": True,
            "model": provider.model,
            "response": response
        }
    except Exception as e:
        logger.error(f"[OLLAMA TEST] Error: {e}")
        return {
            "success": False,
            "model": provider.model,
            "error": str(e)
        }
