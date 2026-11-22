import 'package:sqflite/sqflite.dart';

import '../../domain/models/alert_record.dart';
import '../../domain/models/appliance.dart';
import '../../domain/models/mqtt_readings.dart';

class AlertRepository {
  AlertRepository(this._database);

  final Database _database;

  Future<AlertRecord?> recordGasStatus(
    bool leak, {
    DateTime? now,
  }) async {
    final occurredAt = now ?? DateTime.now();
    return _database.transaction((transaction) async {
      final wasLeaking = await _readState(transaction, 'gas_leak') == 'true';
      await _writeState(transaction, 'gas_leak', leak.toString());
      if (!leak || wasLeaking) {
        return null;
      }
      return _insertAlert(
        transaction,
        type: AlertType.gasLeak,
        title: 'Gas leak detected',
        message:
            'The gas sensor reported a leak. Check the area and follow your '
            'household safety plan. Acknowledge only after you have checked.',
        occurredAt: occurredAt,
      );
    });
  }

  Future<AlertRecord?> recordDeviceStatus(
    bool online, {
    DateTime? now,
  }) async {
    final occurredAt = now ?? DateTime.now();
    return _database.transaction((transaction) async {
      final previous = await _readState(transaction, 'device_online');
      await _writeState(transaction, 'device_online', online.toString());
      if (online || previous == 'false') {
        return null;
      }
      return _insertAlert(
        transaction,
        type: AlertType.deviceOffline,
        title: 'ESP32 is offline',
        message:
            'The ESP32 reported that it is offline. Ghar cannot confirm relay '
            'or sensor updates until it reconnects.',
        occurredAt: occurredAt,
      );
    });
  }

  Future<AlertRecord?> recordPowerReading({
    required double watts,
    required double limitWatts,
    DateTime? now,
  }) async {
    if (!watts.isFinite || watts < 0) {
      throw ArgumentError.value(watts, 'watts');
    }
    if (!limitWatts.isFinite || limitWatts < 0) {
      throw ArgumentError.value(limitWatts, 'limitWatts');
    }
    final occurredAt = now ?? DateTime.now();
    final limitKey = limitWatts == 0 ? 'disabled' : limitWatts.toString();
    return _database.transaction((transaction) async {
      final previousLimit = await _readState(transaction, 'load_limit');
      if (limitWatts == 0 || watts <= limitWatts) {
        await _writeState(transaction, 'load_limit', 'below');
        return null;
      }
      if (previousLimit == limitKey) {
        return null;
      }
      await _writeState(transaction, 'load_limit', limitKey);
      return _insertAlert(
        transaction,
        type: AlertType.loadLimit,
        title: 'High power use',
        message:
            'The meter reports ${watts.toStringAsFixed(0)} W, above your '
            '${limitWatts.toStringAsFixed(0)} W limit. This is a warning; '
            'Ghar does not switch relays off automatically.',
        occurredAt: occurredAt,
      );
    });
  }

  Future<void> recordConfirmedRelayStates(
    Map<int, RelayState> relayStates,
  ) async {
    await _database.transaction((transaction) async {
      final states = relayStates.values.toList()
        ..sort((first, second) => first.relay.compareTo(second.relay));
      for (final state in states) {
        final rows = await transaction.query(
          'alert_relay_state',
          columns: ['is_on'],
          where: 'relay = ?',
          whereArgs: [state.relay],
          limit: 1,
        );
        final timestamp = state.receivedAt.toLocal().millisecondsSinceEpoch;
        if (rows.isEmpty) {
          await transaction.insert('alert_relay_state', {
            'relay': state.relay,
            'is_on': state.isOn ? 1 : 0,
            'on_since_ms': state.isOn ? timestamp : null,
            'heavy_alerted': 0,
          });
          continue;
        }
        final wasOn = rows.first['is_on']! as int == 1;
        if (wasOn == state.isOn) {
          continue;
        }
        await transaction.update(
          'alert_relay_state',
          {
            'is_on': state.isOn ? 1 : 0,
            'on_since_ms': state.isOn ? timestamp : null,
            'heavy_alerted': 0,
          },
          where: 'relay = ?',
          whereArgs: [state.relay],
        );
      }
    });
  }

  Future<List<AlertRecord>> checkHeavyUse({
    required int thresholdMinutes,
    required List<Appliance> appliances,
    required Map<int, double?> wattages,
    DateTime? now,
  }) async {
    if (thresholdMinutes < 1) {
      throw ArgumentError.value(thresholdMinutes, 'thresholdMinutes');
    }
    final currentTime = now ?? DateTime.now();
    final currentTimeMs = currentTime.millisecondsSinceEpoch;
    final thresholdMs = Duration(minutes: thresholdMinutes).inMilliseconds;
    return _database.transaction((transaction) async {
      final rows = await transaction.query(
        'alert_relay_state',
        where: 'is_on = 1 AND heavy_alerted = 0 AND on_since_ms IS NOT NULL',
      );
      final applianceByRelay = {
        for (final appliance in appliances) appliance.relay: appliance,
      };
      final alerts = <AlertRecord>[];
      for (final row in rows) {
        final relay = row['relay']! as int;
        final onSinceMs = row['on_since_ms']! as int;
        final elapsedMs = currentTimeMs - onSinceMs;
        if (elapsedMs < thresholdMs) {
          continue;
        }
        final appliance = applianceByRelay[relay];
        final name = appliance?.name ?? 'Relay $relay';
        final watts = wattages[relay];
        final elapsed = Duration(milliseconds: elapsedMs);
        final energyKwh = watts == null
            ? null
            : watts * elapsedMs / 3600000000;
        final safetyNote = appliance?.protected == true
            ? ' This device is Protected; this is a warning only.'
            : ' This is a warning only; Ghar never switches relays off '
                  'automatically.';
        final estimatedEnergy = energyKwh == null
            ? ''
            : ' Estimated energy use: ${energyKwh.toStringAsFixed(2)} kWh.';
        final alert = await _insertAlert(
          transaction,
          type: AlertType.heavyUse,
          title: 'Heavy use: $name',
          message:
              '$name has been ON for ${_formatDuration(elapsed)}.'
              '$estimatedEnergy$safetyNote',
          occurredAt: currentTime,
        );
        await transaction.update(
          'alert_relay_state',
          {'heavy_alerted': 1},
          where: 'relay = ?',
          whereArgs: [relay],
        );
        alerts.add(alert);
      }
      return alerts;
    });
  }

  Future<AlertRecord?> loadActiveGasAlert() async {
    final rows = await _database.query(
      'alert_events',
      where: 'type = ? AND acknowledged_at_ms IS NULL',
      whereArgs: [AlertType.gasLeak.name],
      orderBy: 'id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : AlertRecord.fromRow(rows.first);
  }

  Future<List<AlertRecord>> loadHistory({int limit = 100}) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit');
    }
    final rows = await _database.query(
      'alert_events',
      orderBy: 'occurred_at_ms DESC, id DESC',
      limit: limit,
    );
    return rows.map(AlertRecord.fromRow).toList(growable: false);
  }

  Future<void> acknowledge(int id, {DateTime? now}) async {
    await _database.update(
      'alert_events',
      {'acknowledged_at_ms': (now ?? DateTime.now()).millisecondsSinceEpoch},
      where: 'id = ? AND acknowledged_at_ms IS NULL',
      whereArgs: [id],
    );
  }

  Future<String?> _readState(DatabaseExecutor executor, String key) async {
    final rows = await executor.query(
      'alert_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']! as String;
  }

  Future<void> _writeState(
    DatabaseExecutor executor,
    String key,
    String value,
  ) async {
    await executor.insert('alert_state', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AlertRecord> _insertAlert(
    DatabaseExecutor executor, {
    required AlertType type,
    required String title,
    required String message,
    required DateTime occurredAt,
  }) async {
    final timestamp = occurredAt.toLocal();
    final id = await executor.insert('alert_events', {
      'type': type.name,
      'title': title,
      'message': message,
      'occurred_at_ms': timestamp.millisecondsSinceEpoch,
    });
    return AlertRecord(
      id: id,
      type: type,
      title: title,
      message: message,
      occurredAt: timestamp,
      acknowledgedAt: null,
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) {
      return '$minutes min';
    }
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
}
