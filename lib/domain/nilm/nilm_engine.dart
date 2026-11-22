import 'dart:math' as math;

class NilmPowerSample {
  const NilmPowerSample({required this.timestamp, required this.watts});

  final DateTime timestamp;
  final double watts;
}

class NilmRelayEvent {
  const NilmRelayEvent({
    required this.id,
    required this.relay,
    required this.isOn,
    required this.timestamp,
    required this.isTransition,
    required this.processed,
  });

  final int id;
  final int relay;
  final bool isOn;
  final DateTime timestamp;
  final bool isTransition;
  final bool processed;

  NilmRelayEvent copyWith({bool? processed}) {
    return NilmRelayEvent(
      id: id,
      relay: relay,
      isOn: isOn,
      timestamp: timestamp,
      isTransition: isTransition,
      processed: processed ?? this.processed,
    );
  }
}

class NilmLearningOutcome {
  const NilmLearningOutcome({
    required this.eventId,
    required this.relay,
    required this.accepted,
    required this.reason,
    this.sampleWatts,
    this.learnedWatts,
  });

  final int eventId;
  final int relay;
  final bool accepted;
  final String reason;
  final double? sampleWatts;
  final double? learnedWatts;
}

class NilmApplianceInput {
  const NilmApplianceInput({
    required this.relay,
    required this.name,
    required this.isProtected,
    required this.isVariableLoad,
    this.manualWattage,
  });

  final int relay;
  final String name;
  final bool isProtected;
  final bool isVariableLoad;
  final double? manualWattage;
}

class NilmApplianceEstimate {
  const NilmApplianceEstimate({
    required this.relay,
    required this.name,
    required this.learnedWattage,
    required this.manualWattage,
    required this.effectiveWattage,
    required this.sampleCount,
    required this.spreadWatts,
    required this.confidence,
    required this.isLowConfidenceLoad,
    required this.energyKwh,
    required this.sharePercent,
  });

  final int relay;
  final String name;
  final double? learnedWattage;
  final double? manualWattage;
  final double? effectiveWattage;
  final int sampleCount;
  final double? spreadWatts;
  final double confidence;
  final bool isLowConfidenceLoad;
  final double energyKwh;
  final double sharePercent;
}

class NilmInsightSnapshot {
  const NilmInsightSnapshot({
    required this.appliances,
    required this.measuredTotalKwh,
    required this.estimatedApplianceKwh,
    required this.otherKwh,
    required this.modelExcessKwh,
  });

  final List<NilmApplianceEstimate> appliances;
  final double measuredTotalKwh;
  final double estimatedApplianceKwh;
  final double otherKwh;
  final double modelExcessKwh;

  double get otherSharePercent =>
      measuredTotalKwh > 0 ? otherKwh / measuredTotalKwh * 100 : 0;
}

class _RelayProfile {
  final List<double> samples = [];

  double? get medianWatts => samples.isEmpty ? null : _median(samples);

  double? get spreadWatts {
    final median = medianWatts;
    if (median == null) {
      return null;
    }
    return _median(samples.map((sample) => (sample - median).abs()).toList());
  }

  double get confidence {
    final median = medianWatts;
    if (median == null) {
      return 0;
    }
    final countScore = samples.length >= 5 ? 1.0 : samples.length / 5;
    final spreadRatio = (spreadWatts ?? 0) / math.max(median, 1);
    final consistencyScore = spreadRatio >= 0.7 ? 0.3 : 1 - spreadRatio;
    return countScore * consistencyScore;
  }
}

class NilmEngine {
  NilmEngine({
    this.minimumDeltaWatts = 8,
    this.maximumBaselineDeviationWatts = 15,
    this.maximumLearnedSamples = 7,
  }) {
    if (!minimumDeltaWatts.isFinite || minimumDeltaWatts < 0) {
      throw ArgumentError.value(minimumDeltaWatts, 'minimumDeltaWatts');
    }
    if (!maximumBaselineDeviationWatts.isFinite ||
        maximumBaselineDeviationWatts < 0) {
      throw ArgumentError.value(
        maximumBaselineDeviationWatts,
        'maximumBaselineDeviationWatts',
      );
    }
    if (maximumLearnedSamples < 1) {
      throw ArgumentError.value(maximumLearnedSamples, 'maximumLearnedSamples');
    }
  }

  final double minimumDeltaWatts;
  final double maximumBaselineDeviationWatts;
  final int maximumLearnedSamples;

  final List<NilmPowerSample> _powerSamples = [];
  final List<NilmRelayEvent> _relayEvents = [];
  final List<NilmRelayEvent> _pendingEvents = [];
  final Map<int, _RelayProfile> _profiles = {};
  final Map<int, bool> _relayStates = {};
  final Map<int, double> _manualWattages = {};

  bool? relayState(int relay) => _relayStates[relay];

  List<NilmLearningOutcome> addPowerSample(NilmPowerSample sample) {
    if (!sample.watts.isFinite || sample.watts < 0) {
      throw ArgumentError.value(sample.watts, 'watts');
    }
    _powerSamples
      ..removeWhere((existing) => existing.timestamp == sample.timestamp)
      ..add(sample)
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    final cutoff = sample.timestamp.subtract(const Duration(seconds: 30));
    _powerSamples.removeWhere(
      (existing) => existing.timestamp.isBefore(cutoff),
    );

    final dueEvents = _pendingEvents
        .where(
          (event) => !sample.timestamp.isBefore(
            event.timestamp.add(const Duration(seconds: 8)),
          ),
        )
        .toList();
    final outcomes = <NilmLearningOutcome>[];
    for (final event in dueEvents) {
      outcomes.add(_evaluateEvent(event));
      _markProcessed(event.id);
    }
    return outcomes;
  }

  void restore({
    required List<NilmPowerSample> powerSamples,
    required List<NilmRelayEvent> relayEvents,
    required Map<int, List<double>> learnedSamples,
    required Map<int, double> manualWattages,
  }) {
    _powerSamples
      ..clear()
      ..addAll(powerSamples)
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    if (_powerSamples.isNotEmpty) {
      final cutoff = _powerSamples.last.timestamp.subtract(
        const Duration(seconds: 30),
      );
      _powerSamples.removeWhere((sample) => sample.timestamp.isBefore(cutoff));
    }

    _relayEvents
      ..clear()
      ..addAll(relayEvents)
      ..sort(_compareEvents);
    _pendingEvents
      ..clear()
      ..addAll(
        _relayEvents.where((event) => event.isTransition && !event.processed),
      );
    _relayStates.clear();
    for (final event in _relayEvents) {
      _relayStates[event.relay] = event.isOn;
    }

    _profiles.clear();
    for (final entry in learnedSamples.entries) {
      final profile = _RelayProfile();
      profile.samples.addAll(entry.value);
      if (profile.samples.length > maximumLearnedSamples) {
        profile.samples.removeRange(
          0,
          profile.samples.length - maximumLearnedSamples,
        );
      }
      _profiles[entry.key] = profile;
    }
    _manualWattages
      ..clear()
      ..addAll(manualWattages);
  }

  void recordRelayEvent(NilmRelayEvent event) {
    if (event.relay < 1 || event.relay > 6) {
      throw ArgumentError.value(event.relay, 'relay');
    }
    _relayEvents.add(event);
    _relayEvents.sort(_compareEvents);
    _relayStates[event.relay] = event.isOn;
    if (event.isTransition && !event.processed) {
      _pendingEvents.add(event);
    }
  }

  void setManualWattage(int relay, double? wattage) {
    if (relay < 1 || relay > 6) {
      throw ArgumentError.value(relay, 'relay');
    }
    if (wattage == null) {
      _manualWattages.remove(relay);
      return;
    }
    if (!wattage.isFinite || wattage < 0) {
      throw ArgumentError.value(wattage, 'wattage');
    }
    _manualWattages[relay] = wattage;
  }

  double? effectiveWattageFor(int relay, {double? manualWattage}) {
    if (manualWattage != null &&
        (!manualWattage.isFinite || manualWattage < 0)) {
      throw ArgumentError.value(manualWattage, 'manualWattage');
    }
    return manualWattage ?? _profiles[relay]?.medianWatts;
  }

  NilmInsightSnapshot createSnapshot({
    required DateTime now,
    required double measuredTotalKwh,
    required List<NilmApplianceInput> appliances,
  }) {
    final measured = !measuredTotalKwh.isFinite || measuredTotalKwh < 0
        ? 0.0
        : measuredTotalKwh;
    final startOfDay = DateTime(now.year, now.month, now.day);
    final estimates = <NilmApplianceEstimate>[];

    for (final appliance in appliances) {
      setManualWattage(appliance.relay, appliance.manualWattage);
      final profile = _profiles[appliance.relay] ?? _RelayProfile();
      final learned = profile.medianWatts;
      final manual = _manualWattages[appliance.relay];
      final effective = manual ?? learned;
      final energy = effective == null
          ? 0.0
          : _energyForRelay(appliance.relay, effective, startOfDay, now);
      final lowConfidence = appliance.isProtected || appliance.isVariableLoad;

      estimates.add(
        NilmApplianceEstimate(
          relay: appliance.relay,
          name: appliance.name,
          learnedWattage: learned,
          manualWattage: manual,
          effectiveWattage: effective,
          sampleCount: profile.samples.length,
          spreadWatts: profile.spreadWatts,
          confidence: lowConfidence && profile.confidence > 0.35
              ? 0.35
              : profile.confidence,
          isLowConfidenceLoad: lowConfidence,
          energyKwh: energy,
          sharePercent: measured > 0 ? energy / measured * 100 : 0,
        ),
      );
    }

    final applianceEnergy = estimates.fold<double>(
      0,
      (total, estimate) => total + estimate.energyKwh,
    );
    final otherEnergy = measured > applianceEnergy
        ? measured - applianceEnergy
        : 0.0;
    return NilmInsightSnapshot(
      appliances: estimates,
      measuredTotalKwh: measured,
      estimatedApplianceKwh: applianceEnergy,
      otherKwh: otherEnergy,
      modelExcessKwh: applianceEnergy > measured
          ? applianceEnergy - measured
          : 0.0,
    );
  }

  NilmLearningOutcome _evaluateEvent(NilmRelayEvent event) {
    final eventTime = event.timestamp;
    // Compare settled medians so an appliance's inrush spike is not learned.
    final baselineStart = eventTime.subtract(const Duration(seconds: 6));
    final baselineEnd = eventTime.subtract(const Duration(seconds: 1));
    final afterStart = eventTime.add(const Duration(seconds: 3));
    final afterEnd = eventTime.add(const Duration(seconds: 8));
    final baseline = _powerSamples
        .where(
          (sample) =>
              !sample.timestamp.isBefore(baselineStart) &&
              !sample.timestamp.isAfter(baselineEnd),
        )
        .map((sample) => sample.watts)
        .toList();
    final after = _powerSamples
        .where(
          (sample) =>
              !sample.timestamp.isBefore(afterStart) &&
              !sample.timestamp.isAfter(afterEnd),
        )
        .map((sample) => sample.watts)
        .toList();

    if (baseline.length < 3 || after.length < 3) {
      return _rejected(event, 'Not enough power samples in both windows.');
    }
    final baselineMedian = _median(baseline);
    final baselineMean =
        baseline.fold<double>(0, (total, value) => total + value) /
        baseline.length;
    final baselineDeviation = _standardDeviation(baseline, baselineMean);
    if (baselineDeviation > maximumBaselineDeviationWatts) {
      return _rejected(event, 'Baseline power was unstable.');
    }
    final confounded = _relayEvents.any(
      (other) =>
          other.id != event.id &&
          other.isTransition &&
          !other.timestamp.isBefore(
            eventTime.subtract(const Duration(seconds: 8)),
          ) &&
          !other.timestamp.isAfter(eventTime.add(const Duration(seconds: 8))),
    );
    if (confounded) {
      return _rejected(event, 'Another relay changed within the event window.');
    }

    final delta = _median(after) - baselineMedian;
    final expectedDirection = event.isOn ? delta : -delta;
    if (expectedDirection < minimumDeltaWatts) {
      return _rejected(
        event,
        'Power step was below the ${minimumDeltaWatts.toStringAsFixed(0)} W threshold or in the wrong direction.',
      );
    }
    final sampleWatts = expectedDirection;
    final profile = _profiles.putIfAbsent(event.relay, _RelayProfile.new);
    final currentMedian = profile.medianWatts;
    if (currentMedian != null &&
        (sampleWatts - currentMedian).abs() >
            math.max(50, currentMedian * 0.5)) {
      return _rejected(event, 'Power step was an outlier for this appliance.');
    }

    profile.samples.add(sampleWatts);
    if (profile.samples.length > maximumLearnedSamples) {
      profile.samples.removeAt(0);
    }
    return NilmLearningOutcome(
      eventId: event.id,
      relay: event.relay,
      accepted: true,
      reason: 'Accepted.',
      sampleWatts: sampleWatts,
      learnedWatts: profile.medianWatts,
    );
  }

  NilmLearningOutcome _rejected(NilmRelayEvent event, String reason) {
    return NilmLearningOutcome(
      eventId: event.id,
      relay: event.relay,
      accepted: false,
      reason: reason,
    );
  }

  void _markProcessed(int eventId) {
    final pendingIndex = _pendingEvents.indexWhere(
      (event) => event.id == eventId,
    );
    if (pendingIndex < 0) {
      return;
    }
    final event = _pendingEvents
        .removeAt(pendingIndex)
        .copyWith(processed: true);
    final eventIndex = _relayEvents.indexWhere((item) => item.id == eventId);
    if (eventIndex >= 0) {
      _relayEvents[eventIndex] = event;
    }
  }

  double _energyForRelay(
    int relay,
    double watts,
    DateTime start,
    DateTime end,
  ) {
    var isOn = false;
    var intervalStart = start;
    var energyKwh = 0.0;
    final events = _relayEvents.where((event) => event.relay == relay).toList()
      ..sort(_compareEvents);

    // Replay confirmed states and clip any ON interval to today's boundary.
    for (final event in events) {
      if (event.timestamp.isBefore(start) ||
          event.timestamp.isAtSameMomentAs(start)) {
        isOn = event.isOn;
        intervalStart = start;
        continue;
      }
      if (event.timestamp.isAfter(end)) {
        break;
      }
      if (isOn) {
        energyKwh +=
            watts *
            event.timestamp.difference(intervalStart).inMicroseconds /
            Duration.microsecondsPerHour /
            1000;
      }
      isOn = event.isOn;
      intervalStart = event.timestamp;
    }
    if (isOn && end.isAfter(intervalStart)) {
      energyKwh +=
          watts *
          end.difference(intervalStart).inMicroseconds /
          Duration.microsecondsPerHour /
          1000;
    }
    return energyKwh;
  }
}

int _compareEvents(NilmRelayEvent first, NilmRelayEvent second) {
  final timeComparison = first.timestamp.compareTo(second.timestamp);
  return timeComparison != 0 ? timeComparison : first.id.compareTo(second.id);
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _standardDeviation(List<double> values, double mean) {
  final variance =
      values.fold<double>(
        0,
        (total, value) => total + math.pow(value - mean, 2).toDouble(),
      ) /
      values.length;
  return math.sqrt(variance);
}
