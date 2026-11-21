/// KIKO Windows Desktop Application — Main Entry Point
/// Configures the window, loads settings, and launches the desktop shell.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'config/app_settings.dart';
import 'config/kiko_theme.dart';
import 'services/background_service.dart';
import 'desktop/desktop_shell.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted settings first (backend URL, mode, etc.)
  await AppSettings.instance.load();

  // Windows desktop window configuration
  if (!kIsWeb && _isDesktop()) {
    try {
      await windowManager.ensureInitialized();
      const options = WindowOptions(
        size: Size(1280, 720),
        minimumSize: Size(960, 640),
        center: true,
        title: 'KIKO — Personal AI Agent',
        backgroundColor: Color(0xFF080C14),
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.maximize();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('WindowManager init error: $e');
    }
  }

  // Android background service
  if (!kIsWeb && !_isDesktop()) {
    try {
      await BackgroundAgentService.initializeService();
    } catch (e) {
      debugPrint('Background service init error: $e');
    }
  }

  runApp(
    ChangeNotifierProvider.value(
      value: AppSettings.instance,
      child: const KikoApp(),
    ),
  );
}

bool _isDesktop() {
  try {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}

class KikoApp extends StatelessWidget {
  const KikoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KIKO — Personal AI Agent',
      debugShowCheckedModeBanner: false,
      theme: KikoTheme.dark,
      home: _isDesktop() ? const DesktopShell() : const SplashScreen(),
    );
  }
}
