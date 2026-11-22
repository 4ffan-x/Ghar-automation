import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/repositories/settings_repository.dart';
import 'ghar_monitoring_task_handler.dart';

abstract interface class BackgroundMonitoringController {
  Future<bool> isRunning();

  Future<void> start();

  Future<void> stop();

  Future<bool> requestBatteryOptimizationExemption();

  Future<bool> openBatteryOptimizationSettings();
}

class BackgroundMonitoringService
    implements BackgroundMonitoringController {
  BackgroundMonitoringService(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  static void initialize() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ghar_background_monitor_v1',
        channelName: 'Ghar background monitoring',
        channelDescription:
            'Keeps the ESP32 connection active for safety alerts.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30 * 1000),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start() async {
    if (_settingsRepository.load().host.trim().isEmpty) {
      throw StateError('Save an MQTT broker address before enabling alerts.');
    }
    if (await isRunning()) {
      return;
    }
    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.remoteMessaging],
      notificationTitle: 'Ghar is monitoring your home',
      notificationText: 'Tap to open the app. Use Stop to end monitoring.',
      notificationButtons: const [
        NotificationButton(id: 'stop', text: 'Stop'),
      ],
      callback: startGharMonitoringService,
    );
    if (result case ServiceRequestFailure(:final error)) {
      throw StateError('Could not start background monitoring: $error');
    }
  }

  @override
  Future<void> stop() async {
    final result = await FlutterForegroundTask.stopService();
    if (result case ServiceRequestFailure(:final error)) {
      throw StateError('Could not stop background monitoring: $error');
    }
  }

  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      return true;
    }
    return FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  @override
  Future<bool> openBatteryOptimizationSettings() =>
      FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
}
