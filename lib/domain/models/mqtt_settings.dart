class MqttSettings {
  const MqttSettings({
    this.host = '',
    this.port = 1883,
    this.username = '',
    this.password = '',
    this.useTls = false,
    this.topicPrefix = 'ghar',
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final bool useTls;
  final String topicPrefix;

  void validate() {
    if (host.trim().isEmpty) {
      throw const FormatException('Enter the broker host name or IP address.');
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Port must be between 1 and 65535.');
    }
    if (topicPrefix.trim().isEmpty ||
        topicPrefix.contains(RegExp(r'[/+#\s]'))) {
      throw const FormatException(
        'Topic prefix must be one topic segment without spaces, /, +, or #.',
      );
    }
  }
}
