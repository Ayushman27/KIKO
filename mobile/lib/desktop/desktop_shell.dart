/// KIKO Desktop Shell
/// The persistent outer frame of the Windows desktop app.
/// Left rail: mode selector + navigation.
/// Right area: current screen content.
/// Top bar: connection status, Ollama badge, mode pill.
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../config/api_config.dart';
import '../config/app_settings.dart';
import '../config/kiko_theme.dart';
import '../services/websocket_service.dart';
import '../services/ollama_service.dart';

// Screens
import '../screens/chat_screen.dart';
import '../screens/tasks_screen.dart';
import '../screens/devices_screen.dart';
import '../screens/memory_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/approvals_screen.dart';
import '../screens/gmode_screen.dart';
import 'sessions_panel.dart';
import '../widgets/synapse/synapse_dual_mode_screen.dart';
import '../widgets/synapse/synapse_theme.dart';

enum NavPage {
  workspace,
  chat,
  sessions,
  tasks,
  devices,
  memory,
  approvals,
  gmode,
  settings,
}

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> with WindowListener {
  NavPage _currentPage = NavPage.workspace;
  bool _sidebarExpanded = true;
  bool _backendOnline = false;
  bool _isMaximized = false;
  OllamaStatus? _ollamaStatus;
  int _pendingApprovals = 0;
  int _runningExperiments = 0;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((val) {
      if (mounted) setState(() => _isMaximized = val);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final isMax = await windowManager.isMaximized();
        if (!isMax) {
          await windowManager.maximize();
          if (mounted) setState(() => _isMaximized = true);
        }
      } catch (_) {}
    });
    WebSocketService.instance.connect();
    _pollStatus();
    _statusTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pollStatus());
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  // ─── Polling ──────────────────────────────────────────────────────────────

  Future<void> _pollStatus() async {
    // Backend health
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/'))
          .timeout(const Duration(seconds: 4));
      if (mounted) setState(() => _backendOnline = res.statusCode == 200);
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    }

    // Ollama health
    final ollama = await OllamaService.instance.checkHealth();
    if (mounted) setState(() => _ollamaStatus = ollama);

    // Pending approvals
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/approvals'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final list = jsonDecode(res.body) as List;
        setState(() => _pendingApprovals = list.length);
      }
    } catch (_) {}

    // Running G experiments
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/gmode/status'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _runningExperiments = data['running_experiments'] ?? 0);
      }
    } catch (_) {}
  }

  // ─── Window lifecycle ─────────────────────────────────────────────────────

  @override
  void onWindowClose() async {
    bool prevent = false;
    if (_runningExperiments > 0) {
      prevent = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: KikoColors.bg1,
              title: const Text('G Mode Running',
                  style: TextStyle(color: KikoColors.warning)),
              content: Text(
                '$_runningExperiments G Mode experiment(s) are still running in the backend.\n'
                'They will continue running. Close anyway?',
                style: const TextStyle(color: KikoColors.textSecondary),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Close App')),
              ],
            ),
          ) ??
          false;
    }
    if (!prevent) await windowManager.destroy();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyW):
            _NavIntent(NavPage.workspace),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            _NavIntent(NavPage.chat),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyT):
            _NavIntent(NavPage.tasks),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyG):
            _NavIntent(NavPage.gmode),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.comma):
            _NavIntent(NavPage.settings),
      },
      child: Actions(
        actions: {
          _NavIntent: CallbackAction<_NavIntent>(
            onInvoke: (intent) =>
                setState(() => _currentPage = intent.page),
          ),
        },
        child: Scaffold(
          backgroundColor: KikoColors.bg0,
          body: Row(
            children: [
              // ── Sidebar ────────────────────────────────────────────────────
              _buildSidebar(settings),
              const VerticalDivider(width: 1),
              // ── Main content ───────────────────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(settings),
                    Expanded(child: _buildCurrentPage()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(AppSettings settings) {
    final isGMode = settings.isGMode;
    final accent = isGMode ? SynapseTokens.gPrimaryContainer : SynapseTokens.alphaPrimaryContainer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _sidebarExpanded ? 245 : 64,
      color: SynapseTokens.surfaceLowest,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Synapse OS Header & Collapse toggle
          DragToMoveArea(
            child: Container(
              height: 60,
              padding: EdgeInsets.symmetric(horizontal: _sidebarExpanded ? 14 : 0),
              child: _sidebarExpanded
                  ? Row(
                      children: [
                        // Glowing Pulse Dot
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            boxShadow: [
                              BoxShadow(
                                color: accent,
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'SYNAPSE // OS',
                          style: TextStyle(
                            color: SynapseTokens.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: SynapseTokens.surfaceHigh,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'v4.8',
                            style: TextStyle(
                              color: SynapseTokens.outline,
                              fontSize: 10,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_left,
                            size: 18,
                          ),
                          color: SynapseTokens.outline,
                          onPressed: () =>
                              setState(() => _sidebarExpanded = !_sidebarExpanded),
                          tooltip: 'Collapse',
                        ),
                      ],
                    )
                  : Center(
                      child: IconButton(
                        icon: const Icon(
                          Icons.chevron_right,
                          size: 18,
                        ),
                        color: SynapseTokens.outline,
                        onPressed: () =>
                            setState(() => _sidebarExpanded = !_sidebarExpanded),
                        tooltip: 'Expand',
                      ),
                    ),
            ),
          ),

          const Divider(height: 1, color: Color(0x1AFFFFFF)),

          // Mode Selector
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: _sidebarExpanded
                ? _buildExpandedModeSelector(settings)
                : Center(child: _buildCollapsedModeIcon(settings)),
          ),

          const Divider(height: 1, color: Color(0x1AFFFFFF)),
          const SizedBox(height: 6),

          // Navigation items
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _navItem(NavPage.workspace, Icons.psychology, 'Neural Workspace',
                      shortcut: 'Ctrl+W', highlight: true),
                  _navItem(NavPage.chat, Icons.forum, 'Conversations',
                      shortcut: 'Ctrl+K'),
                  _navItem(NavPage.gmode, Icons.science, 'Models & Weights',
                      shortcut: 'Ctrl+G',
                      badge: _runningExperiments > 0
                          ? '$_runningExperiments'
                          : null,
                      highlight: isGMode),
                  _navItem(NavPage.tasks, Icons.task_alt, 'Tasks Stream',
                      shortcut: 'Ctrl+T'),
                  _navItem(NavPage.devices, Icons.devices, 'Connected Devices'),
                  _navItem(NavPage.memory, Icons.memory, 'Memories'),
                  if (_pendingApprovals > 0)
                    _navItem(NavPage.approvals, Icons.approval, 'Approvals',
                        badge: '$_pendingApprovals'),
                  _navItem(NavPage.sessions, Icons.history, 'Sessions History'),
                  _navItem(NavPage.settings, Icons.tune, 'Settings',
                      shortcut: 'Ctrl+,'),

                  // Chat Sessions Section (if expanded)
                  if (_sidebarExpanded) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0x1AFFFFFF)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'CHAT SESSIONS',
                            style: TextStyle(
                              color: SynapseTokens.outline,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            'SYS.SYNC // OK',
                            style: TextStyle(
                              color: accent,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    _sessionItem('Quantum Cognitive Mapping', 'ACTIVE • 4m ago'),
                    _sessionItem('Neural Architecture Review', 'CHECKPOINT • 1h ago'),
                    _sessionItem('Real-time Voice Synthesis', 'STREAM // 48kHz • 3h ago'),
                    _sessionItem('Autonomous Agent Protocol', 'DEPLOYED • 1d ago'),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Operator 01 Profile Card
          if (_sidebarExpanded)
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SynapseTokens.surfaceLow.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: accent,
                        child: Icon(Icons.person, size: 18, color: isGMode ? Colors.white : Colors.black),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            border: Border.all(color: SynapseTokens.surfaceLowest, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Operator 01',
                          style: TextStyle(
                            color: SynapseTokens.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          isGMode ? 'G-Mode Neural Link' : 'Alpha Neural Link',
                          style: const TextStyle(
                            color: SynapseTokens.outline,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_vert, size: 16, color: SynapseTokens.outline),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionItem(String title, String status) {
    return InkWell(
      onTap: () => setState(() => _currentPage = NavPage.chat),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SynapseTokens.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              style: const TextStyle(
                color: SynapseTokens.outline,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedModeSelector(AppSettings settings) {
    final isAlpha = !settings.isGMode;
    return Container(
      decoration: BoxDecoration(
        color: KikoColors.bg2,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => settings.setAgentMode('alpha'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isAlpha ? KikoColors.cyan : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'ALPHA',
                    style: TextStyle(
                        color: isAlpha ? KikoColors.bg0 : KikoColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => settings.setAgentMode('g_mode'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: !isAlpha ? KikoColors.purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'G MODE',
                    style: TextStyle(
                        color: !isAlpha ? Colors.white : KikoColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedModeIcon(AppSettings settings) {
    return GestureDetector(
      onTap: () => settings.setAgentMode(settings.isGMode ? 'alpha' : 'g_mode'),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: settings.isGMode ? KikoColors.purple : KikoColors.cyan,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            settings.isGMode ? 'G' : 'A',
            style: TextStyle(
                color: settings.isGMode ? Colors.white : KikoColors.bg0,
                fontWeight: FontWeight.w900,
                fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _navItem(NavPage page, IconData icon, String label,
      {String? badge, String? shortcut, bool highlight = false}) {
    final selected = _currentPage == page;
    final color = selected
        ? KikoColors.cyan
        : highlight
            ? KikoColors.purple
            : KikoColors.textSecondary;

    return Tooltip(
      message: _sidebarExpanded ? (shortcut ?? '') : '$label${shortcut != null ? ' ($shortcut)' : ''}',
      child: InkWell(
        onTap: () => setState(() => _currentPage = page),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: EdgeInsets.symmetric(
              horizontal: _sidebarExpanded ? 10 : 0, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: _sidebarExpanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 20, color: color),
                  if (badge != null)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: KikoColors.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(badge,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
              if (_sidebarExpanded) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.normal),
                  ),
                ),
                if (shortcut != null)
                  Text(shortcut,
                      style: const TextStyle(
                          color: KikoColors.textMuted, fontSize: 9)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppSettings settings) {
    final isGMode = settings.isGMode;
    final accent = isGMode ? SynapseTokens.gPrimaryContainer : SynapseTokens.alphaPrimaryContainer;

    return DragToMoveArea(
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: SynapseTokens.surfaceLowest.withOpacity(0.98),
          border: const Border(
            bottom: BorderSide(color: Color(0x14FFFFFF), width: 1),
          ),
        ),
        padding: const EdgeInsets.only(left: 16, right: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showTelemetry = constraints.maxWidth > 950;
            final showAudioBadge = constraints.maxWidth > 780;
            final showProfile = constraints.maxWidth > 650;

            return Row(
              children: [
                // Page title (flexible, truncates cleanly without causing overflow)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _pageTitle(_currentPage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SynapseTokens.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      if (showTelemetry) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: SynapseTokens.surfaceContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '14ms STEREO • 3.2 TFLOPS',
                                style: TextStyle(
                                  color: SynapseTokens.outline,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Draggable empty space in middle
                const Spacer(),

                // Right Controls Section: Badges + Divider + Window Controls
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showAudioBadge) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SynapseTokens.surfaceLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mic, color: accent, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'AUDIO ON',
                              style: TextStyle(
                                color: accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Mode pill
                    _modePill(settings),
                    const SizedBox(width: 8),

                    // Backend badge
                    _backendBadge(),

                    if (showProfile) ...[
                      const SizedBox(width: 10),
                      CircleAvatar(
                        radius: 13,
                        backgroundColor: accent,
                        child: Icon(Icons.person, size: 15, color: isGMode ? Colors.white : Colors.black),
                      ),
                    ],

                    const SizedBox(width: 12),

                    // Vertical Divider before Window Controls
                    Container(
                      height: 18,
                      width: 1,
                      color: Colors.white.withOpacity(0.15),
                    ),

                    const SizedBox(width: 6),

                    // Window Controls: Minimize, Maximize/Restore, Close
                    _buildWindowControls(),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWindowControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minimize Button (_)
        _windowActionButton(
          icon: Icons.remove,
          tooltip: 'Minimize',
          iconSize: 15,
          onTap: () async {
            await windowManager.minimize();
          },
        ),
        const SizedBox(width: 3),
        // Maximize / Restore Button (□ / ❐)
        _windowActionButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          tooltip: _isMaximized ? 'Restore Down' : 'Maximize',
          iconSize: _isMaximized ? 12 : 14,
          onTap: () async {
            final isMax = await windowManager.isMaximized();
            if (isMax) {
              await windowManager.unmaximize();
              if (mounted) setState(() => _isMaximized = false);
            } else {
              await windowManager.maximize();
              if (mounted) setState(() => _isMaximized = true);
            }
          },
        ),
        const SizedBox(width: 3),
        // Close Button (✕)
        _windowActionButton(
          icon: Icons.close,
          tooltip: 'Close Window',
          iconSize: 15,
          isClose: true,
          onTap: () async {
            await windowManager.close();
          },
        ),
      ],
    );
  }

  Widget _windowActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double iconSize = 14,
    bool isClose = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: isClose
              ? const Color(0xFFE81123)
              : Colors.white.withOpacity(0.15),
          child: Container(
            width: 32,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isClose
                  ? const Color(0xFFE81123).withOpacity(0.12)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isClose
                    ? const Color(0xFFE81123).withOpacity(0.4)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: isClose ? const Color(0xFFFF6E6E) : SynapseTokens.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _modePill(AppSettings settings) {
    final isG = settings.isGMode;
    return GestureDetector(
      onTap: () =>
          settings.setAgentMode(isG ? 'alpha' : 'g_mode'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (isG ? KikoColors.purple : KikoColors.cyan).withOpacity(0.12),
          border: Border.all(
              color: (isG ? KikoColors.purple : KikoColors.cyan).withOpacity(0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          isG ? '🔬 G MODE' : '⚡ ALPHA',
          style: TextStyle(
              color: isG ? KikoColors.purple : KikoColors.cyan,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1),
        ),
      ),
    );
  }

  Widget _ollamaBadge() {
    if (_ollamaStatus == null) {
      return _badge('Ollama...', KikoColors.textMuted);
    }
    final color = _ollamaStatus!.online
        ? (_ollamaStatus!.modelAvailable ? KikoColors.success : KikoColors.warning)
        : KikoColors.error;
    final modelName = _ollamaStatus!.configuredModel.isNotEmpty
        ? _ollamaStatus!.configuredModel
        : 'qwen3:4b';
    return Tooltip(
      message: _ollamaStatus!.online
          ? (_ollamaStatus!.modelAvailable
              ? '$modelName ready at ${AppSettings.instance.ollamaUrl}'
              : 'Ollama online but $modelName not found. Available: ${_ollamaStatus!.availableModels.join(", ")}')
          : 'Ollama offline. Run: ollama serve',
      child: _badge(
        _ollamaStatus!.online
            ? (_ollamaStatus!.modelAvailable ? '🟢 $modelName' : '🟡 Model missing')
            : '🔴 Ollama',
        color,
      ),
    );
  }

  Widget _backendBadge() {
    return Tooltip(
      message: _backendOnline
          ? 'Backend: ${ApiConfig.baseUrl}'
          : 'Backend offline: ${ApiConfig.baseUrl}',
      child: _badge(
        _backendOnline ? '● Backend' : '○ Backend',
        _backendOnline ? KikoColors.success : KikoColors.error,
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _buildCurrentPage() {
    switch (_currentPage) {
      case NavPage.workspace:
        return const SynapseDualModeScreen(isDesktop: true);
      case NavPage.chat:
        return const ChatScreen();
      case NavPage.sessions:
        return const SessionsPanel();
      case NavPage.tasks:
        return const TasksScreen();
      case NavPage.devices:
        return const DevicesScreen();
      case NavPage.memory:
        return const MemoryScreen();
      case NavPage.approvals:
        return const ApprovalsScreen();
      case NavPage.gmode:
        return const GModeScreen();
      case NavPage.settings:
        return const SettingsScreen();
    }
  }

  String _pageTitle(NavPage page) {
    switch (page) {
      case NavPage.workspace:
        return 'Synapse // OS — Neural Workspace';
      case NavPage.chat:
        return 'Conversations';
      case NavPage.sessions:
        return 'Conversation History';
      case NavPage.tasks:
        return 'Task Stream';
      case NavPage.devices:
        return 'Connected Devices';
      case NavPage.memory:
        return 'Personal Memory';
      case NavPage.approvals:
        return 'Pending Approvals';
      case NavPage.gmode:
        return 'Models & Weights — G Mode';
      case NavPage.settings:
        return 'Settings';
    }
  }
}

// ─── Keyboard shortcut intent ─────────────────────────────────────────────────

class _NavIntent extends Intent {
  final NavPage page;
  const _NavIntent(this.page);
}
