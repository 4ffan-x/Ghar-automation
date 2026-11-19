import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/app.dart';
import 'package:ghar_app/data/appliance_providers.dart';
import 'package:ghar_app/data/mqtt_providers.dart';
import 'package:ghar_app/data/mqtt_service.dart';
import 'package:ghar_app/data/repositories/appliance_repository.dart';
import 'package:ghar_app/domain/models/mqtt_readings.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  late MqttService mqttService;
  late ApplianceRepository applianceRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    applianceRepository = ApplianceRepository(
      await SharedPreferences.getInstance(),
    );
    mqttService = MqttService();
  });

  tearDown(() async {
    await mqttService.dispose();
  });

  testWidgets('shows all four tabs and opens their placeholder screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mqttServiceProvider.overrideWithValue(mqttService),
          applianceRepositoryProvider.overrideWithValue(applianceRepository),
        ],
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
    expect(find.text('Monitor is coming in a later phase.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Insights are coming in a later phase.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('MQTT broker'), findsOneWidget);
    expect(find.text('Broker host or IP address'), findsOneWidget);
  });

  testWidgets('appliance name and protection preference are editable', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mqttServiceProvider.overrideWithValue(mqttService),
          applianceRepositoryProvider.overrideWithValue(applianceRepository),
        ],
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
          mqttServiceProvider.overrideWithValue(service),
          applianceRepositoryProvider.overrideWithValue(applianceRepository),
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
          mqttServiceProvider.overrideWithValue(service),
          applianceRepositoryProvider.overrideWithValue(applianceRepository),
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
}
