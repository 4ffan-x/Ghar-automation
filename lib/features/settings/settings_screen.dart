import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/app_constants.dart';
import '../../data/monitor_providers.dart';
import '../../data/mqtt_providers.dart';
import '../../data/mqtt_service.dart';
import '../../domain/models/mqtt_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _topicPrefixController;
  late final TextEditingController _tariffController;
  late bool _useTls;
  bool _saving = false;
  String? _message;
  String? _tariffMessage;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(mqttServiceProvider).settings;
    _hostController = TextEditingController(text: settings.host);
    _portController = TextEditingController(text: settings.port.toString());
    _usernameController = TextEditingController(text: settings.username);
    _passwordController = TextEditingController(text: settings.password);
    _topicPrefixController = TextEditingController(text: settings.topicPrefix);
    _tariffController = TextEditingController(
      text: ref.read(settingsRepositoryProvider).loadEnergyTariff().toString(),
    );
    _useTls = settings.useTls;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _topicPrefixController.dispose();
    _tariffController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(mqttServiceProvider);
    final connection = ref
        .watch(mqttConnectionProvider)
        .maybeWhen(
          data: (state) => state,
          orElse: () => service.connectionState,
        );
    final relayStates = ref
        .watch(mqttRelayStatesProvider)
        .maybeWhen(data: (states) => states, orElse: () => service.relayStates);
    final relayOne = relayStates[1];
    final power = ref
        .watch(mqttPowerProvider)
        .maybeWhen(
          data: (reading) => reading,
          orElse: () => service.latestPower,
        );
    final gas = ref
        .watch(mqttGasProvider)
        .maybeWhen(data: (status) => status, orElse: () => service.latestGas);
    final connectionError = ref
        .watch(mqttErrorProvider)
        .maybeWhen(data: (error) => error, orElse: () => service.lastError);
    final connected = connection == BrokerConnectionState.connected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          AppConstants.brokerSettingsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: AppConstants.brokerHostLabel,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a broker host or IP address.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: AppConstants.brokerPortLabel,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final port = int.tryParse(value ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return 'Enter a port from 1 to 65535.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: AppConstants.brokerUsernameLabel,
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: AppConstants.brokerPasswordLabel,
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _topicPrefixController,
                decoration: const InputDecoration(
                  labelText: AppConstants.topicPrefixLabel,
                  helperText: 'Default: ghar',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final prefix = value?.trim() ?? '';
                  if (prefix.isEmpty || prefix.contains(RegExp(r'[/+#\s]'))) {
                    return 'Use one topic segment without spaces, /, +, or #.';
                  }
                  return null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(AppConstants.tlsLabel),
                subtitle: const Text(
                  'Use secure MQTT/TLS. The broker must support TLS.',
                ),
                value: _useTls,
                onChanged: (value) => setState(() => _useTls = value),
              ),
            ],
          ),
        ),
        if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
        if (connectionError != null) ...[
          const SizedBox(height: 8),
          Text(
            'Connection error: $connectionError',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveAndConnect,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text(AppConstants.connectAndSaveLabel),
        ),
        OutlinedButton.icon(
          onPressed: connected
              ? () async {
                  await service.disconnect();
                  if (mounted) {
                    setState(() => _message = 'Disconnected from the broker.');
                  }
                }
              : null,
          icon: const Icon(Icons.link_off),
          label: const Text(AppConstants.disconnectLabel),
        ),
        const SizedBox(height: 24),
        Text(
          AppConstants.energyTariffTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('energy-tariff-field'),
          controller: _tariffController,
          decoration: const InputDecoration(
            labelText: AppConstants.energyTariffLabel,
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (_tariffMessage != null) ...[
          const SizedBox(height: 8),
          Text(_tariffMessage!),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _saveTariff,
          icon: const Icon(Icons.currency_rupee),
          label: const Text(AppConstants.energyTariffSaveLabel),
        ),
        const SizedBox(height: 24),
        Text(
          AppConstants.mqttTestTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppConstants.relayOneConfirmedLabel),
                const SizedBox(height: 4),
                Text(
                  relayOne == null
                      ? AppConstants.noRelayConfirmationLabel
                      : relayOne.isOn
                      ? 'ON'
                      : 'OFF',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: connected
                          ? () => _sendTestCommand(true)
                          : null,
                      child: const Text(AppConstants.mqttDebugOnLabel),
                    ),
                    OutlinedButton(
                      onPressed: connected
                          ? () => _sendTestCommand(false)
                          : null,
                      child: const Text(AppConstants.mqttDebugOffLabel),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  power == null
                      ? 'Power: no reading received'
                      : 'Power: ${power.watts.toStringAsFixed(1)} W · '
                            '${power.voltage.toStringAsFixed(1)} V · '
                            '${power.current.toStringAsFixed(2)} A · '
                            '${power.kilowattHours.toStringAsFixed(2)} kWh',
                ),
                const SizedBox(height: 4),
                Text(
                  gas == null
                      ? 'Gas: no reading received'
                      : 'Gas: ${gas.leak ? 'LEAK' : 'clear'}'
                            '${gas.ppm == null ? '' : ' · ${gas.ppm!.toStringAsFixed(0)} ppm'}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveAndConnect() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final settings = MqttSettings(
      host: _hostController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      useTls: _useTls,
      topicPrefix: _topicPrefixController.text.trim(),
    );

    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await ref.read(mqttServiceProvider).saveAndConnect(settings);
      if (mounted) {
        setState(
          () => _message = 'Settings saved. Connection attempt started.',
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _sendTestCommand(bool turnOn) async {
    try {
      await ref
          .read(mqttServiceProvider)
          .publishTestRelayCommand(relay: 1, turnOn: turnOn);
      if (mounted) {
        setState(() {
          _message =
              'Test ${turnOn ? 'ON' : 'OFF'} command sent. '
              'The displayed relay state changes only after ESP32 confirmation.';
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    }
  }

  Future<void> _saveTariff() async {
    final tariff = double.tryParse(_tariffController.text.trim());
    if (tariff == null || !tariff.isFinite || tariff < 0) {
      setState(() {
        _tariffMessage = 'Enter a valid non-negative tariff.';
      });
      return;
    }

    try {
      await ref.read(settingsRepositoryProvider).saveEnergyTariff(tariff);
      ref.invalidate(energyTariffProvider);
      if (mounted) {
        setState(() {
          _tariffMessage = 'Tariff saved.';
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _tariffMessage = 'Could not save tariff: $error');
      }
    }
  }
}
