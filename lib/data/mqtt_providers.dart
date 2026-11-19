import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/mqtt_readings.dart';
import 'mqtt_service.dart';

final mqttServiceProvider = Provider<MqttService>((ref) {
  throw StateError('MqttService must be provided at the app root.');
});

final mqttConnectionProvider = StreamProvider<BrokerConnectionState>((ref) {
  return ref.watch(mqttServiceProvider).connectionStatusStream;
});

final mqttDeviceStatusProvider = StreamProvider<bool?>((ref) {
  return ref.watch(mqttServiceProvider).deviceStatusStream;
});

final mqttRelayStatesProvider = StreamProvider<Map<int, RelayState>>((ref) {
  return ref.watch(mqttServiceProvider).relayStateUpdates;
});

final mqttPowerProvider = StreamProvider<PowerReading?>((ref) {
  return ref.watch(mqttServiceProvider).powerReadings;
});

final mqttGasProvider = StreamProvider<GasStatus?>((ref) {
  return ref.watch(mqttServiceProvider).gasStatuses;
});

final mqttErrorProvider = StreamProvider<String?>((ref) {
  return ref.watch(mqttServiceProvider).connectionErrors;
});
