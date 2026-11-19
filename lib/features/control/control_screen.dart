import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_constants.dart';
import '../../data/appliance_providers.dart';
import '../../data/mqtt_providers.dart';
import '../../data/mqtt_service.dart';
import '../../domain/models/appliance.dart';
import '../../domain/models/mqtt_readings.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  final Map<int, bool> _pendingTargets = {};
  final Map<int, Timer> _confirmationTimers = {};
  final Set<int> _timedOutRelays = {};
  final Map<int, String> _commandErrors = {};

  @override
  void dispose() {
    for (final timer in _confirmationTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mqttRelayStatesProvider, (previous, next) {
      next.whenData(_onRelayStates);
    });
    ref.listen(mqttConnectionProvider, (previous, next) {
      next.whenData((state) {
        if (state != BrokerConnectionState.connected) {
          _clearPendingCommands();
        }
      });
    });
    ref.listen(mqttDeviceStatusProvider, (previous, next) {
      next.whenData((online) {
        if (online != true) {
          _clearPendingCommands();
        }
      });
    });

    final service = ref.watch(mqttServiceProvider);
    final connection = ref
        .watch(mqttConnectionProvider)
        .maybeWhen(
          data: (state) => state,
          orElse: () => service.connectionState,
        );
    final deviceOnline = ref
        .watch(mqttDeviceStatusProvider)
        .maybeWhen(
          data: (online) => online,
          orElse: () => service.deviceOnline,
        );
    final relayStates = ref
        .watch(mqttRelayStatesProvider)
        .maybeWhen(data: (states) => states, orElse: () => service.relayStates);
    final appliances = ref.watch(appliancesProvider);

    return appliances.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          Center(child: Text('Could not load appliance settings: $error')),
      data: (items) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final appliance in items)
            _buildApplianceCard(
              appliance: appliance,
              relayState: relayStates[appliance.relay],
              connection: connection,
              deviceOnline: deviceOnline,
            ),
        ],
      ),
    );
  }

  Widget _buildApplianceCard({
    required Appliance appliance,
    required RelayState? relayState,
    required BrokerConnectionState connection,
    required bool? deviceOnline,
  }) {
    final pendingTarget = _pendingTargets[appliance.relay];
    final isPending = pendingTarget != null;
    final confirmed = relayState;
    final canControl =
        connection == BrokerConnectionState.connected &&
        deviceOnline == true &&
        confirmed != null &&
        !isPending;

    return Card(
      key: Key('appliance-card-${appliance.relay}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(appliance.icon, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appliance.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: Key('choose-appliance-icon-${appliance.relay}'),
                  tooltip: AppConstants.applianceIconLabel,
                  onPressed: () => _chooseIcon(appliance),
                  icon: const Icon(Icons.palette_outlined),
                ),
                IconButton(
                  key: Key('rename-appliance-${appliance.relay}'),
                  tooltip: AppConstants.applianceEditNameLabel,
                  onPressed: () => _renameAppliance(appliance),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildRelayStatus(appliance, confirmed)),
                if (isPending)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (confirmed != null)
                  Switch(
                    key: Key('relay-control-switch-${appliance.relay}'),
                    value: confirmed.isOn,
                    onChanged: canControl
                        ? (turnOn) => _sendRelayCommand(appliance.relay, turnOn)
                        : null,
                  ),
              ],
            ),
            if (isPending)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${AppConstants.relayPendingLabel}: '
                  '${pendingTarget ? 'ON' : 'OFF'}',
                ),
              )
            else if (_timedOutRelays.contains(appliance.relay))
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppConstants.relayNoResponseLabel,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_commandErrors[appliance.relay] case final error?)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!canControl && !isPending)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _controlUnavailableReason(connection, deviceOnline),
                ),
              ),
            SwitchListTile(
              key: Key('protected-switch-${appliance.relay}'),
              contentPadding: EdgeInsets.zero,
              title: const Text(AppConstants.protectedLabel),
              subtitle: const Text(
                'Keep marked for future alert rules; no automatic switching is active.',
              ),
              value: appliance.protected,
              onChanged: (value) =>
                  _saveAppliance(appliance.copyWith(protected: value)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelayStatus(Appliance appliance, RelayState? relayState) {
    if (relayState == null) {
      return Text(
        '${AppConstants.relayUnknownLabel} · Relay ${appliance.relay}',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(relayState.isOn ? 'ON' : 'OFF'),
        Text(
          AppConstants.relayConfirmedLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  String _controlUnavailableReason(
    BrokerConnectionState connection,
    bool? deviceOnline,
  ) {
    if (connection != BrokerConnectionState.connected) {
      return AppConstants.brokerUnavailableLabel;
    }
    if (deviceOnline == false) {
      return AppConstants.deviceOfflineLabel;
    }
    if (deviceOnline == null) {
      return AppConstants.deviceStatusUnknownLabel;
    }
    return AppConstants.relayUnknownLabel;
  }

  void _onRelayStates(Map<int, RelayState> states) {
    var changed = false;
    for (final relay in states.keys) {
      if (_timedOutRelays.remove(relay)) {
        _commandErrors.remove(relay);
        changed = true;
      }
    }
    for (final entry in _pendingTargets.entries.toList()) {
      if (states[entry.key]?.isOn == entry.value) {
        _confirmationTimers.remove(entry.key)?.cancel();
        _pendingTargets.remove(entry.key);
        _timedOutRelays.remove(entry.key);
        _commandErrors.remove(entry.key);
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  void _clearPendingCommands() {
    if (_pendingTargets.isEmpty && _confirmationTimers.isEmpty) {
      return;
    }
    for (final timer in _confirmationTimers.values) {
      timer.cancel();
    }
    _confirmationTimers.clear();
    _pendingTargets.clear();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendRelayCommand(int relay, bool turnOn) async {
    _confirmationTimers.remove(relay)?.cancel();
    setState(() {
      _pendingTargets[relay] = turnOn;
      _timedOutRelays.remove(relay);
      _commandErrors.remove(relay);
    });

    try {
      await ref
          .read(mqttServiceProvider)
          .publishTestRelayCommand(relay: relay, turnOn: turnOn);
      if (!mounted || !_pendingTargets.containsKey(relay)) {
        return;
      }
      _confirmationTimers[relay] = Timer(const Duration(seconds: 3), () {
        if (!mounted || !_pendingTargets.containsKey(relay)) {
          return;
        }
        setState(() {
          _pendingTargets.remove(relay);
          _confirmationTimers.remove(relay);
          _timedOutRelays.add(relay);
        });
      });
    } on StateError catch (error) {
      _showCommandError(relay, error);
    } on Exception catch (error) {
      _showCommandError(relay, error);
    }
  }

  void _showCommandError(int relay, Object error) {
    if (!mounted) {
      return;
    }
    _confirmationTimers.remove(relay)?.cancel();
    setState(() {
      _pendingTargets.remove(relay);
      _commandErrors[relay] = 'Could not send command: $error';
    });
  }

  Future<void> _renameAppliance(Appliance appliance) async {
    var editedName = appliance.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppConstants.applianceRenameTitle),
        content: TextFormField(
          initialValue: appliance.name,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) => editedName = value,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editedName),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _saveAppliance(appliance.copyWith(name: name.trim()));
  }

  Future<void> _chooseIcon(Appliance appliance) async {
    final options = <(String, String, IconData)>[
      ('Power', 'power', Icons.power_settings_new),
      ('Light', 'light', Icons.lightbulb_outline),
      ('Fan', 'fan', Icons.air),
      ('TV', 'tv', Icons.tv),
      ('Fridge', 'fridge', Icons.kitchen),
      ('Water heater', 'water', Icons.water),
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppConstants.applianceIconLabel),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, key, icon) in options)
              IconButton(
                tooltip: label,
                onPressed: () => Navigator.of(context).pop(key),
                icon: Icon(icon),
              ),
          ],
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    await _saveAppliance(appliance.copyWith(iconKey: selected));
  }

  Future<void> _saveAppliance(Appliance appliance) async {
    try {
      await ref.read(applianceRepositoryProvider).save(appliance);
      ref.invalidate(appliancesProvider);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save appliance: $error')),
        );
      }
    }
  }
}
