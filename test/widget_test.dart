import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/app.dart';
import 'package:ghar_app/data/mqtt_providers.dart';
import 'package:ghar_app/data/mqtt_service.dart';

void main() {
  late MqttService mqttService;

  setUp(() {
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
        overrides: [mqttServiceProvider.overrideWithValue(mqttService)],
        child: const GharApp(),
      ),
    );

    expect(find.text('Control is coming in a later phase.'), findsOneWidget);

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
}
