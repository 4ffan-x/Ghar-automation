import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/models/alert_record.dart';

abstract interface class AlertNotifier {
  Future<void> initialize();

  Future<bool> requestNotificationPermission();

  Future<bool?> requestFullScreenIntentPermission();

  Future<void> showAlert(AlertRecord alert);

  Future<void> repeatGasAlert(AlertRecord alert);

  Future<void> cancelAlert(AlertRecord alert);
}

class AlertNotificationService implements AlertNotifier {
  AlertNotificationService(this._plugin);

  static const _gasChannelId = 'ghar_gas_critical_v1';
  static const _generalChannelId = 'ghar_home_alerts_v1';
  static const _gasNotificationId = 94001;

  final FlutterLocalNotificationsPlugin _plugin;
  AndroidFlutterLocalNotificationsPlugin? _androidPlugin;

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    _androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await _androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _gasChannelId,
        'Critical gas alerts',
        channelDescription:
            'Urgent gas leak warnings. Sound and vibration repeat until '
            'the alert is acknowledged.',
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
      ),
    );
    await _androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _generalChannelId,
        'Home safety alerts',
        channelDescription:
            'Heavy use, high power, and ESP32 connection warnings.',
        importance: Importance.high,
        enableVibration: true,
      ),
    );
  }

  @override
  Future<bool> requestNotificationPermission() async =>
      await _androidPlugin?.requestNotificationsPermission() ?? true;

  @override
  Future<bool?> requestFullScreenIntentPermission() =>
      _androidPlugin?.requestFullScreenIntentPermission() ??
      Future<bool?>.value(null);

  @override
  Future<void> showAlert(AlertRecord alert) async {
    final isGas = alert.type == AlertType.gasLeak;
    await _plugin.show(
      id: isGas ? _gasNotificationId : _notificationIdFor(alert.id),
      title: alert.title,
      body: alert.message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isGas ? _gasChannelId : _generalChannelId,
          isGas ? 'Critical gas alerts' : 'Home safety alerts',
          channelDescription: isGas
              ? 'Urgent gas leak warnings.'
              : 'Household monitoring warnings.',
          importance: isGas ? Importance.max : Importance.high,
          priority: isGas ? Priority.max : Priority.high,
          category: isGas
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.status,
          fullScreenIntent: isGas,
          ongoing: isGas,
          autoCancel: !isGas,
          playSound: true,
          audioAttributesUsage: isGas
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          enableVibration: true,
          vibrationPattern: isGas
              ? Int64List.fromList([0, 500, 250, 500])
              : null,
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(alert.message),
        ),
      ),
      payload: alert.id.toString(),
    );
  }

  @override
  Future<void> repeatGasAlert(AlertRecord alert) async {
    if (alert.type != AlertType.gasLeak) {
      throw ArgumentError.value(alert.type, 'alert.type', 'Must be gasLeak.');
    }
    await _plugin.cancel(id: _gasNotificationId);
    await showAlert(alert);
  }

  @override
  Future<void> cancelAlert(AlertRecord alert) async {
    await _plugin.cancel(
      id: alert.type == AlertType.gasLeak
          ? _gasNotificationId
          : _notificationIdFor(alert.id),
    );
  }

  int _notificationIdFor(int alertId) => 100000 + alertId;
}
