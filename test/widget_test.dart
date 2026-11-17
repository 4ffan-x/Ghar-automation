import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/app.dart';

void main() {
  testWidgets('shows all four tabs and opens their placeholder screens', (
    tester,
  ) async {
    await tester.pumpWidget(const GharApp());

    expect(find.text('Control is coming in a later phase.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.monitor_heart_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Monitor is coming in a later phase.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Insights are coming in a later phase.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Settings are coming in a later phase.'), findsOneWidget);
  });
}
