import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/appliance.dart';
import '../../domain/models/mqtt_readings.dart';
import '../../domain/nilm/nilm_engine.dart';
import 'appliance_repository.dart';

class NilmRepository {
  NilmRepository(this._database, this._applianceRepository);

  static const _sampleRetention = Duration(minutes: 2);

  final Database _database;
  final ApplianceRepository _applianceRepository;
  final NilmEngine _engine = NilmEngine();
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final powerRows = await _database.query(
      'nilm_power_samples',
      where: 'timestamp_ms >= ?',
      whereArgs: [nowMs - const Duration(seconds: 30).inMilliseconds],
      orderBy: 'timestamp_ms ASC',
    );
    final eventRows = await _database.query(
      'nilm_relay_events',
      orderBy: 'timestamp_ms ASC, id ASC',
    );
    final learnedRows = await _database.query(
      'nilm_learned_samples',
      orderBy: 'id ASC',
    );
    final appliances = await _applianceRepository.loadAll();
    final learnedSamples = <int, List<double>>{};
    for (final row in learnedRows) {
      learnedSamples
          .putIfAbsent(row['relay']! as int, () => [])
          .add((row['watts']! as num).toDouble());
    }
    _engine.restore(
      powerSamples: powerRows
          .map(
            (row) => NilmPowerSample(
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                row['timestamp_ms']! as int,
              ),
              watts: (row['watts']! as num).toDouble(),
            ),
          )
          .toList(),
      relayEvents: eventRows
          .map(
            (row) => NilmRelayEvent(
              id: row['id']! as int,
              relay: row['relay']! as int,
              isOn: row['is_on']! as int == 1,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                row['timestamp_ms']! as int,
              ),
              isTransition: row['is_transition']! as int == 1,
              processed: row['processed']! as int == 1,
            ),
          )
          .toList(),
      learnedSamples: learnedSamples,
      manualWattages: {
        for (final appliance in appliances)
          if (appliance.manualWattage != null)
            appliance.relay: appliance.manualWattage!,
      },
    );
    _initialized = true;
  }

  Future<void> recordPowerReading(PowerReading reading) {
    return _serialize(() async {
      _ensureInitialized();
      final timestamp = reading.receivedAt.toLocal();
      final timestampMs = timestamp.millisecondsSinceEpoch;
      final outcomes = _engine.addPowerSample(
        NilmPowerSample(timestamp: timestamp, watts: reading.watts),
      );
      await _database.transaction((transaction) async {
        await transaction.insert('nilm_power_samples', {
          'timestamp_ms': timestampMs,
          'watts': reading.watts,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final cutoff = timestamp
            .subtract(_sampleRetention)
            .millisecondsSinceEpoch;
        await transaction.delete(
          'nilm_power_samples',
          where: 'timestamp_ms < ?',
          whereArgs: [cutoff],
        );
        for (final outcome in outcomes) {
          await transaction.update(
            'nilm_relay_events',
            {'processed': 1},
            where: 'id = ?',
            whereArgs: [outcome.eventId],
          );
          if (outcome.accepted) {
            await transaction.insert('nilm_learned_samples', {
              'relay': outcome.relay,
              'watts': outcome.sampleWatts!,
              'timestamp_ms': timestampMs,
            });
            await transaction.delete(
              'nilm_learned_samples',
              where:
                  'relay = ? AND id NOT IN ('
                  'SELECT id FROM nilm_learned_samples '
                  'WHERE relay = ? ORDER BY id DESC LIMIT ?)',
              whereArgs: [outcome.relay, outcome.relay, 7],
            );
          } else {
            debugPrint(
              'NILM ignored relay ${outcome.relay} event '
              '${outcome.eventId}: ${outcome.reason}',
            );
          }
        }
      });
    });
  }

  Future<void> recordConfirmedRelayStates(Map<int, RelayState> relayStates) {
    return _serialize(() async {
      _ensureInitialized();
      final states = relayStates.values.toList()
        ..sort((first, second) => first.relay.compareTo(second.relay));
      for (final state in states) {
        final previousState = _engine.relayState(state.relay);
        if (previousState == state.isOn) {
          continue;
        }

        final timestamp = state.receivedAt.toLocal();
        final isTransition = previousState != null;
        final eventId = await _database.insert('nilm_relay_events', {
          'relay': state.relay,
          'is_on': state.isOn ? 1 : 0,
          'timestamp_ms': timestamp.millisecondsSinceEpoch,
          'is_transition': isTransition ? 1 : 0,
          'processed': isTransition ? 0 : 1,
        });
        _engine.recordRelayEvent(
          NilmRelayEvent(
            id: eventId,
            relay: state.relay,
            isOn: state.isOn,
            timestamp: timestamp,
            isTransition: isTransition,
            processed: !isTransition,
          ),
        );
      }
    });
  }

  Future<NilmInsightSnapshot> createSnapshot({
    required double measuredTotalKwh,
    DateTime? now,
  }) async {
    _ensureInitialized();
    final appliances = await _applianceRepository.loadAll();
    return _engine.createSnapshot(
      now: now ?? DateTime.now(),
      measuredTotalKwh: measuredTotalKwh,
      appliances: appliances.map(_toEngineInput).toList(growable: false),
    );
  }

  Future<void> flush() => _writeQueue;

  Future<void> _serialize(Future<void> Function() action) {
    final result = _writeQueue.then((_) => action());
    // Keep later writes running after a failed operation; the returned future
    // still reports that operation's error to its caller.
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  NilmApplianceInput _toEngineInput(Appliance appliance) {
    final normalizedName = appliance.name.toLowerCase();
    final isVariableLoad =
        appliance.iconKey == 'fridge' ||
        normalizedName.contains('fridge') ||
        normalizedName.contains('refrigerator');
    return NilmApplianceInput(
      relay: appliance.relay,
      name: appliance.name,
      isProtected: appliance.protected,
      isVariableLoad: isVariableLoad,
      manualWattage: appliance.manualWattage,
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('NilmRepository.initialize() must be called first.');
    }
  }
}
