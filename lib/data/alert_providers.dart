import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/alert_record.dart';
import '../services/alert_notification_service.dart';
import '../services/alert_monitor.dart';
import '../services/background_monitoring_service.dart';
import 'repositories/alert_repository.dart';

final alertRepositoryProvider = Provider<AlertRepository>((ref) {
  throw StateError('AlertRepository must be provided at the app root.');
});

final alertNotifierProvider = Provider<AlertNotifier>((ref) {
  throw StateError('AlertNotifier must be provided at the app root.');
});

final alertMonitorProvider = Provider<AlertMonitor>((ref) {
  throw StateError('AlertMonitor must be provided at the app root.');
});

final backgroundMonitoringProvider = Provider<BackgroundMonitoringController>(
  (ref) {
    throw StateError(
      'BackgroundMonitoringController must be provided at the app root.',
    );
  },
);

final alertHistoryProvider = FutureProvider<List<AlertRecord>>((ref) {
  return ref.watch(alertRepositoryProvider).loadHistory();
});

final activeGasAlertProvider = FutureProvider<AlertRecord?>((ref) {
  return ref.watch(alertRepositoryProvider).loadActiveGasAlert();
});
