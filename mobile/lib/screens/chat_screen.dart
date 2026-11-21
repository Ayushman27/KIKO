/// KIKO Desktop Chat Screen
/// Sends tasks to Alpha or G Mode depending on the current mode setting.
/// Shows real backend responses, task status, and tool execution results.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/app_settings.dart';
import '../config/kiko_theme.dart';
import '../services/websocket_service.dart';

class _Message {
  final String sender; // 'user' | 'kiko' | 'system' | 'error'
  final String text;
  final String? taskId;
  String status; // 'pending' | 'running' | 'done' | 'failed'
  final DateTime timestamp;

  _Message({
    required this.sender,
    required this.text,
    this.taskId,
    this.status = 'done',
  }) : timestamp = DateTime.now();
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<_Message> _messages = [];
  String? _sessionId;
  bool _sending = false;
  late Function(Map<String, dynamic>) _wsListener;

  @override
  void initState() {
    super.initState();
    _wsListener = _handleWsMessage;
    WebSocketService.instance.addListener(_wsListener);
    WebSocketService.instance.connect();
    _messages.add(_Message(
      sender: 'kiko',
      text: 'Greetings, Ayushman. I\'m KIKO. How can I assist you today?\n\n'
          'Tip: Use Ctrl+Enter to send, or press Enter in the input box.',
    ));
    _initSession();
  }

  @override
  void dispose() {
    WebSocketService.instance.removeListener(_wsListener);
    _input.dispose();
    _scroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleWsMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final event = msg['event'] ?? '';
    final taskId = msg['task_id'];
    final text = msg['message'] ?? '';

    if (['TASK_PROGRESS', 'TASK_STARTED', 'TASK_COMPLETED', 'TASK_FAILED',
        'G_EXPERIMENT_PROGRESS', 'G_EXPERIMENT_COMPLETED', 'G_CANDIDATE_READY']
        .contains(event)) {
      // Update existing task message or add new
      setState(() {
        final idx = _messages.indexWhere(
            (m) => m.taskId != null && m.taskId == taskId?.toString());
        if (idx >= 0) {
          if (event == 'TASK_COMPLETED' || event == 'G_EXPERIMENT_COMPLETED') {
            _messages[idx].status = 'done';
          } else if (event == 'TASK_FAILED') {
            _messages[idx].status = 'failed';
          }
          // Append progress to existing message
          _messages.add(_Message(
              sender: 'kiko',
              text: text.isNotEmpty ? text : event,
              taskId: taskId?.toString()));
        } else {
          _messages.add(_Message(
              sender: 'kiko',
              text: text.isNotEmpty ? text : event,
              taskId: taskId?.toString()));
        }
      });
      _scrollToBottom();
    }
  }

  Future<void> _initSession() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/sessions'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final sessions = jsonDecode(res.body) as List;
        if (sessions.isNotEmpty) {
          setState(() => _sessionId = sessions.first['id']);
          _loadHistory(_sessionId!);
        } else {
          _createSession();
        }
      }
    } catch (_) {}
  }

  Future<void> _createSession() async {
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/sessions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'title': 'New Chat'}),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _sessionId = data['id']);
      }
    } catch (_) {}
  }

  Future<void> _loadHistory(String sessionId) async {
    try {
      final res = await http
          .get(Uri.parse(
              '${ApiConfig.baseUrl}/api/v1/sessions/$sessionId/messages'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final msgs = jsonDecode(res.body) as List;
        if (msgs.isNotEmpty && mounted) {
          setState(() {
            _messages.clear();
            for (final m in msgs.take(50)) {
              _messages.add(_Message(
                sender: m['sender'] ?? 'kiko',
                text: m['content'] ?? '',
              ));
            }
          });
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  Future<void> _send([String? override]) async {
    final text = (override ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    _focusNode.requestFocus();

    final settings = AppSettings.instance;
    final mode = settings.agentMode;

    final userMsg = _Message(sender: 'user', text: text);
    final pendingMsg = _Message(
        sender: 'kiko',
        text: mode == 'g_mode'
            ? '🔬 Starting G Mode experiment...'
            : '⏳ Processing...',
        status: 'running');

    setState(() {
      _messages.add(userMsg);
      _messages.add(pendingMsg);
      _sending = true;
    });
    _scrollToBottom();

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'description': text,
          'origin_device': 'WINDOWS_DESKTOP',
          'session_id': _sessionId,
          'mode': mode,
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['session_id'] != null) {
          setState(() => _sessionId = data['session_id']);
        }

        final taskId = data['id']?.toString() ?? '';
        final taskMode = data['mode'] ?? mode;
        final shortId = taskId.length >= 8 ? taskId.substring(0, 8) : taskId;

        String reply;
        if (taskMode == 'g_mode') {
          reply = '🔬 G Mode experiment started [${shortId}].\n'
              'Objective: "$text"\n'
              'Workspace: ${data['workspace_path'] ?? 'isolated sandbox'}\n'
              'Monitor progress in the G Mode tab or watch the live log here.';
        } else {
          final steps = data['steps'] as List? ?? [];
          final targetDevices = steps
              .map((s) => s['target_device']?.toString() ?? '')
              .where((d) => d.isNotEmpty)
              .toSet()
              .join(', ');

          reply = 'Task initiated [$shortId]'
              '${targetDevices.isNotEmpty ? ' → $targetDevices' : ''}.\n'
              '${_describeSteps(steps)}';
        }

        setState(() {
          final idx = _messages.indexOf(pendingMsg);
          if (idx >= 0) {
            _messages[idx] = _Message(
                sender: 'kiko',
                text: reply,
                taskId: taskId,
                status: 'running');
          }
        });
      } else {
        _setError(pendingMsg, 'Backend returned HTTP ${res.statusCode}');
      }
    } catch (e) {
      _setError(pendingMsg,
          'Failed to reach backend at ${ApiConfig.baseUrl}.\n$e\n\nCheck Settings → Backend URL.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _scrollToBottom();
  }

  void _setError(_Message pending, String err) {
    setState(() {
      final idx = _messages.indexOf(pending);
      if (idx >= 0) {
        _messages[idx] =
            _Message(sender: 'error', text: '⚠️ $err', status: 'failed');
      }
    });
  }

  String _describeSteps(List steps) {
    if (steps.isEmpty) return 'Executing...';
    final lines = steps.take(4).map((s) {
      final tool = s['tool_name'] ?? 'unknown';
      final device = s['target_device'] ?? '';
      return '• $tool${device.isNotEmpty ? " → $device" : ""}';
    }).join('\n');
    if (steps.length > 4) return '$lines\n• ...+${steps.length - 4} more';
    return lines;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final isGMode = settings.isGMode;

    return Column(
      children: [
        // Session bar
        Container(
          color: KikoColors.bg1,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 14,
                  color:
                      isGMode ? KikoColors.purple : KikoColors.cyan),
              const SizedBox(width: 6),
              Text(
                _sessionId != null
                    ? 'Session: ${_sessionId!.substring(0, 8)}'
                    : 'No session',
                style: const TextStyle(
                    color: KikoColors.textMuted, fontSize: 11),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await _createSession();
                  if (mounted) {
                    setState(() {
                      _messages.clear();
                      _messages.add(_Message(
                          sender: 'kiko',
                          text: 'New session started. How can I help?'));
                    });
                  }
                },
                icon: const Icon(Icons.add, size: 14, color: KikoColors.textMuted),
                label: const Text('New Chat',
                    style:
                        TextStyle(color: KikoColors.textMuted, fontSize: 11)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _buildMessage(_messages[i], isGMode),
          ),
        ),

        // Input bar
        _buildInputBar(isGMode),
      ],
    );
  }

  Widget _buildMessage(_Message msg, bool isGMode) {
    final isUser = msg.sender == 'user';
    final isError = msg.sender == 'error';
    final isSystem = msg.sender == 'system';

    if (isSystem) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(msg.text,
              style: const TextStyle(
                  color: KikoColors.textMuted, fontSize: 11)),
        ),
      );
    }

    final bubbleColor = isUser
        ? (isGMode ? KikoColors.purple.withOpacity(0.12) : KikoColors.cyan.withOpacity(0.12))
        : isError
            ? KikoColors.error.withOpacity(0.08)
            : KikoColors.bg2;

    final borderColor = isUser
        ? (isGMode ? KikoColors.purple.withOpacity(0.3) : KikoColors.cyan.withOpacity(0.3))
        : isError
            ? KikoColors.error.withOpacity(0.3)
            : KikoColors.bg3;

    final textColor = isUser
        ? (isGMode ? KikoColors.purple : KikoColors.cyan)
        : isError
            ? KikoColors.error
            : KikoColors.textPrimary;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: bubbleColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: msg.status == 'running' && !isUser
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(msg.text,
                              style: TextStyle(color: textColor, fontSize: 13, height: 1.5)),
                        ),
                        const SizedBox(width: 8),
                        const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: KikoColors.cyan)),
                      ],
                    )
                  : SelectableText(
                      msg.text,
                      style: TextStyle(color: textColor, fontSize: 13, height: 1.5),
                    ),
            ),
            // Copy + timestamp row
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _fmtTime(msg.timestamp),
                    style: const TextStyle(
                        color: KikoColors.textMuted, fontSize: 9),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Copied'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                            margin: EdgeInsets.only(
                                bottom: 80, left: 20, right: 20)),
                      );
                    },
                    child: const Icon(Icons.copy, size: 12, color: KikoColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isGMode) {
    final borderColor = isGMode ? KikoColors.purple : KikoColors.cyan;
    return Container(
      color: KikoColors.bg1,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick suggestions
          if (!_sending)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!isGMode) ...[
                    _chip('Open Chrome', Icons.web),
                    _chip('Take screenshot', Icons.screenshot),
                    _chip('What files are in Documents?', Icons.folder),
                    _chip('Check my tasks', Icons.task_alt),
                  ] else ...[
                    _chip('Research Python async patterns', Icons.science),
                    _chip('Build a REST API prototype', Icons.code),
                    _chip('Analyze system performance', Icons.analytics),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          // Input row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter,
                        control: true): () => _send(),
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(
                        color: KikoColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: isGMode
                          ? 'Describe an experiment objective for G Mode...'
                          : 'Ask KIKO anything, or give a task command...',
                      hintStyle: const TextStyle(
                          color: KikoColors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: KikoColors.bg2,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: KikoColors.bg3)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: KikoColors.bg3)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: borderColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: _sending ? KikoColors.bg3 : borderColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: KikoColors.textSecondary))
                      : Icon(
                          isGMode ? Icons.science : Icons.send_rounded,
                          color: _sending ? KikoColors.textMuted : KikoColors.bg0,
                        ),
                  onPressed: _sending ? null : _send,
                  tooltip: 'Send (Enter or Ctrl+Enter)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isGMode
                ? 'G Mode · Ctrl+Enter to send · Ctrl+G to switch to Alpha'
                : 'Alpha Mode · Enter or Ctrl+Enter to send · Ctrl+G for G Mode',
            style: const TextStyle(color: KikoColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    return GestureDetector(
      onTap: () => _send(label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: KikoColors.bg2,
          border: Border.all(color: KikoColors.bg3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: KikoColors.textMuted),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: KikoColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
