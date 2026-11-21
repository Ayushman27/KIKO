/// Ollama service for KIKO Flutter app.
/// Checks Ollama health, lists available models, and provides connection status
/// for display in the Alpha Mode status bar and G Mode settings.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class OllamaStatus {
  final bool online;
  final bool modelAvailable;
  final String configuredModel;
  final List<String> availableModels;
  final String? error;

  const OllamaStatus({
    required this.online,
    required this.modelAvailable,
    required this.configuredModel,
    this.availableModels = const [],
    this.error,
  });

  factory OllamaStatus.offline(String error) => OllamaStatus(
        online: false,
        modelAvailable: false,
        configuredModel: 'qwen3:4b',
        error: error,
      );

  String get statusLabel {
    if (!online) return 'Ollama Offline';
    if (!modelAvailable) return 'Model Not Found';
    return 'qwen3:4b Ready';
  }

  String get statusIcon {
    if (!online) return '🔴';
    if (!modelAvailable) return '🟡';
    return '🟢';
  }
}

class OllamaService {
  static OllamaService? _instance;
  OllamaService._();
  static OllamaService get instance => _instance ??= OllamaService._();

  OllamaStatus? _lastStatus;
  OllamaStatus? get lastStatus => _lastStatus;

  Future<OllamaStatus> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/ollama/health'))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final status = OllamaStatus(
          online: data['online'] ?? false,
          modelAvailable: data['model_available'] ?? false,
          configuredModel: data['configured_model'] ?? 'qwen3:4b',
          availableModels: List<String>.from(data['available_models'] ?? []),
          error: data['error'],
        );
        _lastStatus = status;
        return status;
      }
      final s = OllamaStatus.offline('Backend returned HTTP ${res.statusCode}');
      _lastStatus = s;
      return s;
    } catch (e) {
      final s = OllamaStatus.offline(e.toString());
      _lastStatus = s;
      return s;
    }
  }

  Future<List<String>> listModels() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/v1/ollama/models'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final models = data['models'] as List;
        return models.map((m) => m['name'].toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>> testChat() async {
    try {
      final res = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/v1/ollama/test'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
    return {'success': false, 'error': 'No response'};
  }
}
