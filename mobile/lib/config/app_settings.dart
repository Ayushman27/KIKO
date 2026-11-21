/// App-wide settings persisted via SharedPreferences.
/// Handles: backend URL, agent mode, theme, Ollama config, etc.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class AppSettings extends ChangeNotifier {
  static AppSettings? _instance;
  static AppSettings get instance => _instance ??= AppSettings._();
  AppSettings._();

  // ─── Keys ──────────────────────────────────────────────────────────────────
  static const _kBackendUrl = 'backend_url';
  static const _kAgentMode = 'agent_mode';
  static const _kOllamaUrl = 'ollama_url';
  static const _kOllamaModel = 'ollama_model';
  static const _kTheme = 'theme';

  // ─── Values ────────────────────────────────────────────────────────────────
  String _backendUrl = 'https://kiko-891a.onrender.com';
  String _agentMode = 'alpha'; // 'alpha' | 'g_mode'
  String _ollamaUrl = 'http://localhost:11434';
  String _ollamaModel = 'qwen3:4b';
  String _theme = 'dark';

  String get backendUrl => _backendUrl;
  String get agentMode => _agentMode;
  String get ollamaUrl => _ollamaUrl;
  String get ollamaModel => _ollamaModel;
  String get theme => _theme;
  bool get isGMode => _agentMode == 'g_mode';

  /// Load all settings from disk. Call once at app startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString(_kBackendUrl) ?? 'https://kiko-891a.onrender.com';
    _agentMode = prefs.getString(_kAgentMode) ?? 'alpha';
    _ollamaUrl = prefs.getString(_kOllamaUrl) ?? 'http://localhost:11434';
    _ollamaModel = prefs.getString(_kOllamaModel) ?? 'qwen3:4b';
    _theme = prefs.getString(_kTheme) ?? 'dark';
    // Propagate to ApiConfig
    ApiConfig.setFromUrl(_backendUrl);
    notifyListeners();
  }

  Future<void> setBackendUrl(String url) async {
    _backendUrl = url.trimRight().replaceAll(RegExp(r'/$'), '');
    ApiConfig.setFromUrl(_backendUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackendUrl, _backendUrl);
    notifyListeners();
  }

  Future<void> setAgentMode(String mode) async {
    _agentMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAgentMode, mode);
    notifyListeners();
  }

  Future<void> setOllamaUrl(String url) async {
    _ollamaUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOllamaUrl, url);
    notifyListeners();
  }

  Future<void> setOllamaModel(String model) async {
    _ollamaModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOllamaModel, model);
    notifyListeners();
  }
}
