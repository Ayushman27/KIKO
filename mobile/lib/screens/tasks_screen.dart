/// Tasks Screen — shows real task history from the backend.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/kiko_theme.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _tasks = [];
  Map<String, dynamic>? _selected;
  bool _loading = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = _tasks.isEmpty);
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/tasks'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _tasks = List<Map<String, dynamic>>.from(jsonDecode(res.body));
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Task list
        Container(
          width: 340,
          color: KikoColors.bg1,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Text('Task History',
                        style: TextStyle(
                            color: KikoColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          size: 16, color: KikoColors.textMuted),
                      onPressed: _load,
                      tooltip: 'Refresh',
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
                    : _tasks.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.task_alt,
                                    color: KikoColors.textMuted, size: 40),
                                SizedBox(height: 10),
                                Text('No tasks yet',
                                    style: TextStyle(
                                        color: KikoColors.textMuted)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _tasks.length,
                            itemBuilder: (_, i) => _taskItem(_tasks[i]),
                          ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Task detail
        Expanded(
          child: _selected == null
              ? const Center(
                  child: Text('Select a task to see details',
                      style: TextStyle(color: KikoColors.textMuted)))
              : _buildDetail(_selected!),
        ),
      ],
    );
  }

  Widget _taskItem(Map<String, dynamic> task) {
    final status = task['status'] ?? 'UNKNOWN';
    final color = statusColor(status);
    final sel = _selected?['id'] == task['id'];

    return InkWell(
      onTap: () => setState(() => _selected = task),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: sel ? KikoColors.cyan.withOpacity(0.07) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['description'] ?? 'Unnamed task',
                    style: TextStyle(
                        color: sel ? KikoColors.cyan : KikoColors.textPrimary,
                        fontSize: 12,
                        fontWeight:
                            sel ? FontWeight.w700 : FontWeight.normal),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(status,
                            style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmtTime(task['created_at'] ?? ''),
                        style: const TextStyle(
                            color: KikoColors.textMuted, fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(Map<String, dynamic> task) {
    final steps = task['steps'] as List? ?? [];
    final status = task['status'] ?? 'UNKNOWN';
    final color = statusColor(status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  border: Border.all(color: color.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task['id']?.toString().substring(0, 8) ?? '',
                  style: const TextStyle(
                      color: KikoColors.textMuted,
                      fontSize: 11,
                      fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 14, color: KikoColors.textMuted),
                tooltip: 'Copy task ID',
                onPressed: () => Clipboard.setData(
                    ClipboardData(text: task['id']?.toString() ?? '')),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SelectableText(
            task['description'] ?? '',
            style: const TextStyle(
                color: KikoColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _fmtTime(task['created_at'] ?? ''),
            style:
                const TextStyle(color: KikoColors.textMuted, fontSize: 11),
          ),

          if (task['result_summary'] != null) ...[
            const SizedBox(height: 16),
            const Text('Result',
                style: TextStyle(
                    color: KikoColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: KikoColors.bg2,
                  borderRadius: BorderRadius.circular(10)),
              child: SelectableText(task['result_summary'],
                  style: const TextStyle(
                      color: KikoColors.textPrimary,
                      fontSize: 13,
                      height: 1.5)),
            ),
          ],

          if (steps.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Execution Steps',
                style: TextStyle(
                    color: KikoColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...steps.map((s) => _stepCard(s)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _stepCard(dynamic step) {
    final tool = step['tool_name'] ?? 'unknown';
    final device = step['target_device'] ?? '';
    final stepStatus = step['status'] ?? 'PENDING';
    final color = statusColor(stepStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: KikoColors.bg2, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool,
                    style: const TextStyle(
                        color: KikoColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace')),
                if (device.isNotEmpty)
                  Text('→ $device',
                      style: const TextStyle(
                          color: KikoColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
          Text(stepStatus,
              style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _fmtTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
