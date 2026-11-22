import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/data/db.dart';
import 'package:ghar_app/data/repositories/power_history_repository.dart';
import 'package:ghar_app/domain/models/mqtt_readings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late PowerHistoryRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: createPowerHistorySchema,
      ),
    );
    repository = PowerHistoryRepository(database);
  });

  tearDown(() => database.close());

  test('downsamples chart rows but records every energy delta', () async {
    final start = DateTime(2026, 2, 1, 12);

    expect(await repository.recordReading(_reading(start, 1.0)), isTrue);
    expect(
      await repository.recordReading(
        _reading(start.add(const Duration(seconds: 5)), 1.1),
      ),
      isFalse,
    );
    expect(
      await repository.recordReading(
        _reading(start.add(const Duration(seconds: 10)), 1.2),
      ),
      isTrue,
    );

    expect(await repository.sampleCount(), 2);
    final totals = await repository.getEnergyTotals(now: start);
    expect(totals.todayKwh, closeTo(0.2, 0.000001));
    expect(totals.monthKwh, closeTo(0.2, 0.000001));
  });

  test('meter reset does not add negative energy', () async {
    final now = DateTime(2026, 3, 10, 12);
    await repository.recordReading(_reading(now, 10));
    await repository.recordReading(
      _reading(now.add(const Duration(seconds: 1)), 0.2),
    );
    await repository.recordReading(
      _reading(now.add(const Duration(seconds: 2)), 0.25),
    );

    final totals = await repository.getEnergyTotals(now: now);
    expect(totals.todayKwh, closeTo(0.05, 0.000001));
  });

  test(
    'prunes raw samples older than 30 days and keeps daily summaries',
    () async {
      final now = DateTime(2026, 5, 1, 12);
      final oldReadingTime = now.subtract(const Duration(days: 31));
      await repository.recordReading(_reading(oldReadingTime, 2.0));
      await repository.recordReading(_reading(now, 2.5));

      expect(
        await repository.getRecentSamples(
          now: now,
          duration: const Duration(days: 60),
        ),
        hasLength(1),
      );
      final totals = await repository.getEnergyTotals(now: now);
      expect(totals.monthKwh, closeTo(0.5, 0.000001));

      final dailyRows = await database.query('daily_energy');
      expect(dailyRows, hasLength(2));
    },
  );

  test(
    'tariff can be multiplied by the returned daily and monthly units',
    () async {
      final start = DateTime(2026, 4, 5, 12);
      await repository.recordReading(_reading(start, 4.0));
      await repository.recordReading(
        _reading(start.add(const Duration(seconds: 2)), 4.75),
      );

      final totals = await repository.getEnergyTotals(now: start);
      const tariff = 8.5;
      expect(totals.todayKwh * tariff, closeTo(6.375, 0.000001));
      expect(totals.monthKwh * tariff, closeTo(6.375, 0.000001));
    },
  );
}

PowerReading _reading(DateTime timestamp, double kwh) {
  return PowerReading(
    voltage: 230,
    current: 1.2,
    watts: 276,
    kilowattHours: kwh,
    receivedAt: timestamp,
  );
}
