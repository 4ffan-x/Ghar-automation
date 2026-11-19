import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/mqtt_providers.dart';
import 'data/mqtt_service.dart';
import 'data/appliance_providers.dart';
import 'data/repositories/appliance_repository.dart';
import 'data/repositories/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final settingsRepository = SettingsRepository(preferences);
  final applianceRepository = ApplianceRepository(preferences);
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
      ],
      child: const GharApp(),
    ),
  );

  if (settings.host.trim().isNotEmpty) {
    unawaited(mqttService.connect());
  }
}
