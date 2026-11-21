/// Sessions Panel — shows conversation history and allows switching sessions.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/kiko_theme.dart';

class SessionsPanel extends StatefulWidget {
  const SessionsPanel({super.key});
  @override
  State<SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends State<SessionsPanel> {
  List<Map<String, dynamic>> _sessions = [];
  String? _selectedId;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/sessions'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMessages(String sessionId) async {
    setState(() {
      _selectedId = sessionId;
      _messages = [];
    });
    try {
      final res = await http
          .get(Uri.parse(
              '${ApiConfig.baseUrl}/api/v1/sessions/$sessionId/messages'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _messages =
              List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Session list
        Container(
          width: 260,
          color: KikoColors.bg1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Text('Conversations',
                        style: TextStyle(
                            color: KikoColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 16, color: KikoColors.textMuted),
                      onPressed: _loadSessions,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: KikoColors.cyan, strokeWidth: 2))
                    : _sessions.isEmpty
                        ? const Center(
                            child: Text('No sessions yet',
                                style: TextStyle(color: KikoColors.textMuted)))
                        : ListView.builder(
                            itemCount: _sessions.length,
                            itemBuilder: (_, i) {
                              final s = _sessions[i];
                              final sel = _selectedId == s['id'];
                              return InkWell(
                                onTap: () => _loadMessages(s['id']),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  color: sel
                                      ? KikoColors.cyan.withOpacity(0.08)
                                      : Colors.transparent,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s['title'] ?? 'Untitled',
                                        style: TextStyle(
                                            color: sel
                                                ? KikoColors.cyan
                                                : KikoColors.textPrimary,
                                            fontSize: 13,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.normal),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _formatTime(s['updated_at'] ?? ''),
                                        style: const TextStyle(
                                            color: KikoColors.textMuted,
                                            fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Message viewer
        Expanded(
          child: _selectedId == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, color: KikoColors.textMuted, size: 48),
                      SizedBox(height: 12),
                      Text('Select a conversation to view its messages',
                          style: TextStyle(color: KikoColors.textMuted)),
                    ],
                  ),
                )
              : _messages.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: KikoColors.cyan, strokeWidth: 2))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m = _messages[i];
                        final isUser = m['sender'] == 'user';
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.6),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? KikoColors.cyan.withOpacity(0.12)
                                  : KikoColors.bg2,
                              border: Border.all(
                                  color: isUser
                                      ? KikoColors.cyan.withOpacity(0.3)
                                      : KikoColors.bg3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['content'] ?? '',
                                  style: TextStyle(
                                      color: isUser
                                          ? KikoColors.cyan
                                          : KikoColors.textPrimary,
                                      fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(m['created_at'] ?? ''),
                                  style: const TextStyle(
                                      color: KikoColors.textMuted,
                                      fontSize: 9),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
