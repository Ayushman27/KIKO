import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Desktop / Native Speech Recognition via Gemini Live API
http.Client? _activeSttClient;
bool _isSttActive = false;

void initWebSpeech(Function(String, bool) onSpeech, {double durationSeconds = 3.0}) async {
  if (_activeSttClient != null) {
    try {
      _activeSttClient?.close();
    } catch (_) {}
    _activeSttClient = null;
  }
  _isSttActive = true;
  _activeSttClient = http.Client();

  try {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/voice/record_and_transcribe');
    debugPrint('[STT] Mic activated. Listening for ${durationSeconds}s...');
    final resp = await _activeSttClient!.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'duration_seconds': durationSeconds}),
    ).timeout(Duration(seconds: (durationSeconds + 5.0).toInt()));

    if (!_isSttActive) {
      return;
    }

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final transcript = (data['transcript'] ?? '').toString().trim();
      debugPrint('[STT] Transcribed speech: "$transcript"');
      onSpeech(transcript, true);
    } else {
      onSpeech('', true);
    }
  } catch (e) {
    if (_isSttActive) {
      debugPrint('[STT] Error in speech recognition: $e');
      onSpeech('', true);
    }
  } finally {
    _activeSttClient?.close();
    _activeSttClient = null;
  }
}

void stopWebSpeech() {
  if (_isSttActive) {
    _isSttActive = false;
    try {
      _activeSttClient?.close();
    } catch (_) {}
    _activeSttClient = null;
    debugPrint('[STT] Microphone turned OFF.');
  }
}

/// Desktop / Native Text-To-Speech via Gemini Multimodal Live API
/// Returns duration of spoken audio in seconds so mic waits until speech ends!
Future<double> speakTextAloud(String text) async {
  try {
    final cleanText = text
        .replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), '')
        .replaceAll('KIKO:', '')
        .replaceAll(RegExp(r'[*_#`~>\[\]\(\)]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleanText.isEmpty) return 0.0;

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/voice/tts');
    debugPrint('[TTS] Synthesizing speech via Gemini Live: "$cleanText"');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': cleanText,
        'voice': 'Puck',
        'play_on_host': true,
      }),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final dur = (data['duration_seconds'] as num?)?.toDouble() ?? (cleanText.length / 14.0);
      return dur;
    }
  } catch (e) {
    debugPrint('[TTS] Error in TTS: $e');
  }
  return (text.length / 14.0);
}
