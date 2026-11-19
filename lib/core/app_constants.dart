abstract final class AppConstants {
  static const appName = 'Ghar';

  static const controlTab = 'Control';
  static const monitorTab = 'Monitor';
  static const insightsTab = 'Insights';
  static const settingsTab = 'Settings';

  static const tabLabels = [controlTab, monitorTab, insightsTab, settingsTab];

  static const brokerSettingsTitle = 'MQTT broker';
  static const brokerHostLabel = 'Broker host or IP address';
  static const brokerPortLabel = 'Port';
  static const brokerUsernameLabel = 'Username (optional)';
  static const brokerPasswordLabel = 'Password (optional)';
  static const topicPrefixLabel = 'Topic prefix';
  static const tlsLabel = 'Use TLS';
  static const connectAndSaveLabel = 'Save and connect';
  static const disconnectLabel = 'Disconnect';
  static const mqttTestTitle = 'Connection test';
  static const relayOneConfirmedLabel = 'Last confirmed Relay 1 state';
  static const noRelayConfirmationLabel = 'No relay state received yet';
  static const mqttDebugOnLabel = 'Send test ON';
  static const mqttDebugOffLabel = 'Send test OFF';
  static const brokerConnectedLabel = 'Connected';
  static const brokerConnectingLabel = 'Connecting';
  static const brokerDisconnectedLabel = 'Disconnected';
  static const deviceOfflineLabel = 'Device offline';
  static const applianceEditNameLabel = 'Edit name';
  static const applianceRenameTitle = 'Appliance name';
  static const applianceIconLabel = 'Change icon';
  static const protectedLabel = 'Protected (never auto-off)';
  static const relayUnknownLabel = 'Waiting for ESP32 state';
  static const brokerUnavailableLabel = 'Broker is not connected';
  static const deviceStatusUnknownLabel = 'Waiting for ESP32 online status';
  static const relayPendingLabel = 'Waiting for confirmation';
  static const relayNoResponseLabel = 'No response. You can try again.';
  static const relayConfirmedLabel = 'Last confirmed by ESP32';
  static const relayCardRetryLabel = 'Retry relay command';
}
