import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'websocket_service.dart';

@pragma('vm:entry-point')
class BackgroundAgentService {
  static const String notificationChannelId = 'kiko_bg_agent_channel';
  static const int notificationId = 888;

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'KIKO Mobile AI Agent Service',
      description: 'Persistent background connection for KIKO AI Agent',
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'KIKO AI Agent',
        initialNotificationContent: 'AI Agent is running in background.',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    await service.startService();
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });

      service.on('stopService').listen((event) {
        service.stopSelf();
      });
    }

    // Connect WebSocketService in the background isolate
    print('[BG_AGENT] Initializing persistent background WebSocket connection...');
    WebSocketService.instance.connect();

    // Periodic heartbeat & status check
    Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!WebSocketService.instance.isConnected) {
        print('[BG_AGENT] Reconnecting background WebSocket...');
        WebSocketService.instance.connect();
      }

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: "KIKO AI Agent",
            content: WebSocketService.instance.isConnected
                ? "AI Agent is ONLINE • Standing by for commands"
                : "AI Agent is reconnecting to backend...",
          );
        }
      }
    });
  }
}
