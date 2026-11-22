import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/mqtt_providers.dart';
import 'data/mqtt_service.dart';
import 'data/appliance_providers.dart';
import 'data/repositories/appliance_repository.dart';
import 'data/db.dart';
import 'data/monitor_providers.dart';
import 'data/repositories/power_history_repository.dart';
import 'data/repositories/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final settingsRepository = SettingsRepository(preferences);
  final applianceRepository = ApplianceRepository(preferences);
  final powerDatabase = await openPowerDatabase();
  final powerHistoryRepository = PowerHistoryRepository(powerDatabase);
  final settings = settingsRepository.load();
  final mqttService = MqttService(
    settingsRepository: settingsRepository,
    settings: settings,
  );

  runApp(
    ProviderScope(
      overrides: [
        mqttServiceProvider.overrideWithValue(mqttService),
        applianceRepositoryProvider.overrideWithValue(applianceRepository),
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        powerHistoryRepositoryProvider.overrideWithValue(
          powerHistoryRepository,
        ),
      ],
      child: const GharApp(),
    ),
  );

  if (settings.host.trim().isNotEmpty) {
    unawaited(mqttService.connect());
  }
}
