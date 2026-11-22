import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/mqtt_service.dart';
import '../data/repositories/alert_repository.dart';
import '../data/repositories/appliance_repository.dart';
import '../data/repositories/nilm_repository.dart';
import '../data/repositories/settings_repository.dart';
import 'alert_monitor.dart';
import 'alert_notification_service.dart';

@pragma('vm:entry-point')
void startGharMonitoringService() {
  FlutterForegroundTask.setTaskHandler(GharMonitoringTaskHandler());
}

class GharMonitoringTaskHandler extends TaskHandler {
  AlertRepository? _alertRepository;
  AlertNotificationService? _notifier;
  MqttService? _mqttService;
  AlertMonitor? _alertMonitor;
  Database? _database;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final preferences = await SharedPreferences.getInstance();
    final settingsRepository = SettingsRepository(preferences);
    final applianceRepository = ApplianceRepository(preferences);
    final database = await openPowerDatabase();
    final alertRepository = AlertRepository(database);
    final nilmRepository = NilmRepository(database, applianceRepository);
    await nilmRepository.initialize();
    final notifier = AlertNotificationService(
      FlutterLocalNotificationsPlugin(),
    );
    await notifier.initialize();
    final mqttService = MqttService(
      settingsRepository: settingsRepository,
      settings: settingsRepository.load(),
    );
    final alertMonitor = AlertMonitor(
      mqttService: mqttService,
      alertRepository: alertRepository,
      notifier: notifier,
      settingsRepository: settingsRepository,
      applianceRepository: applianceRepository,
      nilmRepository: nilmRepository,
    );
    _database = database;
    _alertRepository = alertRepository;
    _notifier = notifier;
    _mqttService = mqttService;
    _alertMonitor = alertMonitor;
    await alertMonitor.start();
    if (settingsRepository.load().host.trim().isNotEmpty) {
      await mqttService.connect();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_repeatUnacknowledgedGasAlert());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _alertMonitor?.dispose();
    await _mqttService?.dispose();
    await _database?.close();
    _alertMonitor = null;
    _mqttService = null;
    _database = null;
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') {
      unawaited(FlutterForegroundTask.stopService());
    }
  }

  Future<void> _repeatUnacknowledgedGasAlert() async {
    try {
      final alert = await _alertRepository?.loadActiveGasAlert();
      if (alert != null) {
        await _notifier?.repeatGasAlert(alert);
      }
    } on Exception catch (error, stackTrace) {
      debugPrint('Could not repeat gas alert: $error\n$stackTrace');
    }
  }
}
