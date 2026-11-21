import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/api_config.dart';
import '../config/app_settings.dart';
import '../services/websocket_service.dart';
import '../utils/web_speech.dart' as web_speech;
import '../widgets/synapse/holographic_dotted_face_orb.dart';
import '../widgets/synapse/audio_eq_visualizer.dart';

/// Voice Agent Lifecycle States
enum VoiceState {
  waitingForWakeWord,
  activeSession,
  processing,
  speaking,
  inactivityTimeout,
}

/// Wake Word Detection Result Container
class WakeWordResult {
  final bool isDetected;
  final String candidate;
  final double similarity;
  final String remainingCommand;

  WakeWordResult({
    required this.isDetected,
    required this.candidate,
    required this.similarity,
    required this.remainingCommand,
  });
}

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with SingleTickerProviderStateMixin {
  // Configurable Parameters
  static const String CONFIG_PRIMARY_WAKE_WORD = "kiko";
  static const int CONFIG_WAKE_SESSION_TIMEOUT = 300; // 5 minutes in seconds
  static const List<String> WAKE_WORD_ALIASES = [
    "kiko",
    "kiku",
    "keko",
    "keeko",
    "kico",
    "kikoo",
    "echo",
    "heiko",
    "chiko",
    "kik",
    "kiko!",
    "kiko?",
  ];

  WebSocketChannel? _voiceChannel;
  late WebSocketService _mobileWsService;
  bool _isListening = true;
  bool _isConnected = false;
  
  // Voice Lifecycle State & Timers
  VoiceState _sessionState = VoiceState.waitingForWakeWord;
  Timer? _inactivityTimer;
  Timer? _reconnectTimer;
  Timer? _speechDebounceTimer;

  // Multi-Device Selection & Registry State
  bool _isAmbiguousChoice = false;
  String _ambiguousPrompt = "";
  List<Map<String, dynamic>> _connectedDevices = [];

  String _liveStatus = "🎤 Say 'Kiko' to start voice session...";
  String _userTranscript = "";
  String _agentResponse = "Greetings, Ayushman. Say 'Kiko' to activate continuous voice assistant mode.\n\nOnce activated, you can speak continuously without saying 'Kiko' before every command.";
  
  List<Map<String, String>> _chatMessages = [];
  final ScrollController _scrollController = ScrollController();

  late AnimationController _animController;
  final TextEditingController _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Connect mobile agent client WebSocket for local tool execution (apps, camera, URLs)
    _mobileWsService = WebSocketService();
    _mobileWsService.connect();

    // 1. Fetch persistent chat history from backend
    _fetchChatHistory();

    // 2. Connect WebSocket to Gemini Live Backend Voice Bridge
    _connectVoiceChannel();

    // 3. Initialize Chrome / Web Microphone Speech Recognition
    _initWebSpeechRecognition();
  }

  Future<void> _fetchChatHistory() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/voice/history');
      print('[HISTORY] Fetching voice history from: $url');
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body);
        if (mounted) {
          setState(() {
            _chatMessages = data.map((item) => {
              'role': (item['role'] ?? 'assistant').toString(),
              'text': (item['text'] ?? '').toString(),
            }).toList();
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      print('[HISTORY] Error fetching chat history: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addChatMessage(String role, String text) {
    if (text.trim().isEmpty) return;
    if (mounted) {
      setState(() {
        _chatMessages.add({
          'role': role,
          'text': text,
        });
      });
      _scrollToBottom();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!mounted) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isConnected) {
        _connectVoiceChannel();
      }
    });
  }

  void _connectVoiceChannel() {
    try {
      final wsUrl = '${ApiConfig.wsBaseUrl}/api/v1/voice/live';
      print('[SESSION] Connecting to Voice WebSocket: $wsUrl');
      _voiceChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

      setState(() {
        _isConnected = true;
        _isListening = true;
        _updateLiveStatus();
      });

      _voiceChannel!.stream.listen(
        (data) {
          try {
            final Map<String, dynamic> msg = jsonDecode(data);
            print('[SESSION] Voice Agent WebSocket received: $msg');

            final event = msg['event'];
            if (event == 'VOICE_RESPONSE') {
              final responseText = msg['text'];
              if (responseText != null && responseText.toString().isNotEmpty) {
                print('[TTS] Speaking response: "$responseText"');
                setState(() {
                  _isAmbiguousChoice = false;
                  _agentResponse = responseText;
                });
                _addChatMessage('assistant', responseText.toString());
                _speakTextAloud(responseText.toString());
              }
            } else if (event == 'VOICE_TRANSCRIPT') {
              final transcript = msg['text'] ?? msg['transcript'] ?? '';
              if (transcript.toString().isNotEmpty) {
                print('[GEMINI-LIVE-STT] Real-time transcript: "$transcript"');
                setState(() {
                  _userTranscript = transcript.toString();
                  _liveStatus = "🗣️ Voice: \"$transcript\"";
                });
                _onSpeechRecognized(transcript.toString(), true);
              }
            } else if (event == 'VOICE_CHUNK') {
              setState(() {
                _sessionState = VoiceState.speaking;
              });
            } else if (event == 'CHOICE_REQUIRED') {
              final promptText = msg['message'] ?? "Which device would you like me to use — your laptop or your phone?";
              setState(() {
                _sessionState = VoiceState.speaking;
                _isAmbiguousChoice = true;
                _ambiguousPrompt = promptText;
                _agentResponse = "KIKO: $promptText";
                _liveStatus = "❓ Device Choice Required";
              });
              _addChatMessage('assistant', "KIKO: $promptText");
              _speakTextAloud(promptText);
            } else if (event == 'TASK_FAILED') {
              final errMsg = msg['message'] ?? "Task failed";
              setState(() {
                _agentResponse = errMsg;
                _liveStatus = "⚠️ $errMsg";
              });
              _addChatMessage('assistant', "⚠️ $errMsg");
              _speakTextAloud(errMsg);
            } else if (event == 'DEVICE_LIST_UPDATED') {
              final List<dynamic> devList = msg['devices'] ?? [];
              setState(() {
                _connectedDevices = devList.cast<Map<String, dynamic>>();
              });
            } else if (event == 'ACTION_DISPATCHED') {
              setState(() {
                _liveStatus = msg['message'] ?? 'Executing action...';
              });
            }
          } catch (e) {
            print('[SESSION] Error parsing voice websocket: $e');
          }
        },
        onError: (err) {
          setState(() {
            _isConnected = false;
            _liveStatus = "Connection error. Reconnecting...";
          });
          _scheduleReconnect();
        },
        onDone: () {
          setState(() {
            _isConnected = false;
            _liveStatus = "Voice bridge disconnected. Reconnecting...";
          });
          _scheduleReconnect();
        },
      );
    } catch (e) {
      setState(() {
        _isConnected = false;
        _liveStatus = "Failed to connect to Voice Bridge ($e)";
      });
      _scheduleReconnect();
    }
  }

  void _initWebSpeechRecognition() {
    print('[WAKE] Initializing Gemini Live Speech Recognition');
    web_speech.initWebSpeech((String transcript, bool isFinal) {
      if (mounted && transcript.trim().isNotEmpty) {
        print('[STT] Speech Captured (isFinal=$isFinal): "$transcript"');
        _onSpeechRecognized(transcript, isFinal);
      }
    });
  }

  void _onSpeechRecognized(String transcript, bool isFinal) {
    if (transcript.trim().isEmpty) return;

    setState(() {
      _userTranscript = transcript;
    });

    _speechDebounceTimer?.cancel();

    if (isFinal) {
      _handleVoiceInput(transcript);
    } else {
      _speechDebounceTimer = Timer(const Duration(milliseconds: 900), () {
        _handleVoiceInput(transcript);
      });
    }
  }

  /// Reset 5-minute inactivity session timer on valid user interaction
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    print('[SESSION] Activity detected - timer reset (${CONFIG_WAKE_SESSION_TIMEOUT}s timeout)');
    _inactivityTimer = Timer(const Duration(seconds: CONFIG_WAKE_SESSION_TIMEOUT), () {
      if (mounted) {
        print('[SESSION] Inactivity timeout (${CONFIG_WAKE_SESSION_TIMEOUT}s elapsed without valid user command)');
        print('[SESSION] Returning to WAITING_FOR_WAKE_WORD');
        setState(() {
          _sessionState = VoiceState.inactivityTimeout;
          _liveStatus = "⏰ Session Ended due to inactivity";
          _agentResponse = "Kiko session ended due to 5 minutes of inactivity.\n\nSay 'Kiko' to start a new voice session.";
        });
      }
    });
  }

  /// Dedicated Wake-Word Detection Function with Fuzzy / Phonetic Matching
  WakeWordResult _analyzeWakeWord(String rawInput) {
    final text = rawInput.trim();
    if (text.isEmpty) {
      return WakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
    }

    final cleanLower = text.toLowerCase();
    final words = cleanLower.replaceAll(RegExp(r'[^\w\s]'), ' ').trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words[0].isEmpty) {
      return WakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
    }

    // Search across all word tokens for wake word match (e.g. "hi kiko", "hello kiko", "kiko")
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;

      bool isMatch = false;
      double similarity = 0.0;
      String matchedCandidate = word;

      // 1. Alias Match
      for (final alias in WAKE_WORD_ALIASES) {
        if (word == alias) {
          // Special "echo" protection: ignore if "echo" is embedded deep in a long sentence
          if (alias == "echo" && words.length > 3 && i > 1) {
            continue;
          }
          isMatch = true;
          similarity = 1.0;
          matchedCandidate = alias;
          break;
        }
      }

      // 2. Levenshtein Distance Match (Max 1 edit distance to "kiko")
      if (!isMatch) {
        final dist = _levenshtein(word, CONFIG_PRIMARY_WAKE_WORD);
        if (dist <= 1 && word.length >= 3) {
          isMatch = true;
          similarity = 1.0 - (dist / CONFIG_PRIMARY_WAKE_WORD.length);
          matchedCandidate = word;
        }
      }

      if (isMatch) {
        final remaining = _extractCommandFromPhrase(text, word, i, words);
        return WakeWordResult(
          isDetected: true,
          candidate: matchedCandidate,
          similarity: similarity,
          remainingCommand: remaining,
        );
      }
    }

    return WakeWordResult(isDetected: false, candidate: "", similarity: 0.0, remainingCommand: "");
  }

  String _extractCommandFromPhrase(String fullText, String matchedWord, int wordIndex, List<String> words) {
    if (wordIndex < words.length - 1) {
      final lowerFull = fullText.toLowerCase();
      final idx = lowerFull.indexOf(matchedWord);
      if (idx != -1) {
        final after = fullText.substring(idx + matchedWord.length).replaceAll(RegExp(r'^[\s,.]+'), '').trim();
        return after;
      }
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

  /// Process voice input according to current Voice Session State Machine
  void _handleVoiceInput(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return;

    print('[STT] Processing user speech: "$text"');

    // If WAITING_FOR_WAKE_WORD or INACTIVITY_TIMEOUT, check for Wake Word
    if (_sessionState == VoiceState.waitingForWakeWord || _sessionState == VoiceState.inactivityTimeout) {
      print('[WAKE] Listening for wake word');
      final wakeResult = _analyzeWakeWord(text);
      if (!wakeResult.isDetected) {
        print('[WAKE] Wake word rejected (no match in "$text")');
        setState(() {
          _userTranscript = text;
          _liveStatus = "⚠️ Say 'Kiko' to start voice session";
          _agentResponse = "⚠️ Command Ignored: \"$text\"\n\nWake word 'Kiko' was NOT detected. Please say 'Kiko' to activate continuous session.";
        });
        return;
      }

      print('[WAKE] Detected candidate: "${wakeResult.candidate}"');
      print('[WAKE] Similarity: ${wakeResult.similarity.toStringAsFixed(2)}');
      print('[WAKE] Wake word accepted');
      print('[SESSION] ACTIVE');

      // Transition to ACTIVE SESSION
      _sessionState = VoiceState.activeSession;
      _resetInactivityTimer();

      final remaining = wakeResult.remainingCommand;
      if (remaining.isEmpty) {
        // Standalone wake word "Kiko" -> Respond "Yes Ayushman?" directly without LLM!
        print('[SESSION] Standalone wake word detected — activating session & acknowledging');
        const ackMessage = "Yes Ayushman? I am listening.";
        setState(() {
          _userTranscript = text;
          _liveStatus = "🟢 SESSION ACTIVE — Listening continuously...";
          _agentResponse = "KIKO: $ackMessage";
        });
        _speakTextAloud(ackMessage);
        return;
      } else {
        // "Kiko, open Chrome" -> Execute command immediately!
        print('[SESSION] Wake word + command detected: "$remaining"');
        _sendVoicePrompt(remaining, displayPrompt: text);
      }
    } else {
      // SESSION IS ALREADY ACTIVE -> Process command directly without requiring wake word!
      print('[SESSION] ACTIVE — Command received without needing wake word');
      _resetInactivityTimer();
      _sendVoicePrompt(text, displayPrompt: text);
    }
  }

  void _sendVoicePrompt(String command, {required String displayPrompt}) {
    final cleanCommand = command.trim();
    if (cleanCommand.isEmpty) return;

    _sessionState = VoiceState.processing;
    _resetInactivityTimer();

    print('[STT] User input: "$cleanCommand"');
    print('[LLM] Processing command: "$cleanCommand"');

    setState(() {
      _userTranscript = displayPrompt;
      _isListening = true;
      _liveStatus = "⚡ Processing command: '$cleanCommand'...";
      _agentResponse = "Processing command: '$cleanCommand'...";
    });

    _addChatMessage('user', displayPrompt);

    if (_voiceChannel != null && _isConnected) {
      _voiceChannel!.sink.add(jsonEncode({
        'event': 'VOICE_PROMPT',
        'text': cleanCommand,
      }));
    } else {
      _connectVoiceChannel();
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_voiceChannel != null) {
          _voiceChannel!.sink.add(jsonEncode({
            'event': 'VOICE_PROMPT',
            'text': cleanCommand,
          }));
        }
      });
    }
    _promptController.clear();
  }

  void _updateLiveStatus() {
    if (_sessionState == VoiceState.activeSession) {
      _liveStatus = "🟢 SESSION ACTIVE — Listening continuously...";
    } else {
      _liveStatus = "🎤 Say 'Kiko' to start voice session...";
    }
  }

  void _stopWebSpeechRecognition() {
    web_speech.stopWebSpeech();
  }

  Future<void> _speakTextAloud(String text) async {
    // 1. Turn OFF mic while agent is speaking
    _stopWebSpeechRecognition();
    if (mounted) {
      setState(() {
        _sessionState = VoiceState.speaking;
        _isListening = false;
        _liveStatus = "🔊 Speaking output // Mic muted...";
      });
    }

    final dur = await web_speech.speakTextAloud(text);
    final waitMs = ((dur + 0.35) * 1000).toInt();

    // 2. Wait until speech playback completes
    await Future.delayed(Duration(milliseconds: waitMs));

    // 3. Turn ON mic after speaking finishes (Google Assistant style)
    if (mounted && _sessionState != VoiceState.inactivityTimeout) {
      setState(() {
        _sessionState = VoiceState.activeSession;
        _isListening = true;
        _updateLiveStatus();
      });
      _initWebSpeechRecognition();
      print('[SESSION] Assistant speech complete — Mic turned ON automatically');
    }
  }

  void _toggleMic() {
    setState(() {
      _isListening = !_isListening;
      if (_isListening) {
        _updateLiveStatus();
        _initWebSpeechRecognition();
      } else {
        _liveStatus = "Mic Muted. Tap to resume listening.";
        _stopWebSpeechRecognition();
      }
    });
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _speechDebounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _stopWebSpeechRecognition();
    _animController.dispose();
    _promptController.dispose();
    _voiceChannel?.sink.close();
    _mobileWsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSessionActive = _sessionState == VoiceState.activeSession || _sessionState == VoiceState.processing || _sessionState == VoiceState.speaking;

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: Color(0xFF00F0FF)),
            SizedBox(width: 8),
            Text(
              'Continuous Voice Assistant',
              style: TextStyle(color: Color(0xFF00F0FF), fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Chip(
              backgroundColor: isSessionActive ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2),
              side: BorderSide(color: isSessionActive ? Colors.greenAccent : Colors.amberAccent),
              label: Text(
                isSessionActive ? "🟢 SESSION ACTIVE (5m)" : "🎤 SAY 'KIKO' TO START",
                style: TextStyle(
                  color: isSessionActive ? Colors.greenAccent : Colors.amberAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),

          // Holographic Dotted Face Synthesizer Orb
          Center(
            child: GestureDetector(
              onTap: _toggleMic,
              child: HolographicDottedFaceOrb(
                isGMode: AppSettings.instance.isGMode,
                isSpeaking: _isListening || isSessionActive,
                size: 165.0,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 28-Bar Animated Audio Frequency Equalizer
          if (_isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: AudioEqVisualizer(
                isGMode: AppSettings.instance.isGMode,
                isSpeaking: _isListening || isSessionActive,
                barCount: 28,
                height: 24,
              ),
            ),

          const SizedBox(height: 8),

          Text(
            _liveStatus,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSessionActive ? const Color(0xFF00FF87) : const Color(0xFFFF007A),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 16),

          // Ambiguous Device Selection Row
          if (_isAmbiguousChoice)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1B4B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF818CF8)),
              ),
              child: Column(
                children: [
                  const Text(
                    "Which device should KIKO use?",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.laptop, color: Colors.black, size: 18),
                        label: const Text("💻 Laptop", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF60EFFF)),
                        onPressed: () {
                          setState(() => _isAmbiguousChoice = false);
                          _handleVoiceInput("on my laptop");
                        },
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.phone_android, color: Colors.white, size: 18),
                        label: const Text("📱 Phone", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF007A)),
                        onPressed: () {
                          setState(() => _isAmbiguousChoice = false);
                          _handleVoiceInput("on my phone");
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Quick Voice Action Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildVoiceChip("Kiko", Icons.mic),
                _buildVoiceChip("open my phone's camera", Icons.camera_alt),
                _buildVoiceChip("open calculator on my laptop", Icons.calculate),
                _buildVoiceChip("open WhatsApp on my phone", Icons.chat),
                _buildVoiceChip("open camera", Icons.videocam),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Live Transcript Feed Container
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isSessionActive ? const Color(0xFF00FF87).withOpacity(0.3) : const Color(0xFF00F0FF).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.forum, color: isSessionActive ? const Color(0xFF00FF87) : const Color(0xFF00F0FF), size: 18),
                      const SizedBox(width: 8),
                      const Text("Voice Session Chat History", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white54, size: 16),
                        onPressed: _fetchChatHistory,
                        tooltip: "Sync Conversation History",
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  
                  Expanded(
                    child: _chatMessages.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              child: Text(
                                _agentResponse,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white38, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: _chatMessages.length,
                            itemBuilder: (context, index) {
                              final msg = _chatMessages[index];
                              final isUser = msg['role'] == 'user';
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUser ? const Color(0xFF1E293B) : const Color(0xFF064E3B).withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isUser ? const Color(0xFF38BDF8).withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isUser ? Icons.person : Icons.smart_toy,
                                          size: 14,
                                          color: isUser ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isUser ? "USER VOICE" : "KIKO AGENT",
                                          style: TextStyle(
                                            color: isUser ? const Color(0xFF38BDF8) : const Color(0xFF34D399),
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    SelectableText(
                                      msg['text'] ?? "",
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Voice / Text Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: isSessionActive
                          ? "Session active — type or speak commands..."
                          : "Say 'Kiko' or type a command...",
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    ),
                    onSubmitted: _handleVoiceInput,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFF00F0FF)),
                  onPressed: () => _handleVoiceInput(_promptController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceChip(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, color: const Color(0xFF00F0FF), size: 16),
        label: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: const Color(0xFF1E293B),
        side: BorderSide(color: const Color(0xFF00F0FF).withOpacity(0.3)),
        onPressed: () => _handleVoiceInput(text),
      ),
    );
  }
}

