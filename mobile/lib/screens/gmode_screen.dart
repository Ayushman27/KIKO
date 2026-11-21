/// G Mode Dashboard Screen for KIKO
/// Shows active experiments, task queues, logs, candidate improvements,
/// and controls (pause/resume/cancel/emergency stop).
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/websocket_service.dart';

class GModeScreen extends StatefulWidget {
  const GModeScreen({super.key});

  @override
  State<GModeScreen> createState() => _GModeScreenState();
}

class _GModeScreenState extends State<GModeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _experiments = [];
  Map<String, dynamic>? _selectedExperiment;
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _status;
  bool _loading = false;
  final _objectiveController = TextEditingController();
  String _selectedMode = 'research';
  int _maxRuntimeMins = 60;

  // Live log stream from WebSocket
  final List<String> _liveLog = [];
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadStatus();
    _loadExperiments();
    // Subscribe to G Mode WebSocket events
    _wsSub = WebSocketService.instance.messageStream.listen((raw) {
      try {
        final data = jsonDecode(raw);
        final event = data['event'] ?? '';
        if (event.startsWith('G_')) {
          setState(() {
            _liveLog.insert(
                0,
                '[${event}] ${data['message'] ?? data.toString()}');
            if (_liveLog.length > 200) _liveLog.removeLast();
          });
          // Refresh experiment list on completion events
          if (['G_EXPERIMENT_COMPLETED', 'G_EXPERIMENT_CANCELLED',
               'G_CANDIDATE_READY', 'G_CANDIDATE_APPROVED'].contains(event)) {
            _loadExperiments();
            if (_selectedExperiment != null) {
              _loadExperimentDetail(_selectedExperiment!['id']);
            }
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _objectiveController.dispose();
    _wsSub?.cancel();
    super.dispose();
  }

  // ─── API calls ─────────────────────────────────────────────────────────────

  Future<void> _loadStatus() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/status'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) {
        setState(() => _status = jsonDecode(res.body));
      }
    } catch (_) {}
  }

  Future<void> _loadExperiments() async {
    setState(() => _loading = true);
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/experiments?limit=30'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _experiments = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadExperimentDetail(String id) async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/experiments/$id'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _selectedExperiment = data;
          _logs = List<Map<String, dynamic>>.from(data['logs'] ?? []);
          _candidates =
              List<Map<String, dynamic>>.from(data['candidates'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _startExperiment() async {
    final obj = _objectiveController.text.trim();
    if (obj.isEmpty) return;
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/experiments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'objective': obj,
          'mode': _selectedMode,
          'max_runtime_secs': _maxRuntimeMins * 60,
        }),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        _objectiveController.clear();
        _loadExperiments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔬 G Mode experiment started!'),
              backgroundColor: Color(0xFF8A2BE2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _pauseExperiment(String id) async {
    await http
        .post(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/experiments/$id/pause'))
        .timeout(const Duration(seconds: 5));
    _loadExperiments();
  }

  Future<void> _resumeExperiment(String id) async {
    await http
        .post(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/experiments/$id/resume'))
        .timeout(const Duration(seconds: 5));
    _loadExperiments();
  }

  Future<void> _cancelExperiment(String id) async {
    await http
        .post(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/experiments/$id/cancel'))
        .timeout(const Duration(seconds: 5));
    _loadExperiments();
  }

  Future<void> _emergencyStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('⛔ Emergency Stop',
            style: TextStyle(color: Color(0xFFFF4444))),
        content: const Text(
            'This will cancel ALL running G Mode experiments immediately. Continue?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4444)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('STOP ALL'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/emergency-stop'))
          .timeout(const Duration(seconds: 5));
      _loadExperiments();
      _loadStatus();
    }
  }

  Future<void> _reviewCandidate(
      String experimentId, String candidateId, bool approve) async {
    final notesCtrl = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(
          approve ? '✅ Approve Candidate' : '❌ Reject Candidate',
          style: TextStyle(
              color: approve ? const Color(0xFF00F0FF) : const Color(0xFFFF4444)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (approve)
              const Text(
                '⚠️ Approval records your decision but does NOT automatically copy files to the main codebase. You must manually review and copy files from the workspace.',
                style: TextStyle(color: Colors.amber, fontSize: 12),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Review notes (optional)',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF334155))),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    approve ? const Color(0xFF00F0FF) : const Color(0xFFFF4444)),
            onPressed: () => Navigator.pop(context, notesCtrl.text),
            child: Text(approve ? 'Approve' : 'Reject',
                style: const TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (notes == null) return;

    try {
      final res = await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/v1/gmode/experiments/$experimentId/candidates/$candidateId/review'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'approved': approve, 'review_notes': notes}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && mounted) {
        _loadExperimentDetail(experimentId);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve
              ? '✅ Candidate approved. Review workspace files before promoting.'
              : '❌ Candidate rejected.'),
          backgroundColor:
              approve ? const Color(0xFF00F0FF) : const Color(0xFFFF4444),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF8A2BE2), Color(0xFF4B0082)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('G MODE',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 13)),
            ),
            const SizedBox(width: 10),
            const Text('Autonomous Research Lab',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
        actions: [
          if (_status != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF8A2BE2)),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  '${_status!['running_experiments']} running',
                  style: const TextStyle(color: Color(0xFF8A2BE2), fontSize: 11)),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.warning_amber, color: Color(0xFFFF4444)),
            tooltip: 'Emergency Stop All',
            onPressed: _emergencyStop,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54),
            onPressed: () {
              _loadExperiments();
              _loadStatus();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF8A2BE2),
          labelColor: const Color(0xFF8A2BE2),
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.science), text: 'Experiments'),
            Tab(icon: Icon(Icons.terminal), text: 'Live Log'),
            Tab(icon: Icon(Icons.pending_actions), text: 'Candidates'),
            Tab(icon: Icon(Icons.add_circle_outline), text: 'New'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExperimentsTab(),
          _buildLiveLogTab(),
          _buildCandidatesTab(),
          _buildNewExperimentTab(),
        ],
      ),
    );
  }

  Widget _buildExperimentsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8A2BE2)));
    }
    if (_experiments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.science_outlined, color: Colors.white24, size: 64),
            const SizedBox(height: 16),
            const Text('No experiments yet.',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Start one in the "New" tab.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A2BE2)),
              onPressed: () => _tabController.animateTo(3),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Experiment',
                  style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _experiments.length,
      itemBuilder: (ctx, i) => _buildExperimentCard(_experiments[i]),
    );
  }

  Widget _buildExperimentCard(Map<String, dynamic> exp) {
    final status = exp['status'] ?? 'UNKNOWN';
    final statusColor = _statusColor(status);
    final isSelected = _selectedExperiment?['id'] == exp['id'];

    return GestureDetector(
      onTap: () {
        _loadExperimentDetail(exp['id']);
        _tabController.animateTo(2); // switch to candidates
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A0E2E) : const Color(0xFF0F172A),
          border: Border.all(
              color: isSelected ? const Color(0xFF8A2BE2) : const Color(0xFF1E293B)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(status,
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(exp['mode'] ?? 'research',
                      style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ),
                const Spacer(),
                Text(
                  'iter ${exp['iteration_count'] ?? 0}',
                  style: const TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              exp['objective'] ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (exp['result_summary'] != null) ...[
              const SizedBox(height: 6),
              Text(exp['result_summary'],
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (status == 'RUNNING')
                  _actionBtn('Pause', Icons.pause, const Color(0xFFFFA500),
                      () => _pauseExperiment(exp['id'])),
                if (status == 'PAUSED')
                  _actionBtn('Resume', Icons.play_arrow, const Color(0xFF00F0FF),
                      () => _resumeExperiment(exp['id'])),
                if (['RUNNING', 'PAUSED', 'PENDING'].contains(status))
                  _actionBtn('Cancel', Icons.stop, const Color(0xFFFF4444),
                      () => _cancelExperiment(exp['id'])),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveLogTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              const Icon(Icons.fiber_manual_record, color: Color(0xFF00F0FF), size: 10),
              const SizedBox(width: 6),
              const Text('Live WebSocket Events',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _liveLog.clear()),
                child: const Text('Clear', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _liveLog.isEmpty
              ? const Center(
                  child: Text('Waiting for G Mode events...',
                      style: TextStyle(color: Colors.white24)))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: _liveLog.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _liveLog[i],
                      style: TextStyle(
                        color: _liveLog[i].contains('ERROR') || _liveLog[i].contains('FAILED')
                            ? const Color(0xFFFF6B6B)
                            : _liveLog[i].contains('COMPLETED') || _liveLog[i].contains('APPROVED')
                                ? const Color(0xFF00FF88)
                                : Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCandidatesTab() {
    return Column(
      children: [
        if (_selectedExperiment != null)
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                const Icon(Icons.science, color: Color(0xFF8A2BE2), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _selectedExperiment!['objective'] ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _candidates.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pending_actions, color: Colors.white24, size: 48),
                      SizedBox(height: 12),
                      Text('Select an experiment to view candidates',
                          style: TextStyle(color: Colors.white38)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _candidates.length,
                  itemBuilder: (_, i) => _buildCandidateCard(_candidates[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildCandidateCard(Map<String, dynamic> c) {
    final status = c['status'] ?? 'PENDING_REVIEW';
    final isPending = status == 'PENDING_REVIEW';
    final isApproved = status == 'APPROVED';
    final statusColor = isApproved
        ? const Color(0xFF00FF88)
        : status == 'REJECTED'
            ? const Color(0xFFFF4444)
            : const Color(0xFFFFA500);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        border: Border.all(
            color: isPending
                ? const Color(0xFFFFA500).withOpacity(0.4)
                : const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (c['candidate_score'] != null)
                Text('Score: ${c['candidate_score']}%',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(c['title'] ?? '',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(c['description'] ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
          if ((c['files_changed'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            const Text('Files changed:',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 4),
            ...((c['files_changed'] as List).take(5).map((f) => Text(
                  '  + $f',
                  style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontFamily: 'monospace'),
                ))),
          ],
          if (c['test_results'] != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle, color: Color(0xFF00FF88), size: 13),
              const SizedBox(width: 4),
              Text(
                '${c['test_results']['passed'] ?? 0} passed, '
                '${c['test_results']['failed'] ?? 0} failed',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ]),
          ],
          if (c['known_limitations'] != null) ...[
            const SizedBox(height: 6),
            Text('⚠️ ${c['known_limitations']}',
                style: const TextStyle(color: Colors.amber, fontSize: 11)),
          ],
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4444),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                  onPressed: () => _reviewCandidate(
                      c['experiment_id'], c['id'], false),
                  icon: const Icon(Icons.close, size: 14, color: Colors.white),
                  label: const Text('Reject', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                  onPressed: () => _reviewCandidate(
                      c['experiment_id'], c['id'], true),
                  icon: const Icon(Icons.check, size: 14, color: Colors.black),
                  label: const Text('Approve', style: TextStyle(color: Colors.black, fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNewExperimentTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // G Mode info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0E2E),
              border: Border.all(color: const Color(0xFF8A2BE2).withOpacity(0.4)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.science, color: Color(0xFF8A2BE2), size: 18),
                  SizedBox(width: 8),
                  Text('G Mode — Autonomous Research Agent',
                      style: TextStyle(
                          color: Color(0xFF8A2BE2),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'G Mode runs experiments autonomously in an isolated workspace. '
                  'It cannot modify the main KIKO codebase. Candidate improvements '
                  'require your explicit approval before any files are promoted.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    _statusChip('Running', '${_status!['running_experiments']}',
                        const Color(0xFF00F0FF)),
                    const SizedBox(width: 8),
                    _statusChip('Paused', '${_status!['paused_experiments']}',
                        const Color(0xFFFFA500)),
                    const SizedBox(width: 8),
                    _statusChip('Pending Review',
                        '${_status!['candidates_pending_review']}',
                        const Color(0xFF8A2BE2)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Objective',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _objectiveController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText:
                  'e.g. "Research best Python async patterns and create a prototype implementation"',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF8A2BE2)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Mode',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: ['research', 'coding', 'testing', 'evaluation'].map((m) {
              final selected = _selectedMode == m;
              return GestureDetector(
                onTap: () => setState(() => _selectedMode = m),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF8A2BE2)
                        : const Color(0xFF0F172A),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF8A2BE2)
                            : const Color(0xFF334155)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(m,
                      style: TextStyle(
                          color: selected ? Colors.white : Colors.white38,
                          fontSize: 12)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('Max Runtime: ',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              Text('${_maxRuntimeMins} min',
                  style: const TextStyle(
                      color: Color(0xFF8A2BE2), fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: _maxRuntimeMins.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            activeColor: const Color(0xFF8A2BE2),
            inactiveColor: const Color(0xFF1E293B),
            onChanged: (v) => setState(() => _maxRuntimeMins = v.round()),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A2BE2),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _startExperiment,
              icon: const Icon(Icons.rocket_launch, color: Colors.white),
              label: const Text('Launch G Mode Experiment',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$value ',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          TextSpan(
              text: label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RUNNING':
        return const Color(0xFF00F0FF);
      case 'PAUSED':
        return const Color(0xFFFFA500);
      case 'COMPLETED':
        return const Color(0xFF00FF88);
      case 'FAILED':
      case 'CANCELLED':
        return const Color(0xFFFF4444);
      default:
        return Colors.white38;
    }
  }
}
