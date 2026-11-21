"""
Gemini Multimodal Live API Voice Engine
Implements real-time bidirectional Speech-to-Text (STT) and Text-to-Speech (TTS)
based on reference patterns from https://github.com/google-gemini/gemini-live-api-examples.
"""

import asyncio
import base64
import io
import json
import logging
import os
import re
import subprocess
import threading
import wave
from typing import Optional, Dict, Any, List

try:
    import numpy as np
except ImportError:
    np = None

try:
    import sounddevice as sd
except Exception:
    sd = None

try:
    from google import genai
    from google.genai import types
except ImportError:
    genai = None
    types = None

from app.core.config import settings
from app.api.settings import load_llm_config

logger = logging.getLogger("kiko.gemini_live")

# Models supporting bidiGenerateContent in Google Gemini Live API
PRIMARY_LIVE_MODEL = "models/gemini-2.5-flash-native-audio-latest"
FALLBACK_LIVE_MODEL = "models/gemini-3.8-live"
STT_MODELS = ["models/gemini-3.5-transcribe", "gemini-flash-latest", "gemini-3.8-flash"]

AVAILABLE_VOICES = ["Puck", "Charon", "Kore", "Fenrir", "Aoede"]


def sanitize_text_for_speech(text: str) -> str:
    """Removes emojis, agent labels, and markdown tags so TTS speaks clearly."""
    if not text:
        return ""
    # Strip agent/system prefixes
    clean = re.sub(r'^(?:KIKO|ASSISTANT|SYSTEM):\s*', '', text, flags=re.IGNORECASE)
    # Strip emojis (SMP unicode characters)
    clean = re.sub(r'[\U00010000-\U0010ffff]', '', clean)
    # Strip common markdown decorations
    clean = re.sub(r'[*_#`~>\[\]\(\)\{\}]', ' ', clean)
    # Collapse multiple whitespaces
    clean = re.sub(r'\s+', ' ', clean).strip()
    return clean


def safe_log_str(s: str) -> str:
    """ASCII safe string for Windows console logging avoiding cp1252 charmap errors."""
    return s.encode("ascii", "replace").decode("ascii")


def is_gemini_live_available() -> bool:
    return bool(get_gemini_api_key())


def get_gemini_api_key() -> str:
    cfg = load_llm_config()
    return cfg.get("gemini_api_key") or getattr(settings, "GEMINI_API_KEY", "") or os.getenv("GEMINI_API_KEY", "")


def get_genai_client(api_key: Optional[str] = None) -> genai.Client:
    key = api_key or get_gemini_api_key()
    if not key:
        raise ValueError("Gemini API key is not configured. Please add your key in Settings.")
    return genai.Client(api_key=key, http_options={"api_version": "v1alpha"})


def pcm_to_wav(pcm_bytes: bytes, sample_rate: int = 24000, channels: int = 1, sample_width: int = 2) -> bytes:
    """Wraps raw 16-bit linear PCM audio into a standard RIFF WAV container."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sample_width)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_bytes)
    return buf.getvalue()


_last_spoken_text = ""
_last_spoken_time = 0.0
_audio_finish_time = 0.0
_is_actively_speaking = False


def is_audio_playing() -> bool:
    """Returns True if KIKO is currently playing audio through the host speakers."""
    import time
    return _is_actively_speaking or (time.time() < _audio_finish_time)


def mark_audio_playing(duration_seconds: float):
    """Marks audio as currently playing for duration_seconds + 1.2s echo safety window."""
    global _audio_finish_time
    import time
    _audio_finish_time = max(_audio_finish_time, time.time() + duration_seconds + 1.2)


def is_self_echo(transcript: str, window_seconds: float = 14.0) -> bool:
    """
    Detects if the transcribed text is a repetition or fragment of KIKO's own recently spoken text.
    Guarantees the microphone NEVER feeds KIKO's own speech back into the cognitive engine.
    """
    global _last_spoken_text, _last_spoken_time
    import time, re
    if not transcript or not _last_spoken_text:
        return False
    if (time.time() - _last_spoken_time) > window_seconds:
        return False

    def normalize(s: str) -> str:
        return re.sub(r'[^a-z0-9 ]', '', s.lower()).strip()

    t_norm = normalize(transcript)
    l_norm = normalize(_last_spoken_text)

    if not t_norm or not l_norm:
        return False

    # 1. Exact match
    if t_norm == l_norm:
        logger.warning(f"[ECHO-SUPPRESSION] Blocked exact self-echo: '{t_norm}'")
        return True

    # 2. Substring match
    if t_norm in l_norm or l_norm in t_norm:
        logger.warning(f"[ECHO-SUPPRESSION] Blocked substring self-echo: '{t_norm}' vs '{l_norm}'")
        return True

    # 3. High word overlap
    t_words = set(t_norm.split())
    l_words = set(l_norm.split())
    if len(t_words) >= 3:
        overlap = len(t_words.intersection(l_words)) / len(t_words)
        if overlap >= 0.65:
            logger.warning(f"[ECHO-SUPPRESSION] Blocked high-overlap self-echo ({overlap*100:.0f}%): '{t_norm}'")
            return True

    return False


def is_audio_silent(pcm_bytes: bytes, threshold: float = 8.0) -> bool:
    """Checks whether the raw 16-bit mono PCM audio contains spoken voice or just silence/background."""
    if not pcm_bytes:
        return True
    try:
        if np is not None:
            data = np.frombuffer(pcm_bytes, dtype=np.int16)
            if len(data) == 0:
                return True
            rms = float(np.sqrt(np.mean(data.astype(np.float32) ** 2)))
            return rms < threshold
    except Exception:
        pass
    return False


def should_skip_duplicate_speech(text: str, window_seconds: float = 4.0) -> bool:
    """Returns True if identical speech playback was requested within window_seconds."""
    global _last_spoken_text, _last_spoken_time
    import time
    now = time.time()
    clean = sanitize_text_for_speech(text).lower()
    if clean and clean == _last_spoken_text and (now - _last_spoken_time) < window_seconds:
        logger.info(f"[TTS] Suppressed duplicate speech playback within {window_seconds}s: '{safe_log_str(clean)}'")
        return True
    _last_spoken_text = clean
    _last_spoken_time = now
    return False


def play_audio_async(pcm_or_wav_bytes: bytes, sample_rate: int = 24000, is_wav: bool = False, text_cue: str = ""):
    """
    Plays audio on the host PC audio output devices.
    On Windows, uses a daemon thread with winsound.PlaySound to guarantee
    flawless playback through the active Windows Default Audio Device (Echo Dot, Bluetooth, Realtek).
    Also supports sounddevice.
    """
    if text_cue and should_skip_duplicate_speech(text_cue):
        return

    try:
        wav_bytes = pcm_or_wav_bytes if is_wav else pcm_to_wav(pcm_or_wav_bytes, sample_rate=sample_rate)
        audio_dur = len(wav_bytes) / (sample_rate * 2.0)
        mark_audio_playing(audio_dur)

        # 1. On Windows, try winsound in background daemon thread
        if os.name == "nt":
            def _winsound_runner(data: bytes):
                global _is_actively_speaking, _audio_finish_time
                import time
                _is_actively_speaking = True
                _audio_finish_time = time.time() + audio_dur + 5.0
                try:
                    import winsound
                    winsound.PlaySound(data, winsound.SND_MEMORY)
                except Exception as ex:
                    logger.debug(f"[AUDIO] winsound playback error: {ex}")
                finally:
                    _is_actively_speaking = False
                    _audio_finish_time = time.time() + 1.2

            threading.Thread(target=_winsound_runner, args=(wav_bytes,), daemon=True).start()
            logger.info(f"[AUDIO] Dispatched {len(wav_bytes)} bytes audio ({audio_dur:.1f}s) to Windows sound output.")
            return

        # 2. Non-Windows or fallback: sounddevice
        if sd is not None and np is not None:
            raw_pcm = pcm_or_wav_bytes if not is_wav else wav_bytes[44:]
            audio_array = np.frombuffer(raw_pcm, dtype=np.int16)
            sd.play(audio_array, samplerate=sample_rate)
            logger.info(f"[AUDIO] Dispatched audio to sounddevice.")
    except Exception as e:
        logger.warning(f"[AUDIO] Host audio playback error: {e}")


def fallback_windows_sapi(text: str):
    """Fallback TTS using Windows Speech Synthesis (SAPI) when offline or no API key."""
    if should_skip_duplicate_speech(text):
        return
    try:
        clean = sanitize_text_for_speech(text)
        clean = clean.replace('"', '').replace("'", "").replace("\n", " ").strip()
        if not clean:
            return
        est_dur = max(2.0, len(clean) / 14.0)
        mark_audio_playing(est_dur)

        def _sapi_runner():
            global _is_actively_speaking, _audio_finish_time
            import subprocess, time
            _is_actively_speaking = True
            _audio_finish_time = time.time() + est_dur + 5.0
            try:
                cmd = f"Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{clean}')"
                proc = subprocess.Popen(["powershell", "-NoProfile", "-Command", cmd], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                proc.wait()
            finally:
                _is_actively_speaking = False
                _audio_finish_time = time.time() + 1.2

        threading.Thread(target=_sapi_runner, daemon=True).start()
        logger.info(f"[TTS-SAPI] Spoke via Windows SAPI: '{safe_log_str(clean)}'")
    except Exception as ex:
        logger.error(f"[TTS-SAPI] Error invoking Windows SAPI: {ex}")


async def synthesize_speech_live(
    text: str,
    voice: str = "Puck",
    play_on_host: bool = True,
    system_instruction: str = "You are KIKO. Speak naturally, warmly, and concisely."
) -> Dict[str, Any]:
    """
    Synthesize natural speech audio using Gemini Multimodal Live API.
    Returns base64 WAV, sample rate, transcript, and plays on host PC.
    """
    clean_text = sanitize_text_for_speech(text)
    if not clean_text:
        return {"status": "EMPTY", "audio_base64": "", "text": ""}

    api_key = get_gemini_api_key()
    if not api_key:
        logger.warning("[TTS] No Gemini API key found, using Windows SAPI fallback.")
        if play_on_host:
            fallback_windows_sapi(clean_text)
        return {
            "status": "FALLBACK_SAPI",
            "audio_base64": "",
            "text": clean_text,
            "sample_rate": 24000,
            "voice": "SAPI"
        }

    client = get_genai_client(api_key)
    voice_name = voice if voice in AVAILABLE_VOICES else "Puck"

    config = types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        speech_config=types.SpeechConfig(
            voice_config=types.VoiceConfig(
                prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=voice_name)
            )
        ),
        thinking_config=types.ThinkingConfig(thinking_budget=0),
        output_audio_transcription=types.AudioTranscriptionConfig(),
        system_instruction=types.Content(
            parts=[types.Part.from_text(text=system_instruction)]
        )
    )

    audio_chunks: List[bytes] = []
    output_transcription = ""

    # Attempt connection with primary live model, fallback if needed
    for model_name in [PRIMARY_LIVE_MODEL, FALLBACK_LIVE_MODEL]:
        try:
            async with client.aio.live.connect(model=model_name, config=config) as session:
                await session.send_client_content(
                    turns=[types.Content(role="user", parts=[types.Part.from_text(text=f"Say: {clean_text}")])],
                    turn_complete=True
                )

                async for resp in session.receive():
                    if resp.server_content:
                        d = resp.model_dump(exclude_none=True)
                        sc = d.get("server_content", {})
                        if "output_transcription" in sc:
                            ot = sc["output_transcription"]
                            if isinstance(ot, dict) and "text" in ot:
                                output_transcription += ot["text"]
                        if resp.server_content.model_turn:
                            for part in resp.server_content.model_turn.parts:
                                if part.inline_data and part.inline_data.data:
                                    audio_chunks.append(part.inline_data.data)
                        if resp.server_content.turn_complete:
                            break
            break
        except Exception as e:
            logger.warning(f"[TTS] Connection error with model '{model_name}': {e}")
            audio_chunks.clear()

    if not audio_chunks:
        logger.warning("[TTS] Gemini Live generated no audio chunks, falling back to SAPI.")
        if play_on_host:
            fallback_windows_sapi(clean_text)
        dur = max(2.0, len(clean_text) / 14.0)
        return {
            "status": "FALLBACK_SAPI",
            "audio_base64": "",
            "text": clean_text,
            "sample_rate": 24000,
            "voice": "SAPI",
            "duration_seconds": dur
        }

    raw_pcm = b"".join(audio_chunks)
    wav_bytes = pcm_to_wav(raw_pcm, sample_rate=24000)
    audio_b64 = base64.b64encode(wav_bytes).decode("ascii")
    dur_sec = len(raw_pcm) / (24000 * 2.0)

    if play_on_host:
        play_audio_async(raw_pcm, sample_rate=24000, is_wav=False, text_cue=clean_text)

    final_text = output_transcription.strip() or clean_text
    logger.info(f"[TTS] Gemini Live generated {len(wav_bytes)} bytes audio ({voice_name}, {dur_sec:.1f}s). Transcript: '{safe_log_str(final_text)}'")

    return {
        "status": "SUCCESS",
        "audio_base64": audio_b64,
        "mime_type": "audio/wav",
        "sample_rate": 24000,
        "text": final_text,
        "voice": voice_name,
        "duration_seconds": dur_sec
    }


def _sync_google_stt(audio_bytes: bytes) -> str:
    try:
        import speech_recognition as sr
        r = sr.Recognizer()
        r.energy_threshold = 300
        with io.BytesIO(audio_bytes) as audio_file:
            with sr.AudioFile(audio_file) as source:
                recorded_audio = r.record(source)
        return (r.recognize_google(recorded_audio) or "").strip()
    except sr.UnknownValueError:
        return ""
    except Exception as ex:
        logger.debug(f"[STT] Primary recognizer error: {ex}")
        return ""


async def transcribe_speech_multimodal(audio_bytes: bytes, mime_type: str = "audio/wav") -> str:
    """
    Transcribes audio bytes into high-accuracy text using Google Speech Recognition
    with fallback to Gemini Multimodal STT models.
    Filters out any self-echo from KIKO's own speaker output.
    """
    if not audio_bytes or len(audio_bytes) < 1000:
        return ""

    # Instant silence detection: returns empty immediately without network overhead
    raw_pcm = audio_bytes[44:] if len(audio_bytes) > 44 else audio_bytes
    if is_audio_silent(raw_pcm, threshold=8.0):
        return ""

    # 1. Fast, non-blocking Google Speech Recognition in worker thread
    recognized = await asyncio.to_thread(_sync_google_stt, audio_bytes)
    if recognized:
        if is_self_echo(recognized):
            logger.warning(f"[STT] Discarded transcription '{recognized}' because it matches KIKO's own recent output.")
            return ""
        logger.info(f"[STT] Transcribed via Google Speech Engine: '{recognized}'")
        return recognized

    # 2. Only if recognizer had a connection issue, try Gemini with 5s timeout
    api_key = get_gemini_api_key()
    if api_key:
        try:
            client = get_genai_client(api_key)
            resp = await asyncio.wait_for(
                client.aio.models.generate_content(
                    model="models/gemini-3.5-flash-lite",
                    contents=[
                        types.Part.from_bytes(data=audio_bytes, mime_type=mime_type),
                        "Transcribe the spoken voice in this audio. Output ONLY the words spoken. If silent, return empty."
                    ]
                ),
                timeout=5.0
            )
            text = (resp.text or "").strip()
            if text and text.lower() not in ["silence", "silent", "none"]:
                if is_self_echo(text):
                    logger.warning(f"[STT] Discarded Gemini transcription '{text}' because it matches KIKO's own recent output.")
                    return ""
                return text
        except Exception:
            pass

    return ""


def record_host_microphone(duration_seconds: float = 3.0, sample_rate: int = 16000) -> bytes:
    """
    Records audio synchronously from the host PC microphone using sounddevice.
    Returns 16kHz 16-bit mono WAV bytes.
    Guarantees recording does NOT begin until KIKO has completely stopped speaking!
    """
    import time
    wait_start = time.time()
    while is_audio_playing() and (time.time() - wait_start < 10.0):
        time.sleep(0.15)

    if sd is None or np is None:
        raise RuntimeError("sounddevice/numpy are not available in the active Python environment.")
    num_frames = int(duration_seconds * sample_rate)
    logger.info(f"[MIC] Recording {duration_seconds}s at {sample_rate}Hz from default microphone...")
    recorded = sd.rec(num_frames, samplerate=sample_rate, channels=1, dtype=np.int16)
    sd.wait()
    raw_pcm = recorded.tobytes()
    return pcm_to_wav(raw_pcm, sample_rate=sample_rate, channels=1, sample_width=2)
