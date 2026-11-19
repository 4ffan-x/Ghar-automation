import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_constants.dart';
import 'mqtt_providers.dart';
import 'mqtt_service.dart';

class MqttStatusChip extends ConsumerWidget {
  const MqttStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final (label, icon) = switch (connection) {
      BrokerConnectionState.connecting => (
        AppConstants.brokerConnectingLabel,
        Icons.sync,
      ),
      BrokerConnectionState.connected when deviceOnline == false => (
        AppConstants.deviceOfflineLabel,
        Icons.cloud_off,
      ),
      BrokerConnectionState.connected => (
        AppConstants.brokerConnectedLabel,
        Icons.cloud_done,
      ),
      BrokerConnectionState.disconnected => (
        AppConstants.brokerDisconnectedLabel,
        Icons.cloud_off,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
