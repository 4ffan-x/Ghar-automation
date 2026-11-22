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
  static const energyTariffTitle = 'Energy tariff';
  static const energyTariffLabel = 'Price per unit (Rs/kWh)';
  static const energyTariffSaveLabel = 'Save tariff';
  static const monitorWaitingForPower = 'Waiting for power readings';
  static const monitorChartTitle = 'Power history · last 30 minutes';
  static const monitorNoHistory = 'No saved power samples yet';
  static const monitorHistoryLabel = 'Saved samples in chart';
  static const monitorTodayEnergy = 'Today';
  static const monitorMonthEnergy = 'This month';
  static const monitorTodayBill = 'Estimated today bill';
  static const monitorMonthBill = 'Estimated month bill';
  static const monitorHistoryError = 'Could not load power history';
  static const monitorEnergyError = 'Could not load energy summary';
  static const insightsLoading = 'Loading appliance insights...';
  static const insightsError = 'Could not load appliance insights';
  static const insightsTitle = 'Appliance energy estimates · today';
  static const insightsNoMeterEnergy =
      'No measured energy has been recorded today yet.';
  static const insightsMeasuredEnergy = 'Measured energy today';
  static const insightsEstimatedEnergy = 'Estimated appliance energy';
  static const insightsFromRelays = 'from relay estimates';
  static const insightsOtherUnknown = 'Other / unknown';
  static const insightsOtherDescription =
      'The meter energy not explained by relay estimates. This can include '
      'variable loads, manually switched devices, and estimation error.';
  static const insightsNoWattage = 'Not learned yet';
  static const insightsConfidence = 'Confidence';
  static const insightsLowConfidenceReason =
      'Protected or variable loads can change independently, so attribution '
      'is less reliable.';
  static const insightsLowConfidenceLabel = 'Low · protected or variable load';
  static const insightsHighConfidenceLabel = 'High';
  static const insightsMediumConfidenceLabel = 'Medium';
  static const insightsLowConfidenceShortLabel = 'Low';
  static const insightsManualConfidenceLabel = 'Manual override';
  static const insightsTypicalPower = 'Typical power';
  static const insightsManualSuffix = 'manual override';
  static const insightsLearningSamples = 'learning sample(s)';
  static const insightsSpread = 'spread';
  static const insightsTodaySuffix = 'kWh today';
  static const insightsMismatchLabel = 'Mismatch';
  static const insightsLearningHelp =
      'The app compares total power just before and after a confirmed relay '
      'change. Unstable, overlapping, or very small changes are not learned.';
  static const insightsModelExcess =
      'Appliance estimates exceed the meter total; the difference is shown '
      'as a model mismatch, not hidden.';
  static const insightsOverrideLabel = 'Manual wattage override';
  static const insightsEditOverride = 'Set wattage override';
  static const insightsClearOverride = 'Clear override';
  static const insightsOverrideHint =
      'Enter a known appliance wattage in watts. Leave blank to clear.';
  static const insightsOverrideSaveError = 'Could not save wattage override';
  static const insightsWattageInputLabel = 'Wattage (W)';
  static const insightsLearnedEstimateLabel = 'Learned estimate';
  static const insightsOverrideInvalid =
      'Enter a finite wattage of 0 or greater.';
  static const insightsSaveLabel = 'Save';
  static const insightsCancelLabel = 'Cancel';
  static const insightsRetryLabel = 'Retry';
}
