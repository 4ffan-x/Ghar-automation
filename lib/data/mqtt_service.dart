import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../core/mqtt_topics.dart';
import '../domain/models/mqtt_readings.dart';
import '../domain/models/mqtt_settings.dart';
import 'mqtt_message_parser.dart';
import 'repositories/settings_repository.dart';

enum BrokerConnectionState { disconnected, connecting, connected }

class MqttService {
  MqttService({this.settingsRepository, this.settings = const MqttSettings()});

  final SettingsRepository? settingsRepository;
  MqttSettings settings;

  BrokerConnectionState _connectionState = BrokerConnectionState.disconnected;
  bool? _deviceOnline;
  PowerReading? _latestPower;
  GasStatus? _latestGas;
  final Map<int, RelayState> _relayStates = {};
  String? _lastError;

  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage?>>?>?
  _updatesSubscription;
  Timer? _reconnectTimer;
  int _generation = 0;
  int _retryAttempt = 0;
  bool _shouldReconnect = false;

  final _connectionController =
      StreamController<BrokerConnectionState>.broadcast(sync: true);
  final _deviceOnlineController = StreamController<bool?>.broadcast(sync: true);
  final _powerController = StreamController<PowerReading?>.broadcast(
    sync: true,
  );
  final _gasController = StreamController<GasStatus?>.broadcast(sync: true);
  final _relayStatesController =
      StreamController<Map<int, RelayState>>.broadcast(sync: true);
  final _errorController = StreamController<String?>.broadcast(sync: true);

  BrokerConnectionState get connectionState => _connectionState;
  bool? get deviceOnline => _deviceOnline;
  PowerReading? get latestPower => _latestPower;
  GasStatus? get latestGas => _latestGas;
  Map<int, RelayState> get relayStates => Map.unmodifiable(_relayStates);
  String? get lastError => _lastError;

  Stream<BrokerConnectionState> get connectionStatusStream =>
      _withCurrent(_connectionState, _connectionController.stream);

  Stream<bool?> get deviceStatusStream =>
      _withCurrent(_deviceOnline, _deviceOnlineController.stream);

  Stream<PowerReading?> get powerReadings =>
      _withCurrent(_latestPower, _powerController.stream);

  Stream<GasStatus?> get gasStatuses =>
      _withCurrent(_latestGas, _gasController.stream);

  Stream<Map<int, RelayState>> get relayStateUpdates =>
      _withCurrent(relayStates, _relayStatesController.stream);

  Stream<String?> get connectionErrors =>
      _withCurrent(_lastError, _errorController.stream);

  Future<void> saveAndConnect(MqttSettings newSettings) async {
    newSettings.validate();
    final repository = settingsRepository;
    if (repository == null) {
      throw StateError('MQTT settings storage is not configured.');
    }

    await repository.save(newSettings);
    settings = newSettings;
    await connect();
  }

  Future<void> connect() async {
    settings.validate();
    _generation++;
    _shouldReconnect = true;
    _retryAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _clearDeviceData();
    await _disconnectClient();
    await _connectOnce(_generation);
  }

  Future<void> disconnect() async {
    _generation++;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _disconnectClient();
    _setConnectionState(BrokerConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connectionController.close();
    await _deviceOnlineController.close();
    await _powerController.close();
    await _gasController.close();
    await _relayStatesController.close();
    await _errorController.close();
  }

  Future<void> publishTestRelayCommand({
    required int relay,
    required bool turnOn,
  }) async {
    if (relay < 1 || relay > 6) {
      throw ArgumentError.value(relay, 'relay', 'Must be between 1 and 6.');
    }
    final client = _client;
    if (_connectionState != BrokerConnectionState.connected || client == null) {
      throw StateError('Connect to the broker before sending a test command.');
    }

    final payload = MqttClientPayloadBuilder()
      ..addString(turnOn ? 'ON' : 'OFF');
    final topics = MqttTopics(prefix: settings.topicPrefix);
    client.publishMessage(
      topics.relaySet(relay),
      MqttQos.atLeastOnce,
      payload.payload!,
      retain: false,
    );
  }

  Future<void> _connectOnce(int generation) async {
    if (!_shouldReconnect || generation != _generation) {
      return;
    }

    _setConnectionState(BrokerConnectionState.connecting);
    final clientId = _newClientId();
    final client =
        MqttServerClient(
            settings.host.trim(),
            clientId,
            maxConnectionAttempts: 1,
          )
          ..port = settings.port
          ..secure = settings.useTls
          ..keepAlivePeriod = 25
          ..connectTimeoutPeriod = 5000
          ..connectionTimeout = 8000
          ..autoReconnect = false
          ..logging(on: false);

    client.setProtocolV311();
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();
    client.onDisconnected = () {
      if (!identical(_client, client) || generation != _generation) {
        return;
      }
      _client = null;
      unawaited(_updatesSubscription?.cancel());
      _updatesSubscription = null;
      _setConnectionState(BrokerConnectionState.disconnected);
      _scheduleReconnect(generation);
    };
    _client = client;

    try {
      final username = settings.username.trim();
      final password = settings.password;
      final status = await client.connect(
        username.isEmpty ? null : username,
        password.isEmpty ? null : password,
      );
      if (generation != _generation || !_shouldReconnect) {
        client.disconnect();
        return;
      }
      if (status == null || status.state != MqttConnectionState.connected) {
        throw Exception('Broker rejected the connection: $status');
      }

      _retryAttempt = 0;
      _lastError = null;
      _errorController.add(null);
      _listenForMessages(client);
      _subscribe(client);
      _setConnectionState(BrokerConnectionState.connected);
    } on Exception catch (error) {
      debugPrint('MQTT connection failed: $error');
      if (identical(_client, client) && generation == _generation) {
        _client = null;
        await _updatesSubscription?.cancel();
        _updatesSubscription = null;
        client.disconnect();
        _lastError = error.toString();
        _errorController.add(_lastError);
        _setConnectionState(BrokerConnectionState.disconnected);
        _scheduleReconnect(generation);
      }
    }
  }

  void _subscribe(MqttServerClient client) {
    final topics = MqttTopics(prefix: settings.topicPrefix);
    client.subscribe(topics.relayStateWildcard, MqttQos.atMostOnce);
    client.subscribe(topics.power, MqttQos.atMostOnce);
    client.subscribe(topics.gas, MqttQos.atMostOnce);
    client.subscribe(topics.status, MqttQos.atMostOnce);
  }

  void _listenForMessages(MqttServerClient client) {
    _updatesSubscription = client.updates?.listen((messages) {
      for (final message in messages) {
        final payload = message.payload;
        if (payload is! MqttPublishMessage) {
          _logInvalidMessage(message.topic);
          continue;
        }
        final text = MqttPublishPayload.bytesToStringAsString(
          payload.payload.message,
        );
        _handleMessage(message.topic, text);
      }
    });
  }

  void _handleMessage(String topic, String payload) {
    final topics = MqttTopics(prefix: settings.topicPrefix);
    final relay = topics.relayForStateTopic(topic);
    if (relay != null) {
      final state = MqttMessageParser.parseRelayState(
        relay: relay,
        payload: payload,
        receivedAt: DateTime.now(),
      );
      if (state == null) {
        _logInvalidMessage(topic);
        return;
      }
      _relayStates[relay] = state;
      _relayStatesController.add(relayStates);
      return;
    }

    if (topic == topics.power) {
      final reading = MqttMessageParser.parsePower(
        payload: payload,
        receivedAt: DateTime.now(),
      );
      if (reading == null) {
        _logInvalidMessage(topic);
        return;
      }
      _latestPower = reading;
      _powerController.add(reading);
      return;
    }

    if (topic == topics.gas) {
      final gas = MqttMessageParser.parseGas(payload);
      if (gas == null) {
        _logInvalidMessage(topic);
        return;
      }
      _latestGas = gas;
      _gasController.add(gas);
      return;
    }

    if (topic == topics.status) {
      final online = MqttMessageParser.parseDeviceStatus(payload);
      if (online == null) {
        _logInvalidMessage(topic);
        return;
      }
      _deviceOnline = online;
      _deviceOnlineController.add(online);
      return;
    }

    debugPrint('Ignoring MQTT message on unexpected topic: $topic');
  }

  void _scheduleReconnect(int generation) {
    if (!_shouldReconnect ||
        generation != _generation ||
        _reconnectTimer != null) {
      return;
    }

    final delaySeconds = min(30, 1 << min(_retryAttempt, 5));
    _retryAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      unawaited(_connectOnce(generation));
    });
  }

  Future<void> _disconnectClient() async {
    final client = _client;
    _client = null;
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    client?.disconnect();
  }

  void _clearDeviceData() {
    _deviceOnline = null;
    _latestPower = null;
    _latestGas = null;
    _relayStates.clear();
    _deviceOnlineController.add(null);
    _powerController.add(null);
    _gasController.add(null);
    _relayStatesController.add(relayStates);
  }

  void _setConnectionState(BrokerConnectionState state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  void _logInvalidMessage(String topic) {
    debugPrint('Ignoring invalid MQTT payload on topic $topic.');
  }

  String _newClientId() {
    final randomPart = Random.secure().nextInt(0x100000000).toRadixString(16);
    return 'ghar-app-${randomPart.padLeft(8, '0')}';
  }

  static Stream<T> _withCurrent<T>(T current, Stream<T> updates) {
    return Stream<T>.multi((controller) {
      controller.add(current);
      final subscription = updates.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    });
  }
}
