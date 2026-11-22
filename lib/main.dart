import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/mqtt_providers.dart';
import 'data/mqtt_service.dart';
import 'data/appliance_providers.dart';
import 'data/repositories/appliance_repository.dart';
import 'data/alert_providers.dart';
import 'data/repositories/alert_repository.dart';
import 'data/db.dart';
import 'data/monitor_providers.dart';
import 'data/nilm_providers.dart';
import 'data/repositories/nilm_repository.dart';
import 'data/repositories/power_history_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'services/alert_monitor.dart';
import 'services/alert_notification_service.dart';
import 'services/background_monitoring_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundMonitoringService.initialize();
  final preferences = await SharedPreferences.getInstance();
  final settingsRepository = SettingsRepository(preferences);
  final applianceRepository = ApplianceRepository(preferences);
  final powerDatabase = await openPowerDatabase();
  final powerHistoryRepository = PowerHistoryRepository(powerDatabase);
  final alertRepository = AlertRepository(powerDatabase);
  final nilmRepository = NilmRepository(powerDatabase, applianceRepository);
  await nilmRepository.initialize();
  final notificationService = AlertNotificationService(
    FlutterLocalNotificationsPlugin(),
  );
  await notificationService.initialize();
  final settings = settingsRepository.load();
  final mqttService = MqttService(
    settingsRepository: settingsRepository,
    settings: settings,
  );
  final alertMonitor = AlertMonitor(
    mqttService: mqttService,
    alertRepository: alertRepository,
    notifier: notificationService,
    settingsRepository: settingsRepository,
    applianceRepository: applianceRepository,
    nilmRepository: nilmRepository,
  );
  final backgroundMonitoringService = BackgroundMonitoringService(
    settingsRepository,
  );

  runApp(
    ProviderScope(
      overrides: [
        mqttServiceProvider.overrideWithValue(mqttService),
        alertRepositoryProvider.overrideWithValue(alertRepository),
        alertNotifierProvider.overrideWithValue(notificationService),
        alertMonitorProvider.overrideWithValue(alertMonitor),
        backgroundMonitoringProvider.overrideWithValue(
          backgroundMonitoringService,
        ),
        applianceRepositoryProvider.overrideWithValue(applianceRepository),
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        powerHistoryRepositoryProvider.overrideWithValue(
          powerHistoryRepository,
        ),
        nilmRepositoryProvider.overrideWithValue(nilmRepository),
      ],
      child: const GharApp(),
    ),
  );

  if (settings.host.trim().isNotEmpty) {
    unawaited(mqttService.connect());
  }
}
