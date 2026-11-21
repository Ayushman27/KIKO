import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../config/api_config.dart';

class WebSocketService {
  static final WebSocketService instance = WebSocketService();

  String? _customServerUrl;
  String get serverUrl => _customServerUrl ?? ApiConfig.wsUrl;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final List<Function(Map<String, dynamic>)> _listeners = [];
  final StreamController<dynamic> _messageStreamController = StreamController<dynamic>.broadcast();

  Stream<dynamic> get messageStream => _messageStreamController.stream;

  WebSocketService({String? serverUrl, Function(Map<String, dynamic>)? onMessageReceived})
      : _customServerUrl = serverUrl {
    if (onMessageReceived != null) {
      _listeners.add(onMessageReceived);
    }
  }

  void reconnect([String? newUrl]) {
    if (newUrl != null) _customServerUrl = newUrl;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _isConnected = false;
    _stopHeartbeat();
    _reconnectDelaySeconds = 1;
    connect();
  }

  void addListener(Function(Map<String, dynamic>) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  void removeListener(Function(Map<String, dynamic>) listener) {
    _listeners.remove(listener);
  }

  bool get isConnected => _isConnected;

  String? _lastExecutedKey;
  DateTime? _lastExecutionTime;
  int _reconnectDelaySeconds = 1;
  Timer? _heartbeatTimer;

  void connect() {
    if (_isConnected) return;
    try {
      print('Connecting Flutter agent to backend WebSocket: $serverUrl');
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _isConnected = true;
      _reconnectDelaySeconds = 1; // Reset backoff on successful connect

      // Send registration payload with platform-appropriate capabilities
      String devId = 'windows_desktop_app';
      String devName = "Ayushman's Windows PC";
      String devType = 'WINDOWS_PC';
      String plat = 'windows';
      List<String> caps = [
        'open_app',
        'run_command',
        'file_operations',
        'browser_control',
        'clipboard_sync',
        'microphone'
      ];

      if (kIsWeb) {
        devId = 'web_browser_client';
        devName = "Ayushman's Laptop (Browser)";
        devType = 'BROWSER';
        plat = 'web';
        caps = ['microphone', 'browser', 'web_agent'];
      } else {
        try {
          if (Platform.isAndroid || Platform.isIOS) {
            devId = 'mobile_app';
            devName = "Ayushman's Phone";
            devType = 'ANDROID_PHONE';
            plat = 'android';
            caps = [
              'open_app',
              'send_notification',
              'clipboard_sync',
              'file_transfer',
              'media_control',
              'battery_status'
            ];
          }
        } catch (_) {}
      }

      _channel!.sink.add(jsonEncode({
        'event': 'DEVICE_CONNECTED',
        'device_id': devId,
        'name': devName,
        'device_type': devType,
        'platform': plat,
        'status': 'ONLINE',
        'connection_type': 'wifi',
        'battery_level': '100%',
        'battery_status': 'Plugged In',
        'capabilities': caps,
      }));

      _startHeartbeat();

      _channel!.stream.listen(
        (data) {
          _messageStreamController.add(data);
          try {
            final Map<String, dynamic> message = jsonDecode(data);
            print('WebSocket received message: $message');

            for (var listener in List.from(_listeners)) {
              listener(message);
            }

            if (message['action'] == 'EXECUTE_TOOL') {
              _handleToolExecution(message);
            }
          } catch (e) {
            print('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _stopHeartbeat();
          _scheduleReconnect();
        },
        onDone: () {
          print('WebSocket connection closed.');
          _isConnected = false;
          _stopHeartbeat();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      print('WebSocket connection error: $e');
      _isConnected = false;
      _stopHeartbeat();
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isConnected && _channel != null) {
        try {
          _channel!.sink.add(jsonEncode({
            'event': 'HEARTBEAT',
            'device_id': ApiConfig.wsClientId,
            'timestamp': DateTime.now().toIso8601String(),
          }));
        } catch (e) {
          print('[WS] Error sending heartbeat: $e');
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    print('[WS] Scheduling reconnect in $_reconnectDelaySeconds seconds...');
    Future.delayed(Duration(seconds: _reconnectDelaySeconds), () {
      if (!_isConnected) {
        connect();
      }
    });
    // Exponential backoff up to 30 seconds max
    _reconnectDelaySeconds = (_reconnectDelaySeconds * 2).clamp(1, 30);
  }

  void reportActionStatus({
    required String taskId,
    required String message,
  }) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode({
          'event': 'ACTION_STATUS',
          'task_id': taskId,
          'device_id': ApiConfig.wsClientId,
          'status': 'EXECUTING',
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
        }));
      } catch (_) {}
    }
  }

  void reportActionResult({
    required String action,
    required bool success,
    String? taskId,
    String? app,
    String? message,
    String? error,
  }) {
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jsonEncode({
          'event': 'ACTION_RESULT',
          'task_id': taskId,
          'device_id': ApiConfig.wsClientId,
          'action': action,
          'success': success,
          'app': app,
          'message': message ?? (success ? 'Successfully executed $action' : 'Failed to execute $action: $error'),
          'error': error,
          'timestamp': DateTime.now().toIso8601String(),
        }));
      } catch (e) {
        print('[WS] Error reporting action result: $e');
      }
    }
  }

  void executeToolDirectly(String toolName, Map<String, dynamic> params) {
    _handleToolExecution({
      'action': 'EXECUTE_TOOL',
      'tool_name': toolName,
      'target': 'mobile',
      'parameters': params,
    });
  }

  Future<void> _executeWindowsTool({
    required String toolName,
    required String? taskId,
    required Map<String, dynamic> params,
  }) async {
    print('[WINDOWS_EXEC] Executing tool: $toolName with params: $params (task: $taskId)');

    if (taskId != null) {
      reportActionStatus(taskId: taskId, message: 'Executing $toolName on Windows PC...');
    }

    if (toolName == 'open_application' ||
        toolName == 'open_app' ||
        toolName == 'launch_app' ||
        toolName == 'open_mobile_app') {
      final rawAppName = (params['app_name'] ?? params['name'] ?? params['app'] ?? '').toString().trim();
      final cleanedName = rawAppName
          .replaceAll(
            RegExp(r'\b(can you|please|kindly|open|launch|start|run|in|on|my|the|a|an|laptop|pc|desktop|computer|windows|device|kiko|koko|coco|cico|co|ko|ki|eco|echo)\b',
                caseSensitive: false),
            ' ',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final targetApp = cleanedName.isNotEmpty ? cleanedName : rawAppName;
      final cleanLower = targetApp.toLowerCase();

      print('[WINDOWS_EXEC] Target app: "$targetApp" (clean: "$cleanLower")');

      String exeOrCmd = targetApp;
      if (cleanLower == 'netflix' || cleanLower.contains('netflix')) {
        exeOrCmd = 'https://www.netflix.com';
      } else if (cleanLower == 'youtube' || cleanLower.contains('youtube')) {
        exeOrCmd = 'https://www.youtube.com';
      } else if (cleanLower == 'amazon' || cleanLower.contains('amazon')) {
        exeOrCmd = 'https://www.amazon.com';
      } else if (cleanLower == 'flipkart' || cleanLower.contains('flipkart')) {
        exeOrCmd = 'https://www.flipkart.com';
      } else if (cleanLower == 'github' || cleanLower.contains('github')) {
        exeOrCmd = 'https://github.com';
      } else if (cleanLower == 'reddit' || cleanLower.contains('reddit')) {
        exeOrCmd = 'https://www.reddit.com';
      } else if (cleanLower == 'twitter' || cleanLower == 'x') {
        exeOrCmd = 'https://x.com';
      } else if (cleanLower.contains('chatgpt') || cleanLower.contains('openai')) {
        exeOrCmd = 'https://chatgpt.com';
      } else if (cleanLower.contains('hotstar') || cleanLower.contains('disney')) {
        exeOrCmd = 'https://www.hotstar.com';
      } else if (cleanLower.contains('prime video') || cleanLower.contains('primevideo')) {
        exeOrCmd = 'https://www.primevideo.com';
      } else if (cleanLower == 'google' || cleanLower == 'google search') {
        exeOrCmd = 'https://www.google.com';
      } else if (cleanLower.contains('notepad')) {
        exeOrCmd = 'notepad.exe';
      } else if (cleanLower.contains('calc')) {
        exeOrCmd = 'calc.exe';
      } else if (cleanLower.contains('paint') || cleanLower.contains('mspaint')) {
        exeOrCmd = 'mspaint.exe';
      } else if (cleanLower.contains('chrome')) {
        exeOrCmd = 'chrome.exe';
      } else if (cleanLower.contains('edge') || cleanLower == 'browser' || cleanLower == 'web browser') {
        exeOrCmd = 'msedge.exe';
      } else if (cleanLower.contains('camera') || cleanLower.contains('cam')) {
        exeOrCmd = 'microsoft.windows.camera:';
      } else if (cleanLower.contains('setting')) {
        exeOrCmd = 'ms-settings:';
      } else if (cleanLower.contains('explorer') || cleanLower.contains('files') || cleanLower == 'file') {
        exeOrCmd = 'explorer.exe';
      } else if (cleanLower.contains('cmd') || cleanLower.contains('command prompt')) {
        exeOrCmd = 'cmd.exe';
      } else if (cleanLower.contains('terminal') || cleanLower.contains('powershell')) {
        exeOrCmd = 'powershell.exe';
      } else if (cleanLower.contains('spotify')) {
        exeOrCmd = 'spotify:';
      } else if (cleanLower.contains('whatsapp')) {
        exeOrCmd = 'whatsapp:';
      } else if (cleanLower.contains('.')) {
        exeOrCmd = 'https://$cleanLower';
      } else {
        // Unknown app or web search fallback to prevent Windows modal "Windows cannot find ..."
        exeOrCmd = 'https://www.google.com/search?q=${Uri.encodeComponent(targetApp)}';
      }

      try {
        print('[WINDOWS_EXEC] Spawning Windows shell process: cmd.exe /c start "" "$exeOrCmd"');
        final res = await Process.run('cmd.exe', ['/c', 'start', '', exeOrCmd]);
        print('[WINDOWS_EXEC] Process.run exitCode: ${res.exitCode}');
        reportActionResult(
          action: toolName,
          success: true,
          taskId: taskId,
          app: targetApp,
          message: 'Successfully opened $targetApp on your Windows PC',
        );
      } catch (e) {
        print('[WINDOWS_EXEC] Failed to launch $exeOrCmd: $e');
        reportActionResult(
          action: toolName,
          success: false,
          taskId: taskId,
          app: targetApp,
          error: e.toString(),
        );
      }
      return;
    }

    if (toolName == 'close_application' || toolName == 'kill_app') {
      final rawAppName = (params['app_name'] ?? params['name'] ?? '').toString().trim();
      var exeName = rawAppName.toLowerCase().replaceAll(RegExp(r'^(close|kill|terminate|stop)\s+', caseSensitive: false), '').trim();
      if (!exeName.endsWith('.exe')) exeName = '$exeName.exe';
      try {
        await Process.run('taskkill', ['/F', '/IM', exeName]);
        reportActionResult(
          action: toolName,
          success: true,
          taskId: taskId,
          app: rawAppName,
          message: 'Closed $rawAppName',
        );
      } catch (e) {
        reportActionResult(
          action: toolName,
          success: false,
          taskId: taskId,
          app: rawAppName,
          error: e.toString(),
        );
      }
      return;
    }

    if (toolName == 'search_youtube' || toolName == 'search_youtube_mobile') {
      final queryRaw = (params['query'] ?? '').toString().trim();
      final ytUrl = queryRaw.isEmpty || queryRaw.toLowerCase() == 'youtube'
          ? 'https://www.youtube.com'
          : 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(queryRaw)}';
      try {
        await Process.run('cmd.exe', ['/c', 'start', '', ytUrl]);
        reportActionResult(
          action: toolName,
          success: true,
          taskId: taskId,
          message: 'Opened YouTube for "$queryRaw"',
        );
      } catch (e) {
        reportActionResult(
          action: toolName,
          success: false,
          taskId: taskId,
          error: e.toString(),
        );
      }
      return;
    }

    if (toolName == 'open_browser' || toolName == 'open_url' || toolName == 'search_web') {
      final rawUrl = (params['url'] ?? '').toString().trim();
      final rawQuery = (params['query'] ?? '').toString().trim();
      String inputStr = rawUrl.isNotEmpty ? rawUrl : (rawQuery.isNotEmpty ? rawQuery : 'https://www.google.com');
      final inputLower = inputStr.toLowerCase();

      String targetUrl = '';
      if (inputLower == 'netflix' || inputLower.contains('netflix')) {
        targetUrl = 'https://www.netflix.com';
      } else if (inputLower == 'youtube' || inputLower.contains('youtube')) {
        targetUrl = 'https://www.youtube.com';
      } else if (inputLower == 'google') {
        targetUrl = 'https://www.google.com';
      } else if (inputLower == 'amazon' || inputLower.contains('amazon')) {
        targetUrl = 'https://www.amazon.com';
      } else if (inputLower == 'flipkart') {
        targetUrl = 'https://www.flipkart.com';
      } else if (inputLower == 'github') {
        targetUrl = 'https://github.com';
      } else if (inputLower == 'reddit') {
        targetUrl = 'https://www.reddit.com';
      } else if (inputLower == 'twitter' || inputLower == 'x') {
        targetUrl = 'https://x.com';
      } else if (inputLower == 'chatgpt' || inputLower.contains('chatgpt')) {
        targetUrl = 'https://chatgpt.com';
      } else if (inputLower == 'hotstar') {
        targetUrl = 'https://www.hotstar.com';
      } else if (inputLower.startsWith('http://') || inputLower.startsWith('https://')) {
        targetUrl = inputStr;
      } else if (inputLower.contains('.')) {
        targetUrl = 'https://$inputStr';
      } else {
        targetUrl = 'https://www.google.com/search?q=${Uri.encodeComponent(inputStr)}';
      }

      try {
        print('[WINDOWS_EXEC] Spawning browser URL: cmd.exe /c start "" "$targetUrl"');
        await Process.run('cmd.exe', ['/c', 'start', '', targetUrl]);
        reportActionResult(
          action: toolName,
          success: true,
          taskId: taskId,
          message: 'Opened browser to $targetUrl',
        );
      } catch (e) {
        reportActionResult(
          action: toolName,
          success: false,
          taskId: taskId,
          error: e.toString(),
        );
      }
      return;
    }

    if (toolName == 'keyboard_type' || toolName == 'type_text') {
      final textToType = (params['text'] ?? params['content'] ?? '').toString();
      final targetApp = (params['app_name'] ?? params['app'] ?? 'notepad').toString();
      final append = params['append_line'] == true;

      try {
        final possiblePythons = [
          r'c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend\venv\Scripts\python.exe',
          r'..\backend\venv\Scripts\python.exe',
          r'backend\venv\Scripts\python.exe',
          'python.exe',
          'python',
        ];
        String pythonExe = possiblePythons.first;
        for (final p in possiblePythons) {
          if (File(p).existsSync()) {
            pythonExe = p;
            break;
          }
        }

        final possibleScripts = [
          r'c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend\app\tools\desktop_type.py',
          r'..\backend\app\tools\desktop_type.py',
          r'backend\app\tools\desktop_type.py',
        ];
        String scriptPath = possibleScripts.first;
        for (final s in possibleScripts) {
          if (File(s).existsSync()) {
            scriptPath = s;
            break;
          }
        }

        final args = [
          scriptPath,
          '--text', textToType,
          '--app', targetApp,
        ];
        if (append) args.add('--append');

        print('[WINDOWS_EXEC] Running typing script: $pythonExe ${args.join(" ")}');
        final res = await Process.run(pythonExe, args);
        print('[WINDOWS_EXEC] Typing exit code: ${res.exitCode}, stdout: ${res.stdout}, stderr: ${res.stderr}');

        reportActionResult(
          action: toolName,
          success: res.exitCode == 0,
          taskId: taskId,
          message: res.exitCode == 0
              ? 'Typed into $targetApp: "$textToType"'
              : 'Failed to type: ${res.stderr}',
        );
      } catch (e) {
        print('[WINDOWS_EXEC] Failed to execute keyboard_type: $e');
        reportActionResult(
          action: toolName,
          success: false,
          taskId: taskId,
          error: e.toString(),
        );
      }
      return;
    }

    if (toolName == 'save_document') {
      final fileName = (params['file_name'] ?? params['name'] ?? 'document.txt').toString();
      final targetApp = (params['app_name'] ?? params['app'] ?? 'notepad').toString();

      try {
        final possiblePythons = [
          r'c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend\venv\Scripts\python.exe',
          r'..\backend\venv\Scripts\python.exe',
          r'backend\venv\Scripts\python.exe',
          'python.exe',
          'python',
        ];
        String pythonExe = possiblePythons.first;
        for (final p in possiblePythons) {
          if (File(p).existsSync()) {
            pythonExe = p;
            break;
          }
        }

        final possibleScripts = [
          r'c:\Users\ayush\OneDrive\Desktop\created-projects\KIKO\backend\app\tools\desktop_type.py',
          r'..\backend\app\tools\desktop_type.py',
          r'backend\app\tools\desktop_type.py',
        ];
        String scriptPath = possibleScripts.first;
        for (final s in possibleScripts) {
          if (File(s).existsSync()) {
            scriptPath = s;
            break;
          }
        }

        final args = [
          scriptPath,
          '--save', fileName,
          '--app', targetApp,
        ];

        print('[WINDOWS_EXEC] Running save script: $pythonExe ${args.join(" ")}');
        final res = await Process.run(pythonExe, args);

        reportActionResult(
          action: toolName,
          success: res.exitCode == 0,
          taskId: taskId,
          message: res.exitCode == 0 ? 'Saved document as $fileName' : 'Failed to save: ${res.stderr}',
        );
      } catch (e) {
        reportActionResult(
          action: toolName,
          success: false,
          taskId: taskId,
          error: e.toString(),
        );
      }
      return;
    }

    // Default Windows tool execution confirmation
    reportActionResult(
      action: toolName,
      success: true,
      taskId: taskId,
      message: 'Executed $toolName on Windows PC',
    );
  }

  void _handleToolExecution(Map<String, dynamic> message) async {
    final toolName = message['tool_name']?.toString() ?? '';
    final target = message['target']?.toString() ?? '';
    final taskId = message['task_id']?.toString();
    final params = message['parameters'] is Map ? message['parameters'] as Map<String, dynamic> : <String, dynamic>{};
    print('Executing tool action: $toolName (target: $target, task_id: $taskId) with params: $params');

    if (kIsWeb) {
      print('[WS] Suppressing action execution on Web client (must execute on native device).');
      return;
    }

    final String execKey = '$toolName:${jsonEncode(params)}';
    final now = DateTime.now();
    if (_lastExecutedKey == execKey && _lastExecutionTime != null && now.difference(_lastExecutionTime!).inSeconds < 3) {
      print('Ignoring duplicate tool execution request within 3 seconds: $execKey');
      return;
    }
    _lastExecutedKey = execKey;
    _lastExecutionTime = now;

    // ── Windows Native Execution ─────────────────────────────────
    if (!kIsWeb && Platform.isWindows) {
      await _executeWindowsTool(
        toolName: toolName,
        taskId: taskId,
        params: params,
      );
      return;
    }

    // ── Android Mobile Execution ─────────────────────────────────
    if (target != 'mobile' && !toolName.contains('mobile')) {
      return;
    }

    if (_channel != null && _isConnected && taskId != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'event': 'ACTION_STATUS',
          'task_id': taskId,
          'device_id': 'mobile_app',
          'status': 'EXECUTING',
          'tool_name': toolName,
          'message': 'Command received by Android Phone. Executing natively...',
          'timestamp': DateTime.now().toIso8601String(),
        }));
      } catch (e) {}
    }

    if (toolName == 'search_youtube_mobile' || toolName == 'search_youtube') {
      final queryRaw = (params['query'] ?? '').toString().trim();
      
      // 1. Android Native Execution
      if (!kIsWeb && Platform.isAndroid) {
        try {
          if (queryRaw.isNotEmpty && queryRaw.toLowerCase() != 'youtube' && queryRaw.toLowerCase() != 'app') {
            final intent = AndroidIntent(
              action: 'action_view',
              data: 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(queryRaw)}',
              flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
            return;
          } else {
            final intent = AndroidIntent(
              action: 'action_main',
              category: 'category_launcher',
              package: 'com.google.android.youtube',
              flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
            return;
          }
        } catch (e) {
          print('AndroidIntent launch failed: $e, falling back to url_launcher');
        }
      }

      // 2. Web Browser & Universal Fallback Execution
      final Uri youtubeUrl = queryRaw.isEmpty || queryRaw.toLowerCase() == 'youtube' || queryRaw.toLowerCase() == 'app'
          ? Uri.parse('https://www.youtube.com')
          : Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(queryRaw)}');

      try {
        if (kIsWeb) {
          final bool launched = await launchUrl(youtubeUrl, webOnlyWindowName: '_blank');
          if (!launched) {
            await launchUrl(youtubeUrl, webOnlyWindowName: '_self');
          }
        } else {
          await launchUrl(youtubeUrl, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        if (kIsWeb) {
          await launchUrl(youtubeUrl, webOnlyWindowName: '_self');
        } else {
          await launchUrl(youtubeUrl, mode: LaunchMode.platformDefault);
        }
      }
    } else if (toolName == 'open_mobile_app' || toolName == 'open_application') {
      var rawAppName = (params['app_name'] ?? '').toString().toLowerCase().trim();
      
      // Aggressively strip leading and trailing noise words ("in my phone", "on my phone", "my phone", "phone", "app", "apps")
      var cleanedName = rawAppName
          .replaceAll(RegExp(r'\b(can you|please|kindly|in|on|my|the|a|an|phone|mobile|laptop|pc|desktop|smartphone|app|apps)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      
      if (cleanedName.isEmpty) {
        cleanedName = rawAppName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      }
      
      var appName = cleanedName;
      final cleanApp = appName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      print('Dynamically launching app (raw: "$rawAppName", cleaned: "$appName", cleanApp: "$cleanApp")');

      if (cleanApp.isEmpty) return;

      final bool isCamera = cleanApp.contains('camera') || cleanApp.contains('cam');

      if (!kIsWeb && Platform.isAndroid) {
        // 1. System Intent Actions (Camera, Phone/Dialer, Settings, etc.)
        if (isCamera) {
          final List<String> cameraActions = [
            'android.media.action.STILL_IMAGE_CAMERA',
            'android.media.action.STILL_IMAGE_CAMERA_SECURE',
            'android.provider.MediaStore.ACTION_IMAGE_CAPTURE',
            'android.media.action.IMAGE_CAPTURE',
          ];
          for (var act in cameraActions) {
            try {
              final intent = AndroidIntent(
                action: act,
                flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
              );
              await intent.launch();
              print('Successfully launched Android Camera intent: $act');
              reportActionResult(action: 'open_mobile_app', success: true, taskId: taskId, app: 'Camera', message: 'Camera launched successfully');
              return;
            } catch (e) {
              print('Camera intent action $act failed: $e');
            }
          }
        } else if (cleanApp == 'dialer' || cleanApp == 'phone' || cleanApp == 'call') {
          try {
            final intent = AndroidIntent(
              action: 'android.intent.action.DIAL',
              flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
            print('Successfully launched Android Dialer intent');
            return;
          } catch (e) {
            print('Dialer intent failed: $e');
          }
        } else if (cleanApp == 'settings') {
          try {
            final intent = AndroidIntent(
              action: 'android.settings.SETTINGS',
              flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
            print('Successfully launched Android Settings intent');
            return;
          } catch (e) {
            print('Settings intent failed: $e');
          }
        }

        // Deep link handlers for major apps (WhatsApp, Instagram, YouTube, Spotify, Slack)
        if (cleanApp == 'slack') {
          for (var slackScheme in ['slack://open', 'slack://']) {
            try {
              final intent = AndroidIntent(
                action: 'action_view',
                data: slackScheme,
                flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
              );
              await intent.launch();
              print('Successfully launched Slack via native AndroidIntent: $slackScheme');
              reportActionResult(action: 'open_mobile_app', success: true, taskId: taskId, app: appName, message: 'Successfully launched $appName natively ($slackScheme)');
              return;
            } catch (e) {
              print('Slack scheme $slackScheme failed: $e');
            }
          }
        }
        if (cleanApp == 'whatsapp' || cleanApp.contains('wa')) {
          for (var waScheme in ['whatsapp://chat', 'whatsapp://send', 'whatsapp://']) {
            try {
              final intent = AndroidIntent(
                action: 'action_view',
                data: waScheme,
                flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
              );
              await intent.launch();
              print('Successfully launched WhatsApp via native AndroidIntent: $waScheme');
              reportActionResult(action: 'open_mobile_app', success: true, taskId: taskId, app: appName, message: 'Successfully launched $appName natively ($waScheme)');
              return;
            } catch (e) {
              print('WhatsApp scheme $waScheme failed: $e');
            }
          }
        }

        // 2. Package candidates for apps (system + standard apps)
        final List<String> packageCandidates = [
          'com.instagram.android',
          'com.whatsapp',
          'com.whatsapp.w4b',
          'com.Slack',
          'com.tinyspeck.chatlyio',
          'com.slack',
          'com.spotify.music',
          'com.facebook.katana',
          'com.linkedin.android',
          'com.twitter.android',
          'com.snapchat.android',
          'com.google.android.youtube',
          'com.android.chrome',
          'com.$cleanApp.android',
          'com.$cleanApp',
          'com.google.android.$cleanApp',
          'org.$cleanApp.messenger',
          'com.facebook.$cleanApp',
        ];

        if (cleanApp == 'slack') {
          packageCandidates.insertAll(0, ['com.Slack', 'com.tinyspeck.chatlyio', 'com.slack', 'com.slack.android']);
        }
        if (cleanApp == 'telegram') {
          packageCandidates.insertAll(0, ['org.telegram.messenger', 'org.telegram.messenger.web']);
        }
        if (cleanApp == 'teams') {
          packageCandidates.insertAll(0, ['com.microsoft.teams']);
        }
        if (cleanApp == 'gmail') {
          packageCandidates.insertAll(0, ['com.google.android.gm']);
        }
        if (cleanApp == 'maps') {
          packageCandidates.insertAll(0, ['com.google.android.apps.maps']);
        }
        if (cleanApp == 'drive') {
          packageCandidates.insertAll(0, ['com.google.android.apps.docs']);
        }

        if (isCamera) {
          packageCandidates.insertAll(0, [
            'com.vivo.alphacamera',
            'com.android.camera',
            'com.vivo.camera',
            'com.iqoo.camera',
            'com.google.android.GoogleCamera',
            'com.sec.android.app.camera',
            'com.oppo.camera',
            'com.coloros.camera',
            'com.oneplus.camera',
            'com.miui.camera',
            'com.transsion.camera',
            'com.android.camera2',
            'com.motorola.camera2',
          ]);
        }
        if (cleanApp == 'photos' || cleanApp == 'gallery') {
          packageCandidates.insertAll(0, [
            'com.google.android.apps.photos',
            'com.sec.android.gallery3d',
            'com.android.gallery3d',
            'com.vivo.gallery',
            'com.oppo.gallery3d',
            'com.miui.gallery',
          ]);
        }
        if (cleanApp == 'calculator') {
          packageCandidates.insertAll(0, [
            'com.google.android.calculator',
            'com.sec.android.app.popupcalculator',
            'com.android.calculator2',
          ]);
        }
        if (cleanApp == 'clock' || cleanApp == 'alarm') {
          packageCandidates.insertAll(0, [
            'com.google.android.deskclock',
            'com.sec.android.app.clockpackage',
            'com.android.deskclock',
          ]);
        }
        if (cleanApp == 'instagram') packageCandidates.insert(0, 'com.instagram.android');
        if (cleanApp == 'whatsapp' || cleanApp.contains('wa')) {
          packageCandidates.insertAll(0, ['com.whatsapp', 'com.whatsapp.w4b']);
        }
        if (cleanApp == 'spotify') packageCandidates.insert(0, 'com.spotify.music');
        if (cleanApp == 'facebook') packageCandidates.insert(0, 'com.facebook.katana');
        if (cleanApp == 'twitter' || cleanApp == 'x') packageCandidates.insert(0, 'com.twitter.android');
        if (cleanApp == 'linkedin') packageCandidates.insert(0, 'com.linkedin.android');
        if (cleanApp == 'snapchat') packageCandidates.insert(0, 'com.snapchat.android');
        if (cleanApp == 'chrome') packageCandidates.insert(0, 'com.android.chrome');
        if (cleanApp == 'youtube') packageCandidates.insert(0, 'com.google.android.youtube');

        for (var pkg in packageCandidates) {
          try {
            final intent = AndroidIntent(
              action: 'action_main',
              category: 'category_launcher',
              package: pkg,
              flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
            print('Successfully launched Android app package with launcher category: $pkg');
            reportActionResult(action: 'open_mobile_app', success: true, taskId: taskId, app: appName, message: 'Successfully launched $appName natively ($pkg)');
            return;
          } catch (e) {
            // Try next
          }

          try {
            final intent = AndroidIntent(
              action: 'action_main',
              package: pkg,
              flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
            );
            await intent.launch();
            print('Successfully launched Android app package: $pkg');
            reportActionResult(action: 'open_mobile_app', success: true, taskId: taskId, app: appName, message: 'Successfully launched $appName natively ($pkg)');
            return;
          } catch (e) {
            // Try next
          }
        }

        // If package candidates loop finishes without launching, report failure
        reportActionResult(
          action: 'open_mobile_app',
          success: false,
          taskId: taskId,
          app: appName,
          error: 'Unable to launch $appName: App package not found or background activity launch restricted by OS'
        );
      }

      // Dynamic URL deep link fallback for any app name
      final Uri dynamicUrl = isCamera
          ? Uri.parse('https://webcamtests.com')
          : (['settings', 'calculator', 'clock', 'alarm', 'phone', 'dialer', 'gallery'].contains(cleanApp)
              ? Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(appName)}')
              : Uri.parse('https://www.$cleanApp.com'));
      try {
        if (kIsWeb) {
          final bool launched = await launchUrl(dynamicUrl, webOnlyWindowName: '_blank');
          if (!launched) {
            await launchUrl(dynamicUrl, webOnlyWindowName: '_self');
          }
        } else {
          await launchUrl(dynamicUrl, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        try {
          if (kIsWeb) {
            await launchUrl(dynamicUrl, webOnlyWindowName: '_self');
          } else {
            await launchUrl(dynamicUrl, mode: LaunchMode.platformDefault);
          }
        } catch (e2) {
          final Uri searchUrl = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(appName)}');
          if (kIsWeb) {
            await launchUrl(searchUrl, webOnlyWindowName: '_blank');
          } else {
            await launchUrl(searchUrl, mode: LaunchMode.externalApplication);
          }
        }
      }
    } else if (toolName == 'open_url_mobile') {
      final urlStr = params['url'] ?? 'https://google.com';
      final Uri url = Uri.parse(urlStr.startsWith('http') ? urlStr : 'https://$urlStr');
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final intent = AndroidIntent(
            action: 'action_view',
            data: url.toString(),
            flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          await intent.launch();
          return;
        } catch (e) {
          print('AndroidIntent URL launch failed: $e');
        }
      }
      try {
        if (kIsWeb) {
          await launchUrl(url, webOnlyWindowName: '_blank');
        } else {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    }
  }

  void sendCommand(String command) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({'event': 'CLIENT_MESSAGE', 'text': command}));
    }
  }

  void dispose() {
    _channel?.sink.close();
  }
}
