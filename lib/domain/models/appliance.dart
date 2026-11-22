import 'package:material_ui/material_ui.dart';

class Appliance {
  const Appliance({
    required this.relay,
    required this.name,
    required this.iconKey,
    required this.protected,
    this.manualWattage,
  });

  final int relay;
  final String name;
  final String iconKey;
  final bool protected;
  final double? manualWattage;

  IconData get icon => switch (iconKey) {
    'light' => Icons.lightbulb_outline,
    'fan' => Icons.air,
    'tv' => Icons.tv,
    'fridge' => Icons.kitchen,
    'water' => Icons.water,
    _ => Icons.power_settings_new,
  };

  Appliance copyWith({
    String? name,
    String? iconKey,
    bool? protected,
    double? manualWattage,
    bool clearManualWattage = false,
  }) {
    return Appliance(
      relay: relay,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      protected: protected ?? this.protected,
      manualWattage: clearManualWattage
          ? null
          : manualWattage ?? this.manualWattage,
    );
  }

  static List<Appliance> defaults() {
    return List.generate(
      6,
      (index) => Appliance(
        relay: index + 1,
        name: 'Relay ${index + 1}',
        iconKey: 'power',
        protected: false,
      ),
    );
  }
}
