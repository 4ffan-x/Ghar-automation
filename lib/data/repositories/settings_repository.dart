import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/mqtt_settings.dart';

class SettingsRepository {
  SettingsRepository(this._preferences);

  final SharedPreferences _preferences;

  static const _hostKey = 'mqtt.host';
  static const _portKey = 'mqtt.port';
  static const _usernameKey = 'mqtt.username';
  static const _passwordKey = 'mqtt.password';
  static const _useTlsKey = 'mqtt.useTls';
  static const _topicPrefixKey = 'mqtt.topicPrefix';

  MqttSettings load() {
    return MqttSettings(
      host: _preferences.getString(_hostKey) ?? '',
      port: _preferences.getInt(_portKey) ?? 1883,
      username: _preferences.getString(_usernameKey) ?? '',
      password: _preferences.getString(_passwordKey) ?? '',
      useTls: _preferences.getBool(_useTlsKey) ?? false,
      topicPrefix: _preferences.getString(_topicPrefixKey) ?? 'ghar',
    );
  }

  Future<void> save(MqttSettings settings) async {
    await _preferences.setString(_hostKey, settings.host.trim());
    await _preferences.setInt(_portKey, settings.port);
    await _preferences.setString(_usernameKey, settings.username.trim());
    await _preferences.setString(_passwordKey, settings.password);
    await _preferences.setBool(_useTlsKey, settings.useTls);
    await _preferences.setString(_topicPrefixKey, settings.topicPrefix.trim());
  }
}
