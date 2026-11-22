import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/energy_totals.dart';
import '../domain/models/mqtt_readings.dart';
import 'repositories/power_history_repository.dart';
import 'repositories/settings_repository.dart';

final powerHistoryRepositoryProvider = Provider<PowerHistoryRepository>((ref) {
  throw StateError('PowerHistoryRepository must be provided at the app root.');
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  throw StateError('SettingsRepository must be provided at the app root.');
});

final recentPowerHistoryProvider = FutureProvider<List<PowerReading>>((ref) {
  return ref.watch(powerHistoryRepositoryProvider).getRecentSamples();
});

final energyTotalsProvider = FutureProvider<EnergyTotals>((ref) {
  return ref.watch(powerHistoryRepositoryProvider).getEnergyTotals();
});

final energyTariffProvider = Provider<double>((ref) {
  return ref.watch(settingsRepositoryProvider).loadEnergyTariff();
});
