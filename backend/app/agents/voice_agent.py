import abc
from typing import Dict, Any

class STTProvider(abc.ABC):
    @abc.abstractmethod
    async def transcribe_audio(self, audio_bytes: bytes) -> str:
        pass

class TTSProvider(abc.ABC):
    @abc.abstractmethod
    async def text_to_speech(self, text: str) -> bytes:
        pass

class MockVoiceProvider(STTProvider, TTSProvider):
    async def transcribe_audio(self, audio_bytes: bytes) -> str:
        return "Hey Kiko, open Chrome and search for AI news"

    async def text_to_speech(self, text: str) -> bytes:
        return b"MOCK_AUDIO_BYTES_KIKO_SPEECH"

class VoiceAssistant:
    def __init__(self, stt: STTProvider = None, tts: TTSProvider = None):
        self.stt = stt or MockVoiceProvider()
        self.tts = tts or MockVoiceProvider()
        self.wake_words = [
            "hey kiko", "kiko", "koko", "coco", "cico", "co", "ko", "ki", "eco", "echo",
            "keeko", "kiku", "kikoo", "ki ko", "hey echo", "hey eco", "hey coco"
        ]

    def is_wake_word(self, transcript: str) -> bool:
        lower = transcript.lower()
        return any(w in lower for w in self.wake_words)

voice_assistant = VoiceAssistant()
