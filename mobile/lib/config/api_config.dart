/// Centralised API configuration for KIKO.
/// On Windows desktop (same machine as backend), defaults to localhost:8000.
/// The user can override the backend URL from the Settings screen,
/// which persists it via SharedPreferences.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class ApiConfig {
  // Default: deployed cloud backend on Render. Overridden at runtime by AppSettings.
  static String _scheme = 'https';
  static String _host = 'kiko-891a.onrender.com';
  static int? _port;

  static void setBackendUrl(String host, int port) {
    _host = host;
    _port = port;
    _scheme = (port == 443 || host.contains('.onrender.com') || host.contains('.com')) ? 'https' : 'http';
  }

  static void setFromUrl(String url) {
    try {
      final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
      final uri = Uri.parse(clean);
      if (uri.scheme.isNotEmpty) {
        _scheme = uri.scheme;
      }
      if (uri.host.isNotEmpty) {
        _host = uri.host;
      }
      _port = uri.hasPort ? uri.port : null;
    } catch (_) {}
  }

  static String get scheme => _scheme;
  static String get host => _host;
  static int get port => _port ?? (_scheme == 'https' ? 443 : 80);

  static String get baseUrl {
    final portStr = (_port != null && _port != 80 && _port != 443) ? ':$_port' : '';
    return '$_scheme://$_host$portStr';
  }

  static String get wsScheme => (_scheme == 'https' || _scheme == 'wss') ? 'wss' : 'ws';

  static String get wsBaseUrl {
    final portStr = (_port != null && _port != 80 && _port != 443) ? ':$_port' : '';
    return '$wsScheme://$_host$portStr';
  }

  static String get wsUrl {
    final base = wsBaseUrl;
    if (kIsWeb) return '$base/ws/client/web_browser_client';
    if (!kIsWeb && _isWindows()) {
      return '$base/ws/client/windows_desktop_app';
    }
    return '$base/ws/client/mobile_app';
  }

  static String get wsClientId {
    if (kIsWeb) return 'web_browser_client';
    if (_isWindows()) return 'windows_desktop_app';
    return 'mobile_app';
  }

  static bool _isWindows() {
    try {
      return Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  /// Whether we're running as a Windows desktop app.
  static bool get isDesktop {
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }
}
