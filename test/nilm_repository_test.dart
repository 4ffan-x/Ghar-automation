import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/data/db.dart';
import 'package:ghar_app/data/repositories/appliance_repository.dart';
import 'package:ghar_app/data/repositories/nilm_repository.dart';
import 'package:ghar_app/domain/models/mqtt_readings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late ApplianceRepository applianceRepository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    applianceRepository = ApplianceRepository(preferences);
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: createPowerHistorySchema,
      ),
    );
  });

  tearDown(() => database.close());

  test(
    'learned wattage and confirmed relay intervals survive reloading',
    () async {
      final repository = NilmRepository(database, applianceRepository);
      await repository.initialize();
      final start = DateTime.now().subtract(const Duration(seconds: 20));
      await repository.recordConfirmedRelayStates({
        1: RelayState(relay: 1, isOn: false, receivedAt: start),
      });

      for (var second = 4; second <= 9; second++) {
        await repository.recordPowerReading(
          _reading(start.add(Duration(seconds: second)), 100),
        );
      }
      await repository.recordConfirmedRelayStates({
        1: RelayState(
          relay: 1,
          isOn: true,
          receivedAt: start.add(const Duration(seconds: 10)),
        ),
      });
      for (var second = 13; second <= 18; second++) {
        await repository.recordPowerReading(
          _reading(start.add(Duration(seconds: second)), 220),
        );
      }

      final beforeReload = await repository.createSnapshot(
        measuredTotalKwh: 0.001,
        now: start.add(const Duration(seconds: 18)),
      );
      expect(beforeReload.appliances.first.learnedWattage, closeTo(120, 0.001));
      expect(beforeReload.appliances.first.sampleCount, 1);
      expect(beforeReload.appliances.first.energyKwh, greaterThan(0));

      final reloadedRepository = NilmRepository(database, applianceRepository);
      await reloadedRepository.initialize();
      final afterReload = await reloadedRepository.createSnapshot(
        measuredTotalKwh: 0.001,
        now: start.add(const Duration(seconds: 18)),
      );
      expect(afterReload.appliances.first.learnedWattage, closeTo(120, 0.001));
      expect(
        afterReload.appliances.first.energyKwh,
        closeTo(beforeReload.appliances.first.energyKwh, 0.000001),
      );
    },
  );
}

PowerReading _reading(DateTime timestamp, double watts) {
  return PowerReading(
    voltage: 230,
    current: watts / 230,
    watts: watts,
    kilowattHours: 0,
    receivedAt: timestamp,
  );
}
