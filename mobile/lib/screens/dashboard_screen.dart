import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/websocket_service.dart';
import '../services/ollama_service.dart';
import '../config/api_config.dart';
import 'package:provider/provider.dart';
import '../config/app_settings.dart';
import '../widgets/synapse/synapse_dual_mode_screen.dart';
import '../widgets/synapse/synapse_theme.dart';
import 'chat_screen.dart';
import 'voice_screen.dart';
import 'tasks_screen.dart';
import 'approvals_screen.dart';
import 'activity_screen.dart';
import 'memory_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isScanning = false;
  OllamaStatus? _ollamaStatus;

  List<Map<String, dynamic>> _availableDevices = [
    {
      "device_id": "mobile_app",
      "name": "Ayushman's Phone",
      "device_type": "ANDROID_PHONE",
      "platform": "android",
      "connection_type": "Wi-Fi",
      "status": "connected",
      "online": true,
      "paired": true,
      "battery_level": "88%",
      "battery_status": "Discharging",
      "capabilities": ["open_app", "send_notification", "clipboard_sync", "file_transfer", "battery_status"]
    },
    {
      "device_id": "kiko_windows_agent",
      "name": "Ayushman's Laptop",
      "device_type": "WINDOWS_PC",
      "platform": "windows",
      "connection_type": "Wi-Fi",
      "status": "connected",
      "online": true,
      "paired": true,
      "battery_level": "100%",
      "battery_status": "Plugged In",
      "capabilities": ["open_app", "file_operations", "browser_control", "clipboard_sync", "battery_status"]
    }
  ];

  @override
  void initState() {
    super.initState();
    WebSocketService.instance.connect();
    _fetchDevices();
    _checkOllama();
  }

  Future<void> _checkOllama() async {
    final status = await OllamaService.instance.checkHealth();
    if (mounted) setState(() => _ollamaStatus = status);
  }

  Future<void> _fetchDevices() async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/devices'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        if (data.isNotEmpty) {
          setState(() {
            _availableDevices = data.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (e) {
      print('Fetch devices error: $e');
    }
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
    });

    try {
      final res = await http.post(Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/discover'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> found = data['devices'] ?? [];
        if (found.isNotEmpty) {
          setState(() {
            _availableDevices = found.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      }
    } catch (e) {
      print('Scan devices error: $e');
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _showControlModal(Map<String, dynamic> device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    device['device_type'] == 'WINDOWS_PC' ? Icons.laptop : Icons.phone_android,
                    color: const Color(0xFF00F0FF),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device['name'] ?? 'Device',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          "Battery: ${device['battery_level'] ?? '100%'} • ${device['connection_type'] ?? 'Wi-Fi'}",
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text("Control Capabilities", style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildControlActionChip(ctx, device, "Open App", Icons.apps, "open_app"),
                  _buildControlActionChip(ctx, device, "Send Notification", Icons.notifications_active, "send_notification"),
                  _buildControlActionChip(ctx, device, "Send File", Icons.upload_file, "send_file"),
                  _buildControlActionChip(ctx, device, "Clipboard Sync", Icons.content_copy, "clipboard_sync"),
                  _buildControlActionChip(ctx, device, "Media Control", Icons.play_arrow, "media_control"),
                  _buildControlActionChip(ctx, device, "Device Info", Icons.info_outline, "battery_info"),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlActionChip(BuildContext ctx, Map<String, dynamic> dev, String title, IconData icon, String action) {
    return ActionChip(
      avatar: Icon(icon, color: const Color(0xFF00F0FF), size: 16),
      label: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Color(0xFF00F0FF), width: 0.5),
      onPressed: () async {
        Navigator.pop(ctx);
        final devId = dev['device_id'] ?? 'default_device';
        try {
          final res = await http.post(
            Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$devId/control'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': action,
              'parameters': {'triggered_from': 'Mobile App UI'}
            }),
          );
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Action executed'),
                backgroundColor: const Color(0xFF0F172A),
              ),
            );
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trigger action error: $e')),
          );
        }
      },
    );
  }

  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final isGMode = settings.isGMode;
    final accent = SynapseTokens.primaryColor(isGMode);

    return Scaffold(
      backgroundColor: SynapseTokens.substrateVoid,
      body: IndexedStack(
        index: _selectedTab,
        children: [
          const SynapseDualModeScreen(isDesktop: false),
          _buildDevicesTab(isGMode, accent),
          const TasksScreen(),
          const ApprovalsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: SynapseTokens.surfaceLowest.withOpacity(0.96),
          border: Border(
            top: BorderSide(
              color: Colors.white.withOpacity(0.08),
              width: 1.0,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 16,
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedTab,
          onTap: (idx) => setState(() => _selectedTab = idx),
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: accent,
          unselectedItemColor: SynapseTokens.outline,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.psychology),
              activeIcon: Icon(Icons.psychology, size: 26),
              label: 'Synapse AI',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.devices),
              label: 'Devices',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.task_alt),
              label: 'Tasks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.shield_outlined),
              label: 'Approvals',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.tune),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesTab(bool isGMode, Color accent) {
    return Scaffold(
      backgroundColor: SynapseTokens.substrateVoid,
      appBar: AppBar(
        title: Text('DEVICE CONTROLLER // HUB', style: TextStyle(color: accent, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 14, fontFamily: 'monospace')),
        backgroundColor: SynapseTokens.surfaceLowest,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: Colors.amber),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Available Devices Header & Scan Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("AVAILABLE DEVICES", style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2, fontFamily: 'monospace')),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SynapseTokens.surfaceContainer,
                    side: BorderSide(color: accent, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isScanning
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                      : Icon(Icons.search, color: accent, size: 16),
                  label: Text(_isScanning ? "Scanning..." : "🔍 Scan for Devices", style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _isScanning ? null : _scanForDevices,
                )
              ],
            ),
            const SizedBox(height: 12),

            // Discovered / Active Device Cards
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _availableDevices.length,
              itemBuilder: (context, idx) {
                final dev = _availableDevices[idx];
                final isWindows = dev['device_type'] == 'WINDOWS_PC';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isWindows ? const Color(0xFF00F0FF).withOpacity(0.4) : Colors.greenAccent.withOpacity(0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: (isWindows ? const Color(0xFF00F0FF) : Colors.greenAccent).withOpacity(0.08),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(isWindows ? Icons.laptop : Icons.phone_android, color: isWindows ? const Color(0xFF00F0FF) : Colors.greenAccent, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dev['name'] ?? 'KIKO Device', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text("Platform: ${dev['platform'] ?? 'device'} • Battery: ${dev['battery_level'] ?? '100%'}", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Control Device", style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () => _showControlModal(dev),
                          )
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildBadge("Agent: ONLINE", Colors.greenAccent),
                          _buildBadge(dev['connection_type'] ?? "Wi-Fi", Colors.cyanAccent),
                          _buildBadge(dev['paired'] == true ? "PAIRED" : "AVAILABLE", Colors.purpleAccent),
                          _buildBadge(WebSocketService.instance.isConnected ? "WS: CONNECTED" : "WS: CONNECTING...", WebSocketService.instance.isConnected ? Colors.greenAccent : Colors.amberAccent),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Mode Navigation Grid
            const Text("AI Agent Interfaces", style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _buildNavTile(context, "AI Chat", Icons.chat_bubble_outline, const Color(0xFF00F0FF), () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
                }),
                _buildNavTile(context, "Voice Assistant", Icons.mic_none, Colors.purpleAccent, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceScreen()));
                }),
                _buildNavTile(context, "Tasks Stream", Icons.list_alt, Colors.cyan, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen()));
                }),
                _buildNavTile(context, "Approvals", Icons.shield_outlined, Colors.amber, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ApprovalsScreen()));
                }),
                _buildNavTile(context, "Activity Log", Icons.history, Colors.blueAccent, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityScreen()));
                }),
                _buildNavTile(context, "Memory", Icons.psychology, Colors.tealAccent, () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()));
                }),
              ],
            ),

            const SizedBox(height: 24),
            const Text("Quick Commands", style: TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            _buildCommandTile(context, "Show my phone battery", Icons.battery_charging_full),
            _buildCommandTile(context, "Open Notepad on my laptop", Icons.laptop),
            _buildCommandTile(context, "Open Instagram on my phone", Icons.phone_android),
            _buildCommandTile(context, "Send this file to my phone", Icons.send),
            _buildCommandTile(context, "Copy text to my laptop", Icons.content_copy),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandTile(BuildContext context, String title, IconData icon) {
    return Card(
      color: const Color(0xFF0F172A),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00F0FF), size: 20),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
        },
      ),
    );
  }

  static Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
