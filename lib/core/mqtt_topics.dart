class MqttTopics {
  const MqttTopics({this.prefix = 'ghar'});

  final String prefix;

  String relaySet(int relay) => '$prefix/relay/$relay/set';

  String relayState(int relay) => '$prefix/relay/$relay/state';

  String get relayStateWildcard => '$prefix/relay/+/state';

  String get power => '$prefix/power';

  String get gas => '$prefix/gas';

  String get status => '$prefix/status';
}
