import 'dart:convert';

import '../domain/models/mqtt_readings.dart';

class MqttMessageParser {
  const MqttMessageParser._();

  static RelayState? parseRelayState({
    required int relay,
    required String payload,
    required DateTime receivedAt,
  }) {
    if (relay < 1 || relay > 6) {
      return null;
    }

    final normalized = payload.trim().toUpperCase();
    if (normalized != 'ON' && normalized != 'OFF') {
      return null;
    }

    return RelayState(
      relay: relay,
      isOn: normalized == 'ON',
      receivedAt: receivedAt,
    );
  }

  static PowerReading? parsePower({
    required String payload,
    required DateTime receivedAt,
  }) {
    final data = _decodeObject(payload);
    if (data == null) {
      return null;
    }

    final voltage = _readFiniteNumber(data, 'v');
    final current = _readFiniteNumber(data, 'a');
    final watts = _readFiniteNumber(data, 'w');
    final kilowattHours = _readFiniteNumber(data, 'kwh');
    if (voltage == null ||
        current == null ||
        watts == null ||
        kilowattHours == null) {
      return null;
    }

    return PowerReading(
      voltage: voltage,
      current: current,
      watts: watts,
      kilowattHours: kilowattHours,
      receivedAt: receivedAt,
    );
  }

  static GasStatus? parseGas(String payload) {
    final data = _decodeObject(payload);
    if (data == null || data['leak'] is! bool) {
      return null;
    }

    final ppmValue = data['ppm'];
    if (ppmValue != null && ppmValue is! num) {
      return null;
    }
    final ppm = ppmValue as num?;
    if (ppm != null && !ppm.isFinite) {
      return null;
    }

    return GasStatus(leak: data['leak']! as bool, ppm: ppm?.toDouble());
  }

  static bool? parseDeviceStatus(String payload) {
    switch (payload.trim().toLowerCase()) {
      case 'online':
        return true;
      case 'offline':
        return false;
      default:
        return null;
    }
  }

  static Map<String, dynamic>? _decodeObject(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static double? _readFiniteNumber(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! num || !value.isFinite) {
      return null;
    }
    return value.toDouble();
  }
}
