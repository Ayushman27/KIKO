import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../config/app_settings.dart';
import '../services/websocket_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  String _selectedProvider = 'openai';
  
  final TextEditingController _openaiKeyController = TextEditingController();
  final TextEditingController _openaiModelController = TextEditingController(text: 'gpt-4o');
  
  final TextEditingController _anthropicKeyController = TextEditingController();
  final TextEditingController _anthropicModelController = TextEditingController(text: 'claude-3-5-sonnet-20240620');
  
  final TextEditingController _geminiKeyController = TextEditingController();
  final TextEditingController _geminiModelController = TextEditingController(text: 'gemini-1.5-flash');
  
  final TextEditingController _groqKeyController = TextEditingController();
  final TextEditingController _groqModelController = TextEditingController(text: 'llama-3.1-70b-versatile');
  
  final TextEditingController _ollamaUrlController = TextEditingController(text: 'http://localhost:11434');
  final TextEditingController _ollamaModelController = TextEditingController(text: 'qwen3:4b');

  bool _obscureOpenAI = true;
  bool _obscureAnthropic = true;
  bool _obscureGemini = true;
  bool _obscureGroq = true;

  @override
  void initState() {
    super.initState();
    _fetchLLMSettings();
  }

  @override
  void dispose() {
    _openaiKeyController.dispose();
    _openaiModelController.dispose();
    _anthropicKeyController.dispose();
    _anthropicModelController.dispose();
    _geminiKeyController.dispose();
    _geminiModelController.dispose();
    _groqKeyController.dispose();
    _groqModelController.dispose();
    _ollamaUrlController.dispose();
    _ollamaModelController.dispose();
    super.dispose();
  }

  Future<void> _fetchLLMSettings() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/settings/llm'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _selectedProvider = data['selected_provider'] ?? 'openai';
          _openaiKeyController.text = data['openai_api_key'] ?? '';
          _openaiModelController.text = data['openai_model'] ?? 'gpt-4o';
          _anthropicKeyController.text = data['anthropic_api_key'] ?? '';
          _anthropicModelController.text = data['anthropic_model'] ?? 'claude-3-5-sonnet-20240620';
          _geminiKeyController.text = data['gemini_api_key'] ?? '';
          _geminiModelController.text = data['gemini_model'] ?? 'gemini-1.5-flash';
          _groqKeyController.text = data['groq_api_key'] ?? '';
          _groqModelController.text = data['groq_model'] ?? 'llama-3.1-70b-versatile';
          _ollamaUrlController.text = data['ollama_base_url'] ?? 'http://localhost:11434';
          _ollamaModelController.text = data['ollama_model'] ?? 'qwen3:4b';
        });
      }
    } catch (e) {
      print('Error fetching LLM settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLLMSettings() async {
    setState(() => _isLoading = true);
    try {
      final payload = {
        'selected_provider': _selectedProvider,
        'openai_api_key': _openaiKeyController.text.trim(),
        'openai_model': _openaiModelController.text.trim(),
        'anthropic_api_key': _anthropicKeyController.text.trim(),
        'anthropic_model': _anthropicModelController.text.trim(),
        'gemini_api_key': _geminiKeyController.text.trim(),
        'gemini_model': _geminiModelController.text.trim(),
        'groq_api_key': _groqKeyController.text.trim(),
        'groq_model': _groqModelController.text.trim(),
        'ollama_base_url': _ollamaUrlController.text.trim(),
        'ollama_model': _ollamaModelController.text.trim(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/settings/llm'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('LLM API Keys & Provider Settings Saved Successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openLLMConfigDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Configure LLM & API Keys",
                          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Active Provider Dropdown
                    const Text("Active AI Brain Provider", style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedProvider,
                          dropdownColor: const Color(0xFF1E293B),
                          isExpanded: true,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: const [
                            DropdownMenuItem(value: 'openai', child: Text("⚡ OpenAI (GPT-4o)")),
                            DropdownMenuItem(value: 'anthropic', child: Text("🤖 Anthropic Claude (Claude 3.5)")),
                            DropdownMenuItem(value: 'gemini', child: Text("✨ Google Gemini (1.5 Flash/Pro)")),
                            DropdownMenuItem(value: 'groq', child: Text("🚀 Groq (Llama-3.1 70B)")),
                            DropdownMenuItem(value: 'ollama', child: Text("🦙 Ollama Local LLM")),
                            DropdownMenuItem(value: 'rule', child: Text("🛠️ Rule Engine (Offline Direct)")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => _selectedProvider = val);
                              setState(() => _selectedProvider = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Divider(color: Colors.white10),
                    const Text("Provider API Keys", style: TextStyle(color: Color(0xFF00F0FF), fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),

                    // OpenAI
                    _buildApiKeyField(
                      title: "OpenAI API Key",
                      hint: "sk-...",
                      controller: _openaiKeyController,
                      obscure: _obscureOpenAI,
                      onToggleObscure: () {
                        setModalState(() => _obscureOpenAI = !_obscureOpenAI);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Anthropic Claude
                    _buildApiKeyField(
                      title: "Anthropic Claude API Key",
                      hint: "sk-ant-...",
                      controller: _anthropicKeyController,
                      obscure: _obscureAnthropic,
                      onToggleObscure: () {
                        setModalState(() => _obscureAnthropic = !_obscureAnthropic);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Google Gemini
                    _buildApiKeyField(
                      title: "Google Gemini API Key",
                      hint: "AIzaSy...",
                      controller: _geminiKeyController,
                      obscure: _obscureGemini,
                      onToggleObscure: () {
                        setModalState(() => _obscureGemini = !_obscureGemini);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Groq
                    _buildApiKeyField(
                      title: "Groq API Key",
                      hint: "gsk_...",
                      controller: _groqKeyController,
                      obscure: _obscureGroq,
                      onToggleObscure: () {
                        setModalState(() => _obscureGroq = !_obscureGroq);
                      },
                    ),
                    const SizedBox(height: 10),

                    // Ollama Base URL
                    const Text("Ollama Base URL", style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _ollamaUrlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        hintText: "http://localhost:11434",
                        hintStyle: const TextStyle(color: Colors.white30),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00F0FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _saveLLMSettings();
                        },
                        child: const Text(
                          "Save & Apply LLM Settings",
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildApiKeyField({
    required String title,
    required String hint,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1E293B),
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white54, size: 18),
              onPressed: onToggleObscure,
            ),
          ),
        ),
      ],
    );
  }

  void _openServerConfigDialog() {
    final controller = TextEditingController(text: AppSettings.instance.backendUrl);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lan, color: Color(0xFF00F0FF), size: 22),
              SizedBox(width: 8),
              Text(
                "Backend Server URL",
                style: TextStyle(color: Color(0xFF00F0FF), fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "When running on your phone, point this to your PC's Wi-Fi IP address (port 8000):",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  hintText: "http://192.168.1.11:8000",
                  hintStyle: const TextStyle(color: Colors.white30),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF00F0FF)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Color(0xFF00F0FF), width: 0.5),
                    label: const Text("PC: 192.168.1.11:8000", style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11)),
                    onPressed: () {
                      controller.text = "http://192.168.1.11:8000";
                    },
                  ),
                  ActionChip(
                    backgroundColor: const Color(0xFF1E293B),
                    side: const BorderSide(color: Colors.white24, width: 0.5),
                    label: const Text("Localhost", style: TextStyle(color: Colors.white70, fontSize: 11)),
                    onPressed: () {
                      controller.text = "http://127.0.0.1:8000";
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F0FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final newUrl = controller.text.trim();
                if (newUrl.isNotEmpty) {
                  await AppSettings.instance.setBackendUrl(newUrl);
                  WebSocketService.instance.reconnect(ApiConfig.wsUrl);
                  if (mounted) setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Connected to: ${ApiConfig.baseUrl}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text("Save & Connect", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String providerLabel = 'OpenAI (GPT-4o)';
    if (_selectedProvider == 'anthropic') providerLabel = 'Anthropic Claude';
    if (_selectedProvider == 'gemini') providerLabel = 'Google Gemini';
    if (_selectedProvider == 'groq') providerLabel = 'Groq LLM';
    if (_selectedProvider == 'ollama') providerLabel = 'Ollama Local LLM';
    if (_selectedProvider == 'rule') providerLabel = 'Rule Engine (Offline Direct)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Settings', style: TextStyle(color: Color(0xFF00F0FF))),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Backend Server Connection Setting
                ListTile(
                  leading: const Icon(Icons.lan, color: Color(0xFF00F0FF)),
                  title: const Text("Backend Server URL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    "${AppSettings.instance.backendUrl} (Tap to change PC IP)",
                    style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 12),
                  ),
                  trailing: const Icon(Icons.edit, color: Colors.white54),
                  onTap: _openServerConfigDialog,
                ),
                const Divider(color: Colors.white10),
                const ListTile(
                  leading: Icon(Icons.security, color: Colors.greenAccent),
                  title: Text("High-Risk Action Approvals", style: TextStyle(color: Colors.white)),
                  subtitle: Text("ALWAYS REQUIRED", style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.memory, color: Color(0xFF00F0FF)),
                  title: const Text("AI Brain Provider & API Keys", style: TextStyle(color: Colors.white)),
                  subtitle: Text("Active: $providerLabel (Tap to configure API keys)", style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                  onTap: _openLLMConfigDialog,
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  leading: const Icon(Icons.key, color: Color(0xFF8A2BE2)),
                  title: const Text("LLM Model API Keys", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("OpenAI, Anthropic, Gemini, Groq, Ollama", style: TextStyle(color: Colors.grey, fontSize: 11)),
                  trailing: const Icon(Icons.edit, color: Color(0xFF00F0FF)),
                  onTap: _openLLMConfigDialog,
                ),
                const Divider(color: Colors.white10),
                const ListTile(
                  leading: Icon(Icons.folder_shared, color: Color(0xFF00F0FF)),
                  title: Text("Authorized Folders Scope", style: TextStyle(color: Colors.white)),
                  subtitle: Text("Documents, Downloads, Projects", style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ],
            ),
    );
  }
}
