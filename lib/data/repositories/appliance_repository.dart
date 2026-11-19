import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/appliance.dart';

class ApplianceRepository {
  ApplianceRepository(this._preferences);

  final SharedPreferences _preferences;

  Future<List<Appliance>> loadAll() async {
    final defaults = Appliance.defaults();
    return List.generate(6, (index) {
      final relay = index + 1;
      final defaultAppliance = defaults[index];
      return Appliance(
        relay: relay,
        name:
            _preferences.getString(_key(relay, 'name')) ??
            defaultAppliance.name,
        iconKey:
            _preferences.getString(_key(relay, 'icon')) ??
            defaultAppliance.iconKey,
        protected: _preferences.getBool(_key(relay, 'protected')) ?? false,
      );
    });
  }

  Future<void> save(Appliance appliance) async {
    if (appliance.relay < 1 || appliance.relay > 6) {
      throw ArgumentError.value(
        appliance.relay,
        'relay',
        'Must be between 1 and 6.',
      );
    }

    await _preferences.setString(
      _key(appliance.relay, 'name'),
      appliance.name.trim(),
    );
    await _preferences.setString(
      _key(appliance.relay, 'icon'),
      appliance.iconKey,
    );
    await _preferences.setBool(
      _key(appliance.relay, 'protected'),
      appliance.protected,
    );
  }

  static String _key(int relay, String property) =>
      'appliance.$relay.$property';
}
