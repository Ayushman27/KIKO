import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../config/app_settings.dart';
import '../../services/websocket_service.dart';
import 'synapse_theme.dart';
import 'atmospheric_background.dart';
import 'synapse_header_bar.dart';
import 'holographic_dotted_face_orb.dart';
import 'cognition_metrics_card.dart';
import 'kinetic_dialogue_stage.dart';
import 'synapse_command_deck.dart';
import '../../utils/web_speech.dart' as web_speech;

/// Wake Word Detection Result Container for Synapse
class SynapseWakeWordResult {
  final bool isDetected;
  final String candidate;
  final double similarity;
  final String remainingCommand;

  const SynapseWakeWordResult({
    required this.isDetected,
    required this.candidate,
    required this.similarity,
    required this.remainingCommand,
  });
}

/// Complete Synapse Dual-Mode Animated AI Interface
/// Direct implementation of stitch_dual_mode_animated_ai_interface.
/// Responsive across both Windows Desktop and Phone App!
class SynapseDualModeScreen extends StatefulWidget {
  final bool isDesktop;
  final VoidCallback? onOpenDrawer;

  const SynapseDualModeScreen({
    super.key,
    this.isDesktop = false,
    this.onOpenDrawer,
  });

  @override
  State<SynapseDualModeScreen> createState() => _SynapseDualModeScreenState();
}

class _SynapseDualModeScreenState extends State<SynapseDualModeScreen> {
  final TextEditingController _promptController = TextEditingController();

  // Mode texts from the design system
  static const String _alphaText =
      "I have initialized neural pathway synthesis across your cognitive nodes. In Alpha Mode, throughput is tuned for deep analytical precision. Ready to activate G-mode whenever overclocked latency is required.";

  static const String _gModeText =
      "G-MODE OVERDRIVE ENGAGED. Thermal headroom unlocked. Realtime clock throttled to 14ms response rate with maximum creative velocity. Direct synthetic cortex link established.";

  String _currentDialogueText = "";
  String _targetDialogueText = _alphaText;
  Timer? _typewriterTimer;
  int _charIndex = 0;

  bool _isSpeaking = true;
  bool _isStreaming = false;
  bool _isAudioEngaged = true;
  bool _isListeningWakeWord = false; // Quietly listening in background for "Kiko" (button stays calm!)
  bool _isRecordingCommand = false; // Actively recording user instruction (button turns RED REC!)
  bool _isAutoMicEnabled = true; // Auto Wake-word standby mode
  bool _isProcessingPrompt = false;
  bool _isHandlingSynthesize = false;
  String _lastSpokenAssistantText = "";
  Timer? _autoMicLoopTimer;
  Timer? _micWatchdogTimer;
  late Function(Map<String, dynamic>) _wsListener;

  // Cognitive Thread live task tracking
  String _activeTaskName = "";
  CognitionTaskStatus _activeTaskStatus = CognitionTaskStatus.idle;
  String _taskStatusMessage = "";
  String _activeTaskId = "PID #904-SYN";
  String? _browserCurrentUrl;
  String? _browserScreenshotB64;
  List<String> _browserSources = [];
  String? _realBackendTaskId;

  // Wake-word configurations
  static const String CONFIG_PRIMARY_WAKE_WORD = "kiko";
  static const Set<String> WAKE_WORD_ALIASES = {
    // Exact user requested variations
    "kiko", "koko", "coco", "cico", "co", "ko", "ki", "eco", "echo",
    // Common phonetics & STT transcriptions
    "kiku", "keko", "keeko", "kico", "kikoo", "keyko", "kyko", "qiko", "quico",
    "kik", "kica", "kika", "koka", "coka", "cuco", "cuca", "kikou", "kicoo",
    "eko", "ekko", "ecko", "ecco", "heko", "heiko", "chiko", "chico", "cheeko", "chiku",
    "geeko", "geko", "giko", "tiko", "pico", "peko", "miko", "niko", "neeko",
    "kayko", "kayco", "keeco", "kaco", "keico", "ceco", "kio", "queco",
    "cocoo", "kokoo", "cicoo", "feko", "feki", "fecko", "keik", "keikoo"
  };

  static const List<String> MULTI_WORD_WAKE_PHRASES = [
    "feki ko",
    "fe ki ko",
    "fe ki",
    "ki ko",
    "ki co",
    "key ko",
    "kee ko",
    "co co",
    "ko ko",
    "k ko",
    "k co",
    "hey kiko",
    "hey echo",
    "hey eco",
    "hey coco",
    "hey koko",
    "hi kiko",
    "hi echo",
    "hi eco",
    "hi coco",
    "hi koko",
    "ok kiko",
    "ok echo",
    "ok eco",
    "ok coco",
    "ok koko",
    "hello kiko",
    "hello echo",
    "hello eco",
  ];

  static const List<String> REFERENCE_WAKE_WORDS = [
    "kiko", "koko", "coco", "cico", "echo", "eco", "keeko", "kiku"
  ];

  SynapseWakeWordResult _analyzeWakeWord(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) {
      return const SynapseWakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
    }

    final lower = text.toLowerCase();
    final cleanLower = lower.replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanLower.isEmpty) {
      return const SynapseWakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
    }

    // ── Phase 1: Check multi-word wake phrases (e.g. "ki ko", "feki ko", "hey kiko") ──
    for (final phrase in MULTI_WORD_WAKE_PHRASES) {
      if (cleanLower == phrase) {
        return SynapseWakeWordResult(
          isDetected: true,
          candidate: phrase,
          similarity: 1.0,
          remainingCommand: "",
        );
      }
      if (cleanLower.startsWith("$phrase ")) {
        final remaining = cleanLower.substring(phrase.length).trim();
        return SynapseWakeWordResult(
          isDetected: true,
          candidate: phrase,
          similarity: 1.0,
          remainingCommand: remaining,
        );
      }
      final phraseIdx = cleanLower.indexOf(phrase);
      if (phraseIdx != -1) {
        final before = cleanLower.substring(0, phraseIdx).trim();
        final after = cleanLower.substring(phraseIdx + phrase.length).trim();
        final remaining = after.isNotEmpty ? after : before;
        return SynapseWakeWordResult(
          isDetected: true,
          candidate: phrase,
          similarity: 0.95,
          remainingCommand: remaining,
        );
      }
    }

    // ── Phase 2: Word-by-word & 2-word analysis ──
    final words = cleanLower.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return const SynapseWakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
    }

    // Check 2-word combinations joined together (e.g. "ki" + "ko" -> "kiko", "co" + "co" -> "coco")
    for (int i = 0; i < words.length - 1; i++) {
      final joined = words[i] + words[i + 1];
      if (WAKE_WORD_ALIASES.contains(joined)) {
        final remaining = _extractCommandAroundIndex(words, i, 2);
        return SynapseWakeWordResult(
          isDetected: true,
          candidate: "${words[i]} ${words[i + 1]}",
          similarity: 0.98,
          remainingCommand: remaining,
        );
      }
    }

    // Check individual words
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      bool isMatch = false;
      double similarity = 0.0;
      String matchedCandidate = word;

      // 1. Exact alias match (kiko, koko, coco, cico, co, ko, ki, eco, echo, etc.)
      if (WAKE_WORD_ALIASES.contains(word)) {
        isMatch = true;
        similarity = 1.0;
        matchedCandidate = word;
      }

      // 2. Starts-with prefix match for core sounds (kiko..., coco..., koko..., echo..., eco...)
      if (!isMatch) {
        for (final pref in ["kiko", "coco", "koko", "cico", "echo", "eco", "keek"]) {
          if (word.startsWith(pref)) {
            isMatch = true;
            similarity = 0.95;
            matchedCandidate = word;
            break;
          }
        }
      }

      // 3. Levenshtein edit distance <= 1 against reference wake words
      if (!isMatch && word.length >= 3) {
        for (final ref in REFERENCE_WAKE_WORDS) {
          final dist = _levenshtein(word, ref);
          if (dist <= 1) {
            isMatch = true;
            similarity = 1.0 - (dist / ref.length);
            matchedCandidate = word;
            break;
          }
        }
      }

      if (isMatch) {
        final remaining = _extractCommandAroundIndex(words, i, 1);
        return SynapseWakeWordResult(
          isDetected: true,
          candidate: matchedCandidate,
          similarity: similarity,
          remainingCommand: remaining,
        );
      }
    }

    return const SynapseWakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
  }

  String _extractCommandAroundIndex(List<String> words, int matchedIndex, int matchedLength) {
    if (matchedIndex + matchedLength < words.length) {
      final afterWords = words.sublist(matchedIndex + matchedLength);
      final cmd = afterWords.join(' ').trim();
      if (cmd.isNotEmpty) return cmd;
    }
    if (matchedIndex > 0) {
      final beforeWords = words.sublist(0, matchedIndex);
      final cmd = beforeWords.join(' ').trim();
      if (cmd.isNotEmpty) return cmd;
    }
    return "";
  }

  int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<List<int>> matrix = List.generate(
      s1.length + 1,
      (i) => List.filled(s2.length + 1, 0),
    );

    for (int i = 0; i <= s1.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= s2.length; j++) matrix[0][j] = j;

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((min, val) => val < min ? val : min);
      }
    }
    return matrix[s1.length][s2.length];
  }

  bool _isEchoOfAssistant(String transcript, String assistantText) {
    if (transcript.isEmpty || assistantText.isEmpty) return false;
    final tClean = transcript.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
    final aClean = assistantText.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
    if (tClean.isEmpty || aClean.isEmpty) return false;
    if (tClean == aClean) return true;
    if (tClean.length >= 6 && aClean.contains(tClean)) return true;
    if (aClean.length >= 6 && tClean.contains(aClean)) return true;
    final tWords = tClean.split(' ').where((w) => w.length > 2).toSet();
    final aWords = aClean.split(' ').where((w) => w.length > 2).toSet();
    if (tWords.length >= 2) {
      final matchCount = tWords.intersection(aWords).length;
      if (matchCount / tWords.length >= 0.6) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _wsListener = _handleWsMessage;
    WebSocketService.instance.addListener(_wsListener);

    // Initial typewriter stream
    final initialGMode = AppSettings.instance.isGMode;
    _targetDialogueText = initialGMode ? _gModeText : _alphaText;
    _streamTypewriterText(_targetDialogueText);

    // After initial intro text appears, turn on the mic automatically (Google Assistant style)
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        setState(() => _isSpeaking = false);
        if (_isAutoMicEnabled) {
          _turnOnMic();
        }
      }
    });

    // Mic watchdog: keeps the microphone ALWAYS ON in standby if idle
    _micWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (_isAutoMicEnabled &&
          !_isSpeaking &&
          !_isProcessingPrompt &&
          !_isRecordingCommand &&
          !_isListeningWakeWord) {
        debugPrint('[WATCHDOG] Standby wake-word listening idle. Resuming continuous standby...');
        _startWakeWordListening();
      }
    });
  }

  @override
  void dispose() {
    _turnOffMic(reason: 'Screen disposed');
    _micWatchdogTimer?.cancel();
    _typewriterTimer?.cancel();
    WebSocketService.instance.removeListener(_wsListener);
    _promptController.dispose();
    super.dispose();
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final event = msg['event'] ?? '';
    final message = msg['message'] ?? '';

    if (msg['current_url'] != null) {
      _browserCurrentUrl = msg['current_url'];
    }
    if (msg['sources'] != null && msg['sources'] is List) {
      _browserSources = List<String>.from(msg['sources']);
    }
    if (msg['screenshot_b64'] != null) {
      _browserScreenshotB64 = msg['screenshot_b64'];
    }
    if (msg['task_id'] != null) {
      _realBackendTaskId = msg['task_id'].toString();
    }

    if (message.isNotEmpty &&
        ['TASK_PROGRESS', 'TASK_COMPLETED', 'TASK_FAILED', 'AGENT_RESPONSE', 'VOICE_TRANSCRIPT']
            .contains(event)) {
      if (event == 'TASK_PROGRESS') {
        setState(() {
          _activeTaskStatus = CognitionTaskStatus.executing;
          _taskStatusMessage = message;
        });
      } else if (event == 'TASK_COMPLETED') {
        setState(() {
          _activeTaskStatus = CognitionTaskStatus.completed;
          _taskStatusMessage = message;
        });
      } else if (event == 'TASK_FAILED') {
        setState(() {
          _activeTaskStatus = CognitionTaskStatus.failed;
          _taskStatusMessage = message;
        });
      }

      if (event == 'AGENT_RESPONSE' || event == 'TASK_COMPLETED') {
        // Only speak if this wasn't already handled by _handleSynthesize to prevent duplicate responses
        if (!_isHandlingSynthesize &&
            !_isProcessingPrompt &&
            !_isSpeaking &&
            _lastSpokenAssistantText != message) {
          _lastSpokenAssistantText = message;
          _agentSpeakOutput(message, autoRecordFollowUp: true);
        }
      } else {
        _streamTypewriterText(message);
      }
    }
  }

  Future<void> _stopActiveTask() async {
    final tid = _realBackendTaskId;
    if (tid != null && tid.isNotEmpty) {
      try {
        await http.post(Uri.parse('${ApiConfig.baseUrl}/api/v1/tasks/$tid/cancel'));
      } catch (e) {
        debugPrint('[TASK STOP] Error cancelling task: $e');
      }
    }
    setState(() {
      _activeTaskStatus = CognitionTaskStatus.failed;
      _taskStatusMessage = 'Task stopped by user.';
    });
    _streamTypewriterText('Task stopped by user.');
  }

  /// Turn OFF microphone (used whenever agent is speaking or thinking)
  void _turnOffMic({String reason = ''}) {
    _autoMicLoopTimer?.cancel();
    web_speech.stopWebSpeech();
    if (mounted) {
      setState(() {
        _isListeningWakeWord = false;
        _isRecordingCommand = false;
      });
    }
    if (reason.isNotEmpty) {
      debugPrint('[MIC-CTRL] Mic TURNED OFF: $reason');
    }
  }

  /// Turn ON wake-word standby listening
  void _turnOnMic() {
    _autoMicLoopTimer?.cancel();
    if (!mounted || !_isAutoMicEnabled || _isSpeaking || _isProcessingPrompt || _isRecordingCommand) {
      return;
    }
    debugPrint('[MIC-CTRL] Wake-Word Standby ON — Waiting for "Kiko"');
    _startWakeWordListening();
  }

  void _scheduleNextWakeWordCheck({int delayMs = 0}) {
    _autoMicLoopTimer?.cancel();
    if (!mounted || !_isAutoMicEnabled) return;

    if (delayMs <= 0) {
      if (_isSpeaking || _isProcessingPrompt || _isRecordingCommand) {
        // If busy, schedule a retry check instead of discarding the loop
        _autoMicLoopTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted && _isAutoMicEnabled) {
            _scheduleNextWakeWordCheck(delayMs: 0);
          }
        });
        return;
      }
      _startWakeWordListening();
    } else {
      _autoMicLoopTimer = Timer(Duration(milliseconds: delayMs), () {
        if (!mounted || !_isAutoMicEnabled) return;
        if (_isSpeaking || _isProcessingPrompt || _isRecordingCommand) {
          _scheduleNextWakeWordCheck(delayMs: 200);
          return;
        }
        _startWakeWordListening();
      });
    }
  }

  void _toggleAutoMic() {
    setState(() {
      _isAutoMicEnabled = !_isAutoMicEnabled;
    });
    if (_isAutoMicEnabled) {
      _streamTypewriterText("🎙️ Wake-Word standby active. Say \"Kiko\" anytime to issue a command.");
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !_isSpeaking && !_isProcessingPrompt && !_isRecordingCommand) {
          _turnOnMic();
        }
      });
    } else {
      _turnOffMic(reason: 'Wake-word standby disabled by user');
      _streamTypewriterText("⏸️ Wake-Word standby paused. Switched to manual Push-to-Talk mode.");
    }
  }

  /// Complete Agent Output Cycle:
  /// 1. Turns OFF mic immediately while agent is speaking
  /// 2. Speaks the output aloud (TTS)
  /// 3. After completion of task, automatically goes into RECORDING MODE for follow-up!
  /// 4. If no voice input is coming, turns OFF recording without sending output.
  Future<void> _agentSpeakOutput(String text, {bool autoRecordFollowUp = true}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    // 1. Turn OFF mic while agent is speaking
    _turnOffMic(reason: 'Agent speaking output');

    setState(() {
      _isSpeaking = true;
    });

    // 2. Stream typewriter text
    _streamTypewriterText(cleanText);

    // 3. Play voice aloud if audio is engaged
    if (_isAudioEngaged) {
      final audioDuration = await web_speech.speakTextAloud(cleanText);
      final waitDurationMs = ((audioDuration + 0.35) * 1000).toInt();
      debugPrint('[VOICE-CYCLE] Agent speaking for ${audioDuration.toStringAsFixed(1)}s. Mic will remain OFF for ${waitDurationMs}ms');
      await Future.delayed(Duration(milliseconds: waitDurationMs));
    } else {
      await Future.delayed(const Duration(milliseconds: 600));
    }

    // 4. Finished speaking & task complete!
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _isProcessingPrompt = false;
      });
      if (_isAutoMicEnabled) {
        if (autoRecordFollowUp) {
          debugPrint('[VOICE-CYCLE] Task completed. Automatically opening mic in RECORDING MODE for follow-up instruction...');
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted && !_isSpeaking) {
              _startCommandRecording(isFollowUp: true);
            }
          });
        } else {
          debugPrint('[VOICE-CYCLE] Speech finished. Resuming Wake-Word Standby.');
          _scheduleNextWakeWordCheck(delayMs: 350);
        }
      }
    }
  }

  void _streamTypewriterText(String fullText) {
    _typewriterTimer?.cancel();
    _currentDialogueText = "";
    _charIndex = 0;
    _targetDialogueText = fullText;
    setState(() {
      _isStreaming = true;
    });

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (_charIndex < fullText.length) {
        setState(() {
          _currentDialogueText += fullText[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
        setState(() => _isStreaming = false);
      }
    });
  }

  Future<void> _handleSynthesize(String prompt) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) return;

    _isHandlingSynthesize = true;

    // Immediately TURN OFF mic while processing prompt
    _turnOffMic(reason: 'User prompt submitted, processing');

    setState(() {
      _isProcessingPrompt = true;
      _activeTaskName = cleanPrompt;
      _activeTaskStatus = CognitionTaskStatus.executing;
      _taskStatusMessage = 'Dispatched to Windows PC • Executing in real-time...';
      _activeTaskId = 'PID #${(100 + (cleanPrompt.hashCode.abs() % 900))}-SYN';
    });

    final settings = AppSettings.instance;
    final isGMode = settings.isGMode;

    _streamTypewriterText(
      isGMode
          ? '⚡ G-Mode overdrive engaged. Synthesizing: "$cleanPrompt"...'
          : 'Thinking...',
    );

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'description': cleanPrompt,
          'prompt': cleanPrompt,
          'command': cleanPrompt,
          'origin_device': 'WINDOWS_DESKTOP',
          'mode': isGMode ? 'g_mode' : 'alpha',
        }),
      ).timeout(const Duration(seconds: 90));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final responseText = data['response'] ?? data['message'] ?? 'Task completed.';
        _lastSpokenAssistantText = responseText;

        if (mounted) {
          setState(() {
            _isProcessingPrompt = false;
            _activeTaskStatus = CognitionTaskStatus.completed;
            _taskStatusMessage = responseText;
          });
        }
        
        // Agent speaks output (Mic stays OFF while speaking, then enters recording mode for follow-up)
        await _agentSpeakOutput(responseText, autoRecordFollowUp: true);
      } else {
        if (mounted) {
          setState(() {
            _isProcessingPrompt = false;
            _activeTaskStatus = CognitionTaskStatus.failed;
            _taskStatusMessage = 'Server returned HTTP ${res.statusCode}';
          });
        }
        await _agentSpeakOutput('Server returned HTTP ${res.statusCode}.', autoRecordFollowUp: false);
      }
    } catch (e) {
      String errMsg = 'Connection error: $e';
      if (ApiConfig.baseUrl.contains('127.0.0.1') && !widget.isDesktop) {
        errMsg = '⚠️ Cannot reach backend at 127.0.0.1:8000.\n\nPlease open the Settings tab and set the Backend Server URL to your PC\'s Wi-Fi IP (e.g. http://192.168.1.11:8000), and make sure the KIKO backend server is running on your PC.';
      }
      if (mounted) {
        setState(() {
          _isProcessingPrompt = false;
          _activeTaskStatus = CognitionTaskStatus.failed;
          _taskStatusMessage = errMsg;
        });
      }
      await _agentSpeakOutput(errMsg);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPrompt = false;
        });
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _isHandlingSynthesize = false;
        });
      }
    }
  }

  /// Background Wake-Word Listener:
  /// Continuously listens for "Kiko" (or aliases) in short chunks.
  /// Continuous Wake-Word Standby:
  /// Keeps the microphone ALWAYS ON in 3.0s continuous chunks with 0ms gap.
  /// If silence or ambient sound occurs without wake word ("Kiko"), the microphone
  /// remains seamlessly active without turning off or stuttering.
  void _startWakeWordListening() {
    if (_isRecordingCommand || _isProcessingPrompt || _isSpeaking) return;
    if (!mounted || !_isAutoMicEnabled) return;

    if (!_isListeningWakeWord) {
      setState(() {
        _isListeningWakeWord = true;
        _isRecordingCommand = false;
      });
    }

    web_speech.initWebSpeech((transcript, isFinal) {
      if (!mounted) return;

      final cleanTranscript = transcript.trim();
      if (cleanTranscript.isEmpty) {
        // Silence: keep mic seamlessly active for the next 3.0s chunk (0ms gap)
        if (_isAutoMicEnabled && mounted && !_isSpeaking && !_isProcessingPrompt && !_isRecordingCommand) {
          _scheduleNextWakeWordCheck(delayMs: 0);
        }
        return;
      }

      // Analyze transcript for Wake Word "Kiko" and phonetic sound-alikes
      final wakeResult = _analyzeWakeWord(cleanTranscript);

      // Check echo of agent's own speech ONLY if it's NOT a wake word
      if (!wakeResult.isDetected && _isEchoOfAssistant(cleanTranscript, _lastSpokenAssistantText)) {
        debugPrint('[WAKE-WORD] Filtered assistant echo: "$cleanTranscript"');
        if (_isAutoMicEnabled && mounted && !_isSpeaking && !_isProcessingPrompt && !_isRecordingCommand) {
          _scheduleNextWakeWordCheck(delayMs: 0);
        }
        return;
      }

      if (!wakeResult.isDetected) {
        // Ambient noise without wake word (e.g. background voices, "pankha")
        debugPrint('[WAKE-WORD] Ambient sound ignored (no wake word match): "$cleanTranscript"');
        // Keep microphone seamlessly active with 0ms gap!
        if (_isAutoMicEnabled && mounted && !_isSpeaking && !_isProcessingPrompt && !_isRecordingCommand) {
          _scheduleNextWakeWordCheck(delayMs: 0);
        }
        return;
      }

      // WAKE WORD DETECTED!
      debugPrint('[WAKE-WORD] ✅ WAKE WORD ACCEPTED: "${wakeResult.candidate}" (similarity: ${wakeResult.similarity.toStringAsFixed(2)})');
      _turnOffMic(reason: 'Wake word detected: ${wakeResult.candidate}');

      final command = wakeResult.remainingCommand.trim();
      if (command.isNotEmpty && command.length > 1) {
        // User spoke instruction in the same breath (e.g. "Kiko what is the weather today")
        debugPrint('[WAKE-WORD] Inline command found: "$command"');
        _promptController.text = command;
        _handleSynthesize(command);
      } else {
        // Standalone wake word "Kiko" -> Kiko responds "Yes? I am listening." and records user's instruction
        debugPrint('[WAKE-WORD] Standalone wake word. Acknowledging and opening mic for instruction...');
        _promptForInstructionAfterWake();
      }
    }, durationSeconds: 3.0);
  }

  /// Standalone Wake-word acknowledgment ("Yes? I am listening.") followed by active command recording
  Future<void> _promptForInstructionAfterWake() async {
    const ackText = "Yes? I'm listening.";
    _streamTypewriterText("⚡ Kiko awake: \"$ackText\" Speak your instruction now...");

    if (_isAudioEngaged) {
      _turnOffMic(reason: 'Speaking wake-word acknowledgment');
      setState(() => _isSpeaking = true);
      final audioDur = await web_speech.speakTextAloud(ackText);
      final waitMs = ((audioDur + 0.3) * 1000).toInt();
      await Future.delayed(Duration(milliseconds: waitMs));
    }

    if (mounted) {
      setState(() => _isSpeaking = false);
      // Now start active recording for the user's instruction!
      _startCommandRecording(isAfterWakeWord: true);
    }
  }

  /// Actively records the user's instruction (e.g. 5.0s window).
  /// In this mode, button turns RED REC and pulses!
  /// If no voice input is coming, turns off recording without generating any output.
  void _startCommandRecording({
    bool isManualTap = false,
    bool isAfterWakeWord = false,
    bool isFollowUp = false,
  }) {
    _turnOffMic(reason: 'Starting active command recording (followUp: $isFollowUp)');
    if (!mounted || _isSpeaking || _isProcessingPrompt) return;

    setState(() {
      _isRecordingCommand = true;
      _isListeningWakeWord = false;
    });

    _streamTypewriterText(isFollowUp
        ? "🔴 [REC] Listening for next instruction... (speak now or stay silent)"
        : "🔴 [REC] Listening for your instruction... Speak now.");

    web_speech.initWebSpeech((transcript, isFinal) {
      if (!mounted) return;

      final cleanTranscript = transcript.trim();
      _turnOffMic(reason: 'Finished recording command: "$cleanTranscript"');

      // 1. If voice input was detected, process it
      if (cleanTranscript.isNotEmpty) {
        final wakeCheck = _analyzeWakeWord(cleanTranscript);

        // If user said only the wake word ("Kiko") during recording, acknowledge and open command recording
        if (wakeCheck.isDetected && wakeCheck.remainingCommand.trim().isEmpty) {
          debugPrint('[COMMAND-REC] Wake word detected during recording. Acknowledging...');
          _promptForInstructionAfterWake();
          return;
        }

        // Strip any repeated "kiko" if user said it again
        final finalPrompt = (wakeCheck.isDetected && wakeCheck.remainingCommand.trim().isNotEmpty)
            ? wakeCheck.remainingCommand.trim()
            : cleanTranscript;

        if (finalPrompt.trim().isNotEmpty) {
          _promptController.text = finalPrompt;
          _handleSynthesize(finalPrompt);
          return;
        }
      }

      // 3. NO VOICE INPUT DETECTED:
      // Turn off red REC button and smoothly transition BACK to continuous wake-word standby!
      debugPrint('[COMMAND-REC] No voice input detected. Seamlessly returning to continuous Wake-Word Standby.');
      _streamTypewriterText("Ready. Say \"Kiko\" to wake.");
      if (mounted) {
        setState(() {
          _isRecordingCommand = false;
          _isListeningWakeWord = false;
        });
      }
      if (_isAutoMicEnabled && mounted && !_isSpeaking && !_isProcessingPrompt) {
        _scheduleNextWakeWordCheck(delayMs: 50);
      }
    }, durationSeconds: 3.0);
  }

  void _onToggleMode(bool toGMode) {
    AppSettings.instance.setAgentMode(toGMode ? 'g_mode' : 'alpha');
    _streamTypewriterText(toGMode ? _gModeText : _alphaText);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final isGMode = settings.isGMode;
    final accent = SynapseTokens.primaryColor(isGMode);

    return Scaffold(
      backgroundColor: SynapseTokens.substrateVoid,
      body: AtmosphericBackground(
        isGMode: isGMode,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              return Column(
                children: [
                  // Top Status & Mode Control Bar
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 24.0 : 16.0,
                      vertical: 12.0,
                    ),
                    child: SynapseHeaderBar(
                      isGMode: isGMode,
                      isAudioEngaged: _isAudioEngaged,
                      onModeChanged: _onToggleMode,
                      onToggleAudio: () {
                        setState(() => _isAudioEngaged = !_isAudioEngaged);
                        if (_isAudioEngaged) {
                          _agentSpeakOutput("Voice telemetry online.");
                        } else {
                          _turnOffMic(reason: 'Audio stream disengaged');
                          setState(() => _isSpeaking = false);
                        }
                      },
                    ),
                  ),

                  // Main Scrollable HUD Deck
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32.0 : 16.0,
                        vertical: 8.0,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1280),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Hologram & Cognition Section
                              if (isWide)
                                _buildDesktopHeroSection(isGMode, accent)
                              else
                                _buildMobileHeroSection(isGMode, accent),

                              const SizedBox(height: 20),

                              // Kinetic Dialogue Stage
                              KineticDialogueStage(
                                isGMode: isGMode,
                                text: _currentDialogueText,
                                isStreaming: _isStreaming,
                                isSpeaking: _isSpeaking,
                                isListening: _isRecordingCommand,
                                onReplay: () {
                                  final textToPlay = _currentDialogueText.isNotEmpty
                                      ? _currentDialogueText
                                      : (isGMode ? _gModeText : _alphaText);
                                  _agentSpeakOutput(textToPlay);
                                },
                                onBranch: () {
                                  _streamTypewriterText(
                                    'Branching cognitive reasoning path #02. Parallel context matrix instantiated.',
                                  );
                                },
                                onToggleMode: () => _onToggleMode(!isGMode),
                              ),

                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom Floating Command Deck
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isWide ? 32.0 : 16.0,
                      4.0,
                      isWide ? 32.0 : 16.0,
                      12.0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1280),
                        child: SynapseCommandDeck(
                          isGMode: isGMode,
                          controller: _promptController,
                          isPttActive: _isRecordingCommand,
                          isAutoMic: _isAutoMicEnabled,
                          onToggleAutoMic: _toggleAutoMic,
                          onPttStart: () {
                            if (_isRecordingCommand) {
                              _turnOffMic(reason: 'User tapped mic to mute');
                              if (_isAutoMicEnabled) {
                                _scheduleNextWakeWordCheck(delayMs: 300);
                              }
                            } else {
                              if (_isSpeaking) {
                                web_speech.stopWebSpeech();
                                setState(() => _isSpeaking = false);
                              }
                              _startCommandRecording(isManualTap: true);
                            }
                          },
                          onSubmitted: _handleSynthesize,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Desktop Layout: Cognition sub-panel on left, Hologram Orb with live status on right
  Widget _buildDesktopHeroSection(bool isGMode, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left: Cognition Metrics Card (40% width)
        Expanded(
          flex: 5,
          child: CognitionMetricsCard(
            isGMode: isGMode,
            threadId: _activeTaskId,
            taskName: _activeTaskName,
            status: _activeTaskStatus,
            statusMessage: _taskStatusMessage,
            activeUrl: _browserCurrentUrl,
            sources: _browserSources,
            screenshotB64: _browserScreenshotB64,
            onStopTask: _stopActiveTask,
          ),
        ),

        const SizedBox(width: 32),

        // Right: Holographic Dotted Face Orb Stage
        Expanded(
          flex: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Live status badges & speech cadence toggle
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: SynapseTokens.surfaceHigh.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isRecordingCommand
                                ? const Color(0xFFFF2A2A)
                                : (_isSpeaking
                                    ? accent
                                    : (_isProcessingPrompt
                                        ? Colors.amberAccent
                                        : (_isAutoMicEnabled
                                            ? const Color(0xFF00E676)
                                            : SynapseTokens.outline))),
                            boxShadow: [
                              BoxShadow(
                                color: _isRecordingCommand
                                    ? const Color(0xFFFF2A2A)
                                    : (_isSpeaking
                                        ? accent
                                        : (_isProcessingPrompt
                                            ? Colors.amberAccent
                                            : (_isAutoMicEnabled
                                                ? const Color(0xFF00E676)
                                                : Colors.transparent))),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isRecordingCommand
                              ? '🔴 RECORDING // SPEAK NOW'
                              : (_isSpeaking
                                  ? '🔊 SPEAKING // MIC OFF'
                                  : (_isProcessingPrompt
                                      ? '⚡ THINKING // MIC OFF'
                                      : (_isAutoMicEnabled
                                          ? '🟢 WAKE-WORD: "KIKO"'
                                          : '🎙️ MANUAL PTT'))),
                          style: TextStyle(
                            color: _isRecordingCommand
                                ? const Color(0xFFFF5252)
                                : (_isSpeaking
                                    ? accent
                                    : (_isProcessingPrompt
                                        ? Colors.amberAccent
                                        : (_isAutoMicEnabled
                                            ? const Color(0xFF00E676)
                                            : SynapseTokens.outline))),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Toggle Cadence Button
                  InkWell(
                    onTap: () {
                      setState(() => _isSpeaking = !_isSpeaking);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: SynapseTokens.surfaceContainer.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isSpeaking ? Icons.pause_circle : Icons.graphic_eq,
                            color: accent,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isSpeaking ? 'PAUSE JAW CADENCE' : 'SIMULATE SPEECH CADENCE',
                            style: const TextStyle(
                              color: SynapseTokens.onSurface,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 28),

              // The Holographic Dotted Face Orb
              HolographicDottedFaceOrb(
                isGMode: isGMode,
                isSpeaking: _isSpeaking || _isRecordingCommand,
                size: 190.0,
                onTap: () {
                  setState(() => _isSpeaking = !_isSpeaking);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mobile Layout: Center-stage Holographic Face Orb & stacked metrics
  Widget _buildMobileHeroSection(bool isGMode, Color accent) {
    return Column(
      children: [
        // Center Stage Holographic Orb
        Center(
          child: HolographicDottedFaceOrb(
            isGMode: isGMode,
            isSpeaking: _isSpeaking || _isRecordingCommand,
            size: 160.0,
            onTap: () {
              setState(() => _isSpeaking = !_isSpeaking);
            },
          ),
        ),

        const SizedBox(height: 14),

        // Status badge & Cadence toggle pill
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: SynapseTokens.surfaceHigh.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecordingCommand
                          ? const Color(0xFFFF2A2A)
                          : (_isSpeaking
                              ? accent
                              : (_isProcessingPrompt
                                  ? Colors.amberAccent
                                  : (_isAutoMicEnabled
                                      ? const Color(0xFF00E676)
                                      : SynapseTokens.outline))),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isRecordingCommand
                        ? '🔴 RECORDING // SPEAK NOW'
                        : (_isSpeaking
                            ? '🔊 SPEAKING // MIC OFF'
                            : (_isProcessingPrompt
                                ? '⚡ THINKING // MIC OFF'
                                : (_isAutoMicEnabled
                                    ? '🟢 WAKE-WORD: "KIKO"'
                                    : '🎙️ MANUAL PTT'))),
                    style: TextStyle(
                      color: _isRecordingCommand
                          ? const Color(0xFFFF5252)
                          : (_isSpeaking
                              ? accent
                              : (_isProcessingPrompt
                                  ? Colors.amberAccent
                                  : (_isAutoMicEnabled
                                      ? const Color(0xFF00E676)
                                      : SynapseTokens.outline))),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: () => setState(() => _isSpeaking = !_isSpeaking),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: SynapseTokens.surfaceContainer.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isSpeaking ? Icons.pause : Icons.graphic_eq,
                      color: accent,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isSpeaking ? 'Pause' : 'Cadence',
                      style: const TextStyle(
                        color: SynapseTokens.onSurface,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Cognition Sub-panel
        CognitionMetricsCard(
          isGMode: isGMode,
          threadId: _activeTaskId,
          taskName: _activeTaskName,
          status: _activeTaskStatus,
          statusMessage: _taskStatusMessage,
          activeUrl: _browserCurrentUrl,
          sources: _browserSources,
          screenshotB64: _browserScreenshotB64,
          onStopTask: _stopActiveTask,
        ),
      ],
    );
  }
}
