import 'package:sqflite/sqflite.dart';

import '../../domain/models/energy_totals.dart';
import '../../domain/models/mqtt_readings.dart';

class PowerHistoryRepository {
  PowerHistoryRepository(this._database);

  static const sampleInterval = Duration(seconds: 10);
  static const retentionPeriod = Duration(days: 30);

  final Database _database;

  Future<bool> recordReading(PowerReading reading) async {
    final timestamp = reading.receivedAt.toLocal();
    final timestampMs = timestamp.millisecondsSinceEpoch;
    final date = _dateKey(timestamp);

    return _database.transaction((transaction) async {
      final cursorRows = await transaction.query(
        'energy_cursor',
        columns: ['total_kwh'],
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );

      if (cursorRows.isEmpty) {
        await transaction.insert('daily_energy', {
          'date': date,
          'energy_kwh': 0.0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } else {
        final previousKwh = (cursorRows.first['total_kwh']! as num).toDouble();
        final deltaKwh = reading.kilowattHours >= previousKwh
            ? reading.kilowattHours - previousKwh
            : 0.0;
        await transaction.rawInsert(
          '''
          INSERT INTO daily_energy(date, energy_kwh)
          VALUES(?, ?)
          ON CONFLICT(date) DO UPDATE SET
            energy_kwh = daily_energy.energy_kwh + excluded.energy_kwh
          ''',
          [date, deltaKwh],
        );
      }

      await transaction.insert('energy_cursor', {
        'id': 1,
        'total_kwh': reading.kilowattHours,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final latestSamples = await transaction.query(
        'power_samples',
        columns: ['timestamp_ms'],
        orderBy: 'timestamp_ms DESC',
        limit: 1,
      );
      final shouldSaveSample =
          latestSamples.isEmpty ||
          timestampMs - (latestSamples.first['timestamp_ms']! as int) >=
              sampleInterval.inMilliseconds;

      if (shouldSaveSample) {
        await transaction.insert('power_samples', {
          'timestamp_ms': timestampMs,
          'voltage': reading.voltage,
          'current': reading.current,
          'watts': reading.watts,
          'kwh': reading.kilowattHours,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final cutoffMs = timestamp
          .subtract(retentionPeriod)
          .millisecondsSinceEpoch;
      await transaction.delete(
        'power_samples',
        where: 'timestamp_ms < ?',
        whereArgs: [cutoffMs],
      );
      return shouldSaveSample;
    });
  }

  Future<List<PowerReading>> getRecentSamples({
    DateTime? now,
    Duration duration = const Duration(minutes: 30),
  }) async {
    final end = (now ?? DateTime.now()).toLocal();
    final samples = await _database.query(
      'power_samples',
      where: 'timestamp_ms >= ? AND timestamp_ms <= ?',
      whereArgs: [
        end.subtract(duration).millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'timestamp_ms ASC',
    );
    return samples.map(_toReading).toList(growable: false);
  }

  Future<EnergyTotals> getEnergyTotals({DateTime? now}) async {
    final currentDate = (now ?? DateTime.now()).toLocal();
    final today = _dateKey(currentDate);
    final monthStart = _dateKey(DateTime(currentDate.year, currentDate.month));
    final rows = await _database.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN date = ? THEN energy_kwh ELSE 0 END), 0)
          AS today_kwh,
        COALESCE(SUM(energy_kwh), 0) AS month_kwh
      FROM daily_energy
      WHERE date >= ? AND date <= ?
      ''',
      [today, monthStart, today],
    );
    return EnergyTotals(
      todayKwh: (rows.first['today_kwh']! as num).toDouble(),
      monthKwh: (rows.first['month_kwh']! as num).toDouble(),
    );
  }

  Future<int> sampleCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS sample_count FROM power_samples',
    );
    return result.first['sample_count']! as int;
  }

  PowerReading _toReading(Map<String, Object?> row) {
    return PowerReading(
      voltage: (row['voltage']! as num).toDouble(),
      current: (row['current']! as num).toDouble(),
      watts: (row['watts']! as num).toDouble(),
      kilowattHours: (row['kwh']! as num).toDouble(),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        row['timestamp_ms']! as int,
      ),
    );
  }

  static String _dateKey(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
