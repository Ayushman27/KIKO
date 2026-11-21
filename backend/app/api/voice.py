import asyncio
import base64
import json
import logging
import re
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, UploadFile, File, Form, HTTPException
from pydantic import BaseModel

from app.core.config import settings
from app.api.settings import load_llm_config
from app.orchestrator.engine import orchestrator
from app.database.session import SessionLocal
from app.services.gemini_live_voice import (
    synthesize_speech_live,
    transcribe_speech_multimodal,
    record_host_microphone,
    get_genai_client,
    get_gemini_api_key,
    PRIMARY_LIVE_MODEL,
    FALLBACK_LIVE_MODEL,
    AVAILABLE_VOICES,
    play_audio_async,
)
try:
    from google.genai import types
except ImportError:
    types = None

logger = logging.getLogger("kiko.voice")
router = APIRouter(prefix="/voice", tags=["Voice Agent"])

global_voice_chat_history = []


class TTSRequest(BaseModel):
    text: str
    voice: Optional[str] = "Puck"
    play_on_host: Optional[bool] = True


class STTRequest(BaseModel):
    audio_base64: str
    mime_type: Optional[str] = "audio/wav"


class RecordRequest(BaseModel):
    duration_seconds: Optional[float] = 3.0


@router.get("/status")
def get_voice_status():
    """Returns Gemini Live API and audio hardware status."""
    api_key = get_gemini_api_key()
    has_key = bool(api_key)
    
    input_dev = None
    output_dev = None
    try:
        import sounddevice as sd
        input_dev = sd.query_devices(kind="input").get("name", "Default Microphone")
        output_dev = sd.query_devices(kind="output").get("name", "Default Speaker")
    except Exception:
        pass

    return {
        "status": "ONLINE" if has_key else "NO_API_KEY",
        "live_model": PRIMARY_LIVE_MODEL,
        "available_voices": AVAILABLE_VOICES,
        "has_gemini_key": has_key,
        "input_device": input_dev,
        "output_device": output_dev,
    }


@router.get("/history")
def get_voice_history():
    from app.database.session import SessionLocal
    from app.models.domain import Task
    db = SessionLocal()
    try:
        tasks = db.query(Task).order_by(Task.created_at.asc()).all()
        result = []
        seen_prompts = set()

        for t in tasks:
            prompt = t.description
            resp = t.result_summary or f"Sure Ayushman, I am executing '{prompt}' for you right now."
            result.append({
                "role": "user",
                "text": prompt,
                "timestamp": t.created_at.isoformat() if t.created_at else ""
            })
            result.append({
                "role": "assistant",
                "text": f"KIKO: {resp}" if resp.startswith("KIKO:") or "Sure Ayushman" in resp else f"KIKO: {resp}",
                "timestamp": t.created_at.isoformat() if t.created_at else ""
            })
            seen_prompts.add(prompt.lower().strip())

        for item in global_voice_chat_history:
            if item.get("text", "").lower().strip() not in seen_prompts:
                result.append(item)

        return result[-50:]
    finally:
        db.close()


@router.post("/tts")
async def text_to_speech_endpoint(req: TTSRequest):
    """
    Dedicated Text-to-Speech (TTS) endpoint powered by Gemini Multimodal Live API.
    Converts text to natural 24kHz audio and optionally plays aloud on host speakers.
    """
    try:
        res = await synthesize_speech_live(
            text=req.text,
            voice=req.voice or "Puck",
            play_on_host=bool(req.play_on_host)
        )
        return res
    except Exception as e:
        logger.error(f"[TTS] Endpoint error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/stt")
async def speech_to_text_endpoint(
    file: Optional[UploadFile] = File(None),
    audio_base64: Optional[str] = Form(None),
    mime_type: Optional[str] = Form("audio/wav")
):
    """
    Dedicated Speech-to-Text (STT) endpoint powered by Gemini Multimodal API.
    Accepts raw audio file or base64 audio and outputs precise transcription.
    """
    try:
        if file is not None:
            audio_bytes = await file.read()
            detected_mime = file.content_type or mime_type or "audio/wav"
        elif audio_base64:
            audio_bytes = base64.b64decode(audio_base64)
            detected_mime = mime_type or "audio/wav"
        else:
            raise HTTPException(status_code=400, detail="Must provide either 'file' or 'audio_base64'")

        transcript = await transcribe_speech_multimodal(audio_bytes, mime_type=detected_mime)
        return {
            "status": "SUCCESS",
            "transcript": transcript,
            "bytes_processed": len(audio_bytes)
        }
    except Exception as e:
        logger.error(f"[STT] Endpoint error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/record_and_transcribe")
async def record_microphone_and_transcribe_endpoint(req: RecordRequest):
    """
    Captures live audio from the host microphone and immediately transcribes it via Gemini.
    """
    try:
        duration = float(req.duration_seconds or 3.0)
        wav_bytes = await asyncio.to_thread(record_host_microphone, duration)
        transcript = await transcribe_speech_multimodal(wav_bytes, mime_type="audio/wav")
        return {
            "status": "SUCCESS",
            "transcript": transcript,
            "audio_base64": base64.b64encode(wav_bytes).decode("ascii"),
            "duration": duration
        }
    except Exception as e:
        logger.error(f"[MIC-STT] Error recording or transcribing: {e}")
        return {
            "status": "ERROR",
            "transcript": "",
            "error": str(e)
        }


@router.websocket("/live")
async def gemini_live_voice_websocket(websocket: WebSocket):
    """
    Gemini Multimodal Live API Voice Agent WebSocket Bridge.
    Bidirectional streaming bridge connecting clients directly with Gemini Live session.
    Handles continuous microphone audio chunks (STT), voice synthesis streaming (TTS),
    and proactive tool/action execution.
    """
    await websocket.accept()
    logger.info("Voice Client connected to Gemini Live Agent WebSocket bridge.")

    api_key = get_gemini_api_key()
    client = None
    if api_key:
        try:
            client = get_genai_client(api_key)
        except Exception as e:
            logger.error(f"Failed to initialize GenAI client: {e}")

    session_chat_history = []
    pending_choice_task = None

    # Config for Gemini Live session
    live_config = types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name="Puck")
            )
        ),
        thinking_config=types.ThinkingConfig(thinking_budget=0),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        input_audio_transcription=types.AudioTranscriptionConfig(),
        system_instruction=types.Content(
            parts=[types.Part.from_text(text=(
                "You are KIKO, an advanced personal AI agent assisting Ayushman. "
                "Speak naturally, warmly, and concisely in 1-2 short sentences. "
                "Acknowledge instructions immediately and help him control apps, tasks, and search."
            ))]
        )
    )

    async def run_live_bridge():
        nonlocal pending_choice_task, session_chat_history

        # If Gemini Live is available, establish live session
        if client:
            try:
                async with client.aio.live.connect(model=PRIMARY_LIVE_MODEL, config=live_config) as live_session:
                    logger.info("Connected to Gemini Multimodal Live API AsyncSession.")

                    async def handle_client_incoming():
                        nonlocal pending_choice_task
                        while True:
                            data_str = await websocket.receive_text()
                            data = json.loads(data_str)
                            event_type = data.get("event")

                            if event_type in ["VOICE_PROMPT", "TEXT_PROMPT"]:
                                raw_user_text = data.get("text", "").strip()
                                if not raw_user_text:
                                    continue

                                logger.info(f"[VOICE] Speech prompt received: '{raw_user_text}'")

                                # Check device selection resolution
                                clean_text = re.sub(r'^(hello|hi|hey|greetings|please|kindly|kiko|koko|coco|cico|co|ko|ki|eco|echo|keeko|kiku|kikoo)\s+', '', raw_user_text, flags=re.IGNORECASE).strip()
                                user_text = clean_text if clean_text else raw_user_text

                                if pending_choice_task:
                                    pending_desc = pending_choice_task.get("task_description", "")
                                    raw_lower = raw_user_text.lower()
                                    if any(w in raw_lower for w in ["laptop", "pc", "desktop", "phone", "mobile"]):
                                        user_text = f"{pending_desc} on {raw_user_text}"
                                        pending_choice_task = None

                                action_keywords = ["open", "launch", "create", "make", "delete", "remove", "search", "find", "screenshot", "type", "write", "play", "run", "save", "add", "append", "close"]
                                is_action = any(re.search(r'\b' + kw + r'\b', user_text, re.IGNORECASE) for kw in action_keywords)

                                if is_action:
                                    # Execute tool action
                                    db = SessionLocal()
                                    try:
                                        task = await orchestrator.create_and_run_task(db, user_id="voice_user", description=user_text)
                                        if task.status == "FAILED":
                                            action_reply = "Your target device is currently offline. Please connect it first."
                                        elif task.status == "WAITING_CHOICE":
                                            action_reply = f"Which device would you like me to use for '{user_text}' — your laptop or your phone?"
                                            pending_choice_task = {"task_id": task.id, "task_description": user_text}
                                        else:
                                            action_reply = f"Sure Ayushman, I am executing '{user_text}' for you right now."
                                            await websocket.send_json({
                                                "event": "ACTION_DISPATCHED",
                                                "task_id": task.id,
                                                "message": f"Executing action: '{user_text}'"
                                            })
                                        
                                        # Synthesize TTS response via Live session
                                        await live_session.send_client_content(
                                            turns=[types.Content(role="user", parts=[types.Part.from_text(text=f"Say: {action_reply}")])],
                                            turn_complete=True
                                        )
                                    finally:
                                        db.close()
                                else:
                                    # Standard conversational turn
                                    await live_session.send_client_content(
                                        turns=[types.Content(role="user", parts=[types.Part.from_text(text=raw_user_text)])],
                                        turn_complete=True
                                    )

                            elif event_type == "AUDIO_CHUNK":
                                # Stream client microphone PCM chunk to Gemini Live for real-time STT
                                pcm_b64 = data.get("data")
                                if pcm_b64:
                                    pcm_raw = base64.b64decode(pcm_b64)
                                    await live_session.send_realtime_input(
                                        audio=types.Blob(mime_type="audio/pcm;rate=16000", data=pcm_raw)
                                    )

                    async def handle_gemini_outgoing():
                        accumulated_pcm = []
                        accumulated_text = ""

                        async for resp in live_session.receive():
                            if resp.server_content:
                                d = resp.model_dump(exclude_none=True)
                                sc = d.get("server_content", {})

                                # Live STT output transcript from Gemini
                                if "output_transcription" in sc:
                                    ot = sc["output_transcription"]
                                    if isinstance(ot, dict) and "text" in ot:
                                        accumulated_text += ot["text"]
                                        await websocket.send_json({
                                            "event": "VOICE_TRANSCRIPT",
                                            "text": ot["text"],
                                            "is_final": False
                                        })

                                # Live TTS audio chunk stream from Gemini
                                if resp.server_content.model_turn:
                                    for part in resp.server_content.model_turn.parts:
                                        if part.inline_data and part.inline_data.data:
                                            chunk = part.inline_data.data
                                            accumulated_pcm.append(chunk)
                                            await websocket.send_json({
                                                "event": "VOICE_CHUNK",
                                                "data": base64.b64encode(chunk).decode("ascii"),
                                                "sample_rate": 24000
                                            })

                                # Turn completed: play audio on host and complete response
                                if resp.server_content.turn_complete:
                                    if accumulated_pcm:
                                        full_raw = b"".join(accumulated_pcm)
                                        play_audio_async(full_raw, sample_rate=24000, is_wav=False)
                                    
                                    final_text = accumulated_text.strip()
                                    if final_text:
                                        session_chat_history.append({"role": "assistant", "content": final_text})
                                        global_voice_chat_history.append({"role": "assistant", "text": f"KIKO: {final_text}"})

                                    await websocket.send_json({
                                        "event": "VOICE_RESPONSE",
                                        "text": f"KIKO: {final_text}" if final_text else "KIKO: Ready.",
                                        "status": "COMPLETED"
                                    })
                                    accumulated_pcm.clear()
                                    accumulated_text = ""

                    # Run bidirectional bridge concurrently
                    await asyncio.gather(handle_client_incoming(), handle_gemini_outgoing())
                    return
            except Exception as e:
                logger.error(f"[LIVE] Error in Gemini Live session bridge: {e}")

        # Fallback loop if Gemini Live session is not established
        logger.info("[LIVE] Using fallback local voice handling.")
        while True:
            data_str = await websocket.receive_text()
            data = json.loads(data_str)
            event_type = data.get("event")
            if event_type in ["VOICE_PROMPT", "TEXT_PROMPT"]:
                prompt = data.get("text", "").strip()
                if not prompt:
                    continue

                from app.ai.providers import get_ai_provider
                ai_prov = get_ai_provider()
                reply = await ai_prov.generate_response(prompt)
                
                # Speak response using TTS service
                await synthesize_speech_live(reply, play_on_host=True)

                await websocket.send_json({
                    "event": "VOICE_RESPONSE",
                    "text": f"KIKO: {reply}",
                    "status": "COMPLETED"
                })

    try:
        await run_live_bridge()
    except WebSocketDisconnect:
        logger.info("Client disconnected from Voice WebSocket.")
    except Exception as ex:
        logger.error(f"Voice bridge unhandled error: {ex}")
