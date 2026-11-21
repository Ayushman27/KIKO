import asyncio
import base64
import os
import sys

from app.services.gemini_live_voice import (
    synthesize_speech_live,
    transcribe_speech_multimodal,
    get_gemini_api_key,
    PRIMARY_LIVE_MODEL,
    AVAILABLE_VOICES,
    is_gemini_live_available,
)

async def main():
    print("=" * 60)
    print("KIKO GEMINI MULTIMODAL LIVE VOICE VERIFICATION")
    print("=" * 60)

    # 1. Check API Key
    api_key = get_gemini_api_key()
    print(f"[1] Gemini API Key present: {bool(api_key)}")
    print(f"    Available: {is_gemini_live_available()}")
    print(f"    Primary Live Model: {PRIMARY_LIVE_MODEL}")
    print(f"    Available Voices: {AVAILABLE_VOICES}")

    if not api_key:
        print("ERROR: No Gemini API Key configured in config_llm.json or env!")
        return

    # 2. Test Multimodal Live TTS
    test_phrase = "Hello Ayushman. Gemini Live speech synthesis and voice recognition are now fully operational."
    print(f"\n[2] Testing Multimodal Live TTS with phrase: \"{test_phrase}\"")
    tts_result = await synthesize_speech_live(
        text=test_phrase,
        voice="Puck",
        play_on_host=False
    )

    print(f"    TTS Status: {tts_result.get('status')}")
    print(f"    Voice: {tts_result.get('voice')}")
    print(f"    Sample Rate: {tts_result.get('sample_rate')} Hz")
    audio_b64 = tts_result.get("audio_base64", "")
    print(f"    Generated Audio (Base64) Length: {len(audio_b64)} chars")

    if not audio_b64:
        print("ERROR: TTS did not generate audio!")
        return

    wav_bytes = base64.b64decode(audio_b64)
    print(f"    Decoded WAV Audio Bytes: {len(wav_bytes)} bytes")

    # 3. Test Gemini Multimodal STT using generated audio
    print(f"\n[3] Testing Gemini Multimodal STT (transcribing generated audio)...")
    transcript = await transcribe_speech_multimodal(wav_bytes, mime_type="audio/wav")
    print(f"    STT Transcribed Output: \"{transcript}\"")

    if transcript:
        print("\n" + "=" * 60)
        print("SUCCESS: GEMINI MULTIMODAL LIVE TTS AND STT VERIFIED!")
        print("=" * 60)
    else:
        print("WARNING: STT returned empty transcription.")

if __name__ == "__main__":
    asyncio.run(main())
