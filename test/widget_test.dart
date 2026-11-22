import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/app.dart';
import 'package:ghar_app/data/appliance_providers.dart';
import 'package:ghar_app/data/db.dart';
import 'package:ghar_app/data/monitor_providers.dart';
import 'package:ghar_app/data/mqtt_providers.dart';
import 'package:ghar_app/data/mqtt_service.dart';
import 'package:ghar_app/data/nilm_providers.dart';
import 'package:ghar_app/data/repositories/appliance_repository.dart';
import 'package:ghar_app/data/repositories/nilm_repository.dart';
import 'package:ghar_app/data/repositories/power_history_repository.dart';
import 'package:ghar_app/data/repositories/settings_repository.dart';
import 'package:ghar_app/domain/models/energy_totals.dart';
import 'package:ghar_app/domain/models/mqtt_readings.dart';
import 'package:ghar_app/features/monitor/monitor_screen.dart';
import 'package:ghar_app/features/insights/insights_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RecordingMqttService extends MqttService {
  final List<(int, bool)> commands = [];

  @override
  Future<void> publishTestRelayCommand({
    required int relay,
    required bool turnOn,
  }) async {
    commands.add((relay, turnOn));
  }
}

class _NoopNilmRepository extends NilmRepository {
  _NoopNilmRepository(super.database, super.applianceRepository);

  @override
  Future<void> recordPowerReading(PowerReading reading) async {}

  @override
  Future<void> recordConfirmedRelayStates(
    Map<int, RelayState> relayStates,
  ) async {}
}

void main() {
  late MqttService mqttService;
  late ApplianceRepository applianceRepository;
  late SettingsRepository settingsRepository;
  late Database powerDatabase;
  late PowerHistoryRepository powerHistoryRepository;
  late NilmRepository nilmRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    applianceRepository = ApplianceRepository(preferences);
    settingsRepository = SettingsRepository(preferences);
    powerDatabase = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: createPowerHistorySchema,
      ),
    );
    powerHistoryRepository = PowerHistoryRepository(powerDatabase);
    nilmRepository = _NoopNilmRepository(powerDatabase, applianceRepository);
    await nilmRepository.initialize();
    mqttService = MqttService(settingsRepository: settingsRepository);
  });

  tearDown(() async {
    await mqttService.dispose();
    await nilmRepository.flush();
    await powerDatabase.close();
  });

  setUpAll(sqfliteFfiInit);

  commonOverrides(MqttService service) => [
    mqttServiceProvider.overrideWithValue(service),
    applianceRepositoryProvider.overrideWithValue(applianceRepository),
    settingsRepositoryProvider.overrideWithValue(settingsRepository),
    powerHistoryRepositoryProvider.overrideWithValue(powerHistoryRepository),
    nilmRepositoryProvider.overrideWithValue(nilmRepository),
    recentPowerHistoryProvider.overrideWith((ref) async => []),
    energyTotalsProvider.overrideWith(
      (ref) async => const EnergyTotals(todayKwh: 0, monthKwh: 0),
    ),
  ];

  testWidgets('shows all four tabs and opens Insights', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: commonOverrides(mqttService),
        child: const GharApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Relay 1'), findsOneWidget);
    expect(find.text('Waiting for ESP32 state · Relay 1'), findsOneWidget);
    expect(find.byKey(const Key('relay-control-switch-1')), findsNothing);
    expect(find.byKey(const Key('protected-switch-1')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for power readings'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Appliance energy estimates · today'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('MQTT broker'), findsOneWidget);
    expect(find.text('Broker host or IP address'), findsOneWidget);
    await tester.drag(find.text('MQTT broker'), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Price per unit (Rs/kWh)'), findsOneWidget);
  });

  testWidgets('appliance name and protection preference are editable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: commonOverrides(mqttService),
        child: const GharApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rename-appliance-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Geyser');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Geyser'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('protected-switch-1')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    final saved = (await applianceRepository.loadAll()).first;
    expect(saved.name, 'Geyser');
    expect(saved.protected, isTrue);

    await tester.tap(find.byKey(const Key('choose-appliance-icon-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fridge'));
    await tester.pumpAndSettle();
    final savedWithIcon = (await applianceRepository.loadAll()).first;
    expect(savedWithIcon.iconKey, 'fridge');
  });

  testWidgets('relay switch waits for ESP32 confirmation before changing', (
    tester,
  ) async {
    final service = _RecordingMqttService();
    final relayStates = StreamController<Map<int, RelayState>>();
    final now = DateTime.now();
    final initialStates = {
      for (var relay = 1; relay <= 6; relay++)
        relay: RelayState(relay: relay, isOn: false, receivedAt: now),
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides(service),
          mqttConnectionProvider.overrideWith(
            (ref) => Stream.value(BrokerConnectionState.connected),
          ),
          mqttDeviceStatusProvider.overrideWith((ref) => Stream.value(true)),
          mqttRelayStatesProvider.overrideWith((ref) => relayStates.stream),
        ],
        child: const GharApp(),
      ),
    );
    await tester.pumpAndSettle();
    relayStates.add(initialStates);
    await tester.pumpAndSettle();

    final relaySwitch = find.byKey(const Key('relay-control-switch-1'));
    expect(tester.widget<Switch>(relaySwitch).value, isFalse);
    await tester.tap(relaySwitch);
    await tester.pump();

    expect(service.commands, [(1, true)]);
    expect(find.byKey(const Key('relay-control-switch-1')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('appliance-card-1')),
        matching: find.text('OFF'),
      ),
      findsOneWidget,
    );
    expect(find.text('Waiting for confirmation: ON'), findsOneWidget);

    relayStates.add({
      ...initialStates,
      1: RelayState(relay: 1, isOn: true, receivedAt: DateTime.now()),
    });
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(relaySwitch).value, isTrue);
    expect(find.text('Waiting for confirmation: ON'), findsNothing);
    await relayStates.close();
  });

  testWidgets('pending relay command reports no response after three seconds', (
    tester,
  ) async {
    final service = _RecordingMqttService();
    final relayStates = StreamController<Map<int, RelayState>>();
    final now = DateTime.now();
    final initialStates = {
      for (var relay = 1; relay <= 6; relay++)
        relay: RelayState(relay: relay, isOn: false, receivedAt: now),
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides(service),
          mqttConnectionProvider.overrideWith(
            (ref) => Stream.value(BrokerConnectionState.connected),
          ),
          mqttDeviceStatusProvider.overrideWith((ref) => Stream.value(true)),
          mqttRelayStatesProvider.overrideWith((ref) => relayStates.stream),
        ],
        child: const GharApp(),
      ),
    );
    await tester.pump();
    relayStates.add(initialStates);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('relay-control-switch-1')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('No response. You can try again.'), findsOneWidget);
    relayStates.add({
      ...initialStates,
      1: RelayState(relay: 1, isOn: true, receivedAt: DateTime.now()),
    });
    await tester.pumpAndSettle();
    expect(find.text('No response. You can try again.'), findsNothing);
    await relayStates.close();
  });

  testWidgets('monitor shows live readings, saved history, and bill estimate', (
    tester,
  ) async {
    final now = DateTime.now();
    final reading = PowerReading(
      voltage: 231,
      current: 2,
      watts: 462,
      kilowattHours: 1.5,
      receivedAt: now,
    );
    late List<PowerReading> savedHistory;
    late EnergyTotals savedTotals;
    await tester.runAsync(() async {
      await powerHistoryRepository.recordReading(
        PowerReading(
          voltage: 230,
          current: 1.2,
          watts: 276,
          kilowattHours: 1,
          receivedAt: now.subtract(const Duration(seconds: 2)),
        ),
      );
      await powerHistoryRepository.recordReading(reading);
      savedHistory = await powerHistoryRepository.getRecentSamples();
      savedTotals = await powerHistoryRepository.getEnergyTotals();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mqttServiceProvider.overrideWithValue(mqttService),
          powerHistoryRepositoryProvider.overrideWithValue(
            powerHistoryRepository,
          ),
          energyTariffProvider.overrideWithValue(10),
          mqttPowerProvider.overrideWith((ref) => Stream.value(reading)),
          recentPowerHistoryProvider.overrideWith((ref) async => savedHistory),
          energyTotalsProvider.overrideWith((ref) async => savedTotals),
        ],
        child: const MaterialApp(home: Scaffold(body: MonitorScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('462.0 W'), findsOneWidget);
    expect(find.text('231.0 V'), findsOneWidget);
    expect(find.text('2.00 A'), findsOneWidget);
    expect(find.text('1.50 kWh'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    await tester.ensureVisible(find.text('Energy and estimated bill'));
    await tester.pumpAndSettle();
    expect(find.text('Tariff: Rs 10.00 per kWh'), findsOneWidget);
    expect(find.text('0.500 kWh'), findsNWidgets(2));
    expect(find.text('Rs 5.00'), findsNWidgets(2));
    late EnergyTotals totalsAfterLiveReading;
    await tester.runAsync(() async {
      totalsAfterLiveReading = await powerHistoryRepository.getEnergyTotals();
    });
    expect(totalsAfterLiveReading.todayKwh, closeTo(0.5, 0.001));
  });

  testWidgets('energy tariff setting validates and persists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: commonOverrides(mqttService),
        child: const GharApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.drag(find.text('MQTT broker'), const Offset(0, -700));
    await tester.pumpAndSettle();

    final tariffField = find.byKey(const Key('energy-tariff-field'));
    await tester.enterText(tariffField, '-1');
    await tester.tap(find.text('Save tariff'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid non-negative tariff.'), findsOneWidget);

    await tester.enterText(tariffField, '8.5');
    await tester.tap(find.text('Save tariff'));
    await tester.pumpAndSettle();
    expect(settingsRepository.loadEnergyTariff(), 8.5);
  });

  testWidgets('Insights manual wattage override is saved locally', (
    tester,
  ) async {
    final snapshot = await nilmRepository.createSnapshot(
      measuredTotalKwh: 0.2,
      now: DateTime(2026, 11, 22, 12),
    );
    final appliances = await applianceRepository.loadAll();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          applianceRepositoryProvider.overrideWithValue(applianceRepository),
          appliancesProvider.overrideWith((ref) async => appliances),
          nilmInsightsProvider.overrideWith((ref) async => snapshot),
        ],
        child: const MaterialApp(home: Scaffold(body: InsightsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final overrideButton = find.byKey(const Key('nilm-override-1'));
    await tester.scrollUntilVisible(
      overrideButton,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(overrideButton);
    await tester.tap(overrideButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('nilm-manual-wattage-field')),
      '120',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = (await applianceRepository.loadAll()).first;
    expect(saved.manualWattage, 120);
    await tester.scrollUntilVisible(
      find.text('Other / unknown'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0.200 kWh today'), findsOneWidget);
  });
}
