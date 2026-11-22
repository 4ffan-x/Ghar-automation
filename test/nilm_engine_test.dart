import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/domain/nilm/nilm_engine.dart';

void main() {
  test('clean ON and OFF events learn the appliance power step', () {
    final engine = NilmEngine();
    final start = DateTime(2026, 11, 22, 12);
    engine.recordRelayEvent(
      _event(1, 1, false, start, isTransition: false, processed: true),
    );
    _addSamples(engine, start, const Duration(seconds: 0), 9, 100);
    engine.recordRelayEvent(
      _event(2, 1, true, start.add(const Duration(seconds: 10))),
    );
    final onOutcomes = _addSamples(
      engine,
      start,
      const Duration(seconds: 10),
      18,
      220,
    );

    expect(onOutcomes.single.accepted, isTrue);
    expect(onOutcomes.single.sampleWatts, closeTo(120, 0.001));

    _addSamples(engine, start, const Duration(seconds: 19), 29, 220);
    engine.recordRelayEvent(
      _event(3, 1, false, start.add(const Duration(seconds: 30))),
    );
    final offOutcomes = _addSamples(
      engine,
      start,
      const Duration(seconds: 30),
      38,
      100,
    );

    expect(offOutcomes.single.accepted, isTrue);
    expect(offOutcomes.single.sampleWatts, closeTo(120, 0.001));
    expect(offOutcomes.single.learnedWatts, closeTo(120, 0.001));
  });

  test('a noisy but stable baseline is accepted', () {
    final engine = NilmEngine();
    final start = DateTime(2026, 11, 22, 12);
    engine.recordRelayEvent(
      _event(1, 1, false, start, isTransition: false, processed: true),
    );
    for (var second = 0; second <= 9; second++) {
      final noise = const [-2.0, 1.0, -1.0, 2.0][second % 4];
      engine.addPowerSample(
        NilmPowerSample(
          timestamp: start.add(Duration(seconds: second)),
          watts: 100 + noise,
        ),
      );
    }
    engine.recordRelayEvent(
      _event(2, 1, true, start.add(const Duration(seconds: 10))),
    );
    final outcomes = _addSamples(
      engine,
      start,
      const Duration(seconds: 10),
      18,
      220,
    );

    expect(outcomes.single.accepted, isTrue);
    expect(outcomes.single.sampleWatts, closeTo(120, 2));
  });

  test('rejects events confounded by a second relay transition', () {
    final engine = NilmEngine();
    final start = DateTime(2026, 11, 22, 12);
    engine.recordRelayEvent(
      _event(1, 1, false, start, isTransition: false, processed: true),
    );
    engine.recordRelayEvent(
      _event(2, 1, true, start.add(const Duration(seconds: 10))),
    );
    _addSamples(engine, start, Duration.zero, 14, 100);
    engine.recordRelayEvent(
      _event(3, 2, true, start.add(const Duration(seconds: 15))),
    );
    final outcomes = _addSamples(
      engine,
      start,
      const Duration(seconds: 15),
      23,
      220,
    );

    final onOutcome = outcomes.singleWhere((outcome) => outcome.eventId == 2);
    expect(onOutcome.accepted, isFalse);
    expect(onOutcome.reason, contains('Another relay'));
  });

  test('rejects a power step below the configured noise threshold', () {
    final engine = NilmEngine(minimumDeltaWatts: 8);
    final start = DateTime(2026, 11, 22, 12);
    engine.recordRelayEvent(
      _event(1, 1, false, start, isTransition: false, processed: true),
    );
    _addSamples(engine, start, Duration.zero, 9, 100);
    engine.recordRelayEvent(
      _event(2, 1, true, start.add(const Duration(seconds: 10))),
    );
    final outcomes = _addSamples(
      engine,
      start,
      const Duration(seconds: 10),
      18,
      105,
    );

    expect(outcomes.single.accepted, isFalse);
    expect(outcomes.single.reason, contains('threshold'));
  });

  test('rejects a large outlier after a stable estimate is established', () {
    final engine = NilmEngine();
    final start = DateTime(2026, 11, 22, 12);
    engine.recordRelayEvent(
      _event(1, 1, false, start, isTransition: false, processed: true),
    );
    _addSamples(engine, start, Duration.zero, 9, 100);
    engine.recordRelayEvent(
      _event(2, 1, true, start.add(const Duration(seconds: 10))),
    );
    final firstLearning = _addSamples(
      engine,
      start,
      const Duration(seconds: 10),
      18,
      200,
    );
    expect(firstLearning.single.accepted, isTrue);

    _addSamples(engine, start, const Duration(seconds: 19), 29, 200);
    engine.recordRelayEvent(
      _event(3, 1, false, start.add(const Duration(seconds: 30))),
    );
    final offLearning = _addSamples(
      engine,
      start,
      const Duration(seconds: 30),
      38,
      100,
    );
    expect(offLearning.single.accepted, isTrue);

    _addSamples(engine, start, const Duration(seconds: 39), 49, 100);
    engine.recordRelayEvent(
      _event(4, 1, true, start.add(const Duration(seconds: 50))),
    );
    final outlier = _addSamples(
      engine,
      start,
      const Duration(seconds: 50),
      58,
      350,
    );

    expect(outlier.single.accepted, isFalse);
    expect(outlier.single.reason, contains('outlier'));
    expect(outlier.single.learnedWatts, isNull);
  });

  test('manual wattage takes priority over the learned estimate', () {
    final engine = NilmEngine();
    engine.restore(
      powerSamples: [],
      relayEvents: [_event(1, 1, true, DateTime(2026, 11, 22, 8))],
      learnedSamples: {
        1: [118, 120, 122],
      },
      manualWattages: {1: 90},
    );
    final snapshot = engine.createSnapshot(
      now: DateTime(2026, 11, 22, 9),
      measuredTotalKwh: 0.09,
      appliances: const [
        NilmApplianceInput(
          relay: 1,
          name: 'Relay 1',
          isProtected: false,
          isVariableLoad: false,
          manualWattage: 90,
        ),
      ],
    );

    expect(snapshot.appliances.single.learnedWattage, closeTo(120, 0.001));
    expect(snapshot.appliances.single.effectiveWattage, 90);
    expect(snapshot.appliances.single.energyKwh, closeTo(0.09, 0.001));
  });

  test('daily energy and unknown share match a hand-calculated example', () {
    final engine = NilmEngine();
    final day = DateTime(2026, 11, 22);
    engine.restore(
      powerSamples: [],
      relayEvents: [
        _event(
          1,
          1,
          true,
          day.add(const Duration(hours: 8)),
          isTransition: false,
          processed: true,
        ),
        _event(
          2,
          2,
          true,
          day.add(const Duration(hours: 9)),
          isTransition: false,
          processed: true,
        ),
        _event(3, 2, false, day.add(const Duration(hours: 10))),
      ],
      learnedSamples: {
        1: [100],
        2: [200],
      },
      manualWattages: {},
    );
    final snapshot = engine.createSnapshot(
      now: day.add(const Duration(hours: 10)),
      measuredTotalKwh: 0.4,
      appliances: const [
        NilmApplianceInput(
          relay: 1,
          name: 'Fan',
          isProtected: false,
          isVariableLoad: false,
        ),
        NilmApplianceInput(
          relay: 2,
          name: 'Heater',
          isProtected: false,
          isVariableLoad: false,
        ),
      ],
    );

    expect(snapshot.appliances[0].energyKwh, closeTo(0.2, 0.001));
    expect(snapshot.appliances[1].energyKwh, closeTo(0.2, 0.001));
    expect(snapshot.estimatedApplianceKwh, closeTo(0.4, 0.001));
    expect(snapshot.otherKwh, closeTo(0, 0.001));
    expect(snapshot.appliances[0].sharePercent, closeTo(50, 0.001));

    final overestimated = engine.createSnapshot(
      now: day.add(const Duration(hours: 10)),
      measuredTotalKwh: 0.3,
      appliances: const [
        NilmApplianceInput(
          relay: 1,
          name: 'Fan',
          isProtected: false,
          isVariableLoad: false,
        ),
        NilmApplianceInput(
          relay: 2,
          name: 'Heater',
          isProtected: false,
          isVariableLoad: false,
        ),
      ],
    );
    expect(overestimated.otherKwh, 0);
    expect(overestimated.modelExcessKwh, closeTo(0.1, 0.001));
  });

  test('protected and variable loads are labeled as low confidence', () {
    final engine = NilmEngine();
    engine.restore(
      powerSamples: [],
      relayEvents: [],
      learnedSamples: {
        1: [100, 101, 99, 100, 102],
      },
      manualWattages: {},
    );
    final snapshot = engine.createSnapshot(
      now: DateTime(2026, 11, 22, 10),
      measuredTotalKwh: 1,
      appliances: const [
        NilmApplianceInput(
          relay: 1,
          name: 'Fridge',
          isProtected: false,
          isVariableLoad: true,
        ),
      ],
    );

    expect(snapshot.appliances.single.isLowConfidenceLoad, isTrue);
    expect(snapshot.appliances.single.confidence, lessThanOrEqualTo(0.35));
  });
}

NilmRelayEvent _event(
  int id,
  int relay,
  bool isOn,
  DateTime timestamp, {
  bool isTransition = true,
  bool processed = false,
}) {
  return NilmRelayEvent(
    id: id,
    relay: relay,
    isOn: isOn,
    timestamp: timestamp,
    isTransition: isTransition,
    processed: processed,
  );
}

List<NilmLearningOutcome> _addSamples(
  NilmEngine engine,
  DateTime start,
  Duration firstOffset,
  int lastSecond,
  double watts,
) {
  final outcomes = <NilmLearningOutcome>[];
  for (var second = firstOffset.inSeconds; second <= lastSecond; second++) {
    outcomes.addAll(
      engine.addPowerSample(
        NilmPowerSample(
          timestamp: start.add(Duration(seconds: second)),
          watts: watts,
        ),
      ),
    );
  }
  return outcomes;
}
