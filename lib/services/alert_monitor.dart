import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mqtt_service.dart';
import '../data/repositories/alert_repository.dart';
import '../data/repositories/appliance_repository.dart';
import '../data/repositories/nilm_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/models/alert_record.dart';
import '../domain/models/mqtt_readings.dart';
import 'alert_notification_service.dart';

class AlertMonitor {
  AlertMonitor({
    required MqttService mqttService,
    required AlertRepository alertRepository,
    required AlertNotifier notifier,
    required SettingsRepository settingsRepository,
    required ApplianceRepository applianceRepository,
    required NilmRepository nilmRepository,
  }) : _mqttService = mqttService,
       _alertRepository = alertRepository,
       _notifier = notifier,
       _settingsRepository = settingsRepository,
       _applianceRepository = applianceRepository,
       _nilmRepository = nilmRepository;

  static const _heavyUseCheckInterval = Duration(seconds: 15);

  final MqttService _mqttService;
  final AlertRepository _alertRepository;
  final AlertNotifier _notifier;
  final SettingsRepository _settingsRepository;
  final ApplianceRepository _applianceRepository;
  final NilmRepository _nilmRepository;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _heavyUseTimer;
  bool _started = false;
  void Function()? onAlertsChanged;

  Future<void> start({void Function()? onAlertsChanged}) async {
    if (_started) {
      return;
    }
    _started = true;
    this.onAlertsChanged = onAlertsChanged;
    _subscriptions
      ..add(
        _mqttService.gasStatuses.listen(
          (status) => _run(() => _handleGasStatus(status)),
          onError: _logStreamError('gas'),
        ),
      )
      ..add(
        _mqttService.deviceStatusStream.listen(
          (online) => _run(() => _handleDeviceStatus(online)),
          onError: _logStreamError('device status'),
        ),
      )
      ..add(
        _mqttService.powerReadings.listen(
          (reading) => _run(() => _handlePowerReading(reading)),
          onError: _logStreamError('power'),
        ),
      )
      ..add(
        _mqttService.relayStateUpdates.listen(
          (states) => _run(() => _handleRelayStates(states)),
          onError: _logStreamError('relay states'),
        ),
      );
    _heavyUseTimer = Timer.periodic(
      _heavyUseCheckInterval,
      (_) => _run(_checkHeavyUse),
    );
  }

  Future<void> dispose() async {
    _heavyUseTimer?.cancel();
    _heavyUseTimer = null;
    await Future.wait(_subscriptions.map((subscription) => subscription.cancel()));
    _subscriptions.clear();
    _started = false;
  }

  Future<void> _handleGasStatus(GasStatus? status) async {
    if (status == null) {
      return;
    }
    final alert = await _alertRepository.recordGasStatus(status.leak);
    if (alert != null) {
      await _showAlert(alert);
    }
  }

  Future<void> _handleDeviceStatus(bool? online) async {
    if (online == null) {
      return;
    }
    final alert = await _alertRepository.recordDeviceStatus(online);
    if (alert != null) {
      await _showAlert(alert);
    }
  }

  Future<void> _handlePowerReading(PowerReading? reading) async {
    if (reading == null) {
      return;
    }
    final alert = await _alertRepository.recordPowerReading(
      watts: reading.watts,
      limitWatts: _settingsRepository.loadPowerLimitWatts(),
      now: reading.receivedAt,
    );
    if (alert != null) {
      await _showAlert(alert);
    }
  }

  Future<void> _handleRelayStates(Map<int, RelayState> states) async {
    if (states.isEmpty) {
      return;
    }
    await _alertRepository.recordConfirmedRelayStates(states);
    await _checkHeavyUse();
  }

  Future<void> _checkHeavyUse() async {
    final appliances = await _applianceRepository.loadAll();
    final wattages = {
      for (final appliance in appliances)
        appliance.relay: _nilmRepository.effectiveWattageFor(
          appliance.relay,
          manualWattage: appliance.manualWattage,
        ),
    };
    final alerts = await _alertRepository.checkHeavyUse(
      thresholdMinutes: _settingsRepository.loadHeavyUseDurationMinutes(),
      appliances: appliances,
      wattages: wattages,
    );
    for (final alert in alerts) {
      await _showAlert(alert);
    }
  }

  Future<void> _showAlert(AlertRecord alert) async {
    try {
      await _notifier.showAlert(alert);
    } finally {
      onAlertsChanged?.call();
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } on Exception catch (error, stackTrace) {
      debugPrint('Alert monitoring failed: $error\n$stackTrace');
    }
  }

  void Function(Object error, StackTrace stackTrace) _logStreamError(
    String streamName,
  ) {
    return (error, stackTrace) {
      debugPrint('Alert $streamName stream failed: $error\n$stackTrace');
    };
  }
}
