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
}
