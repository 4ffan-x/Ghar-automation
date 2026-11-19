import 'package:flutter_test/flutter_test.dart';
import 'package:ghar_app/core/mqtt_topics.dart';
import 'package:ghar_app/data/mqtt_message_parser.dart';

void main() {
  final receivedAt = DateTime.utc(2026, 1, 1);

  group('relay state parsing', () {
    test('accepts ON and OFF only for valid relay indices', () {
      final onState = MqttMessageParser.parseRelayState(
        relay: 1,
        payload: 'ON',
        receivedAt: receivedAt,
      );
      final offState = MqttMessageParser.parseRelayState(
        relay: 6,
        payload: ' OFF ',
        receivedAt: receivedAt,
      );

      expect(onState?.isOn, isTrue);
      expect(offState?.isOn, isFalse);
      expect(
        MqttMessageParser.parseRelayState(
          relay: 7,
          payload: 'ON',
          receivedAt: receivedAt,
        ),
        isNull,
      );
      expect(
        MqttMessageParser.parseRelayState(
          relay: 1,
          payload: 'maybe',
          receivedAt: receivedAt,
        ),
        isNull,
      );
    });

    test('routes only state topics for relay indices 1 through 6', () {
      const topics = MqttTopics(prefix: 'ghar');

      expect(topics.relayForStateTopic('ghar/relay/1/state'), 1);
      expect(topics.relayForStateTopic('ghar/relay/6/state'), 6);
      expect(topics.relayForStateTopic('ghar/relay/7/state'), isNull);
      expect(topics.relayForStateTopic('other/relay/1/state'), isNull);
    });
  });

  test('parses valid power readings and ignores malformed data', () {
    final reading = MqttMessageParser.parsePower(
      payload: '{"v":230.1,"a":1.2,"w":276,"kwh":12.4}',
      receivedAt: receivedAt,
    );

    expect(reading?.voltage, 230.1);
    expect(reading?.watts, 276);
    expect(reading?.kilowattHours, 12.4);
    expect(
      MqttMessageParser.parsePower(
        payload: '{"v":"230","a":1.2,"w":276,"kwh":12.4}',
        receivedAt: receivedAt,
      ),
      isNull,
    );
    expect(
      MqttMessageParser.parsePower(
        payload: '{not json',
        receivedAt: receivedAt,
      ),
      isNull,
    );
  });

  test('parses gas status and rejects a wrong leak type', () {
    expect(MqttMessageParser.parseGas('{"leak":true,"ppm":123}')?.leak, isTrue);
    expect(MqttMessageParser.parseGas('{"leak":"true"}'), isNull);
  });

  test('parses device availability tokens only', () {
    expect(MqttMessageParser.parseDeviceStatus('online'), isTrue);
    expect(MqttMessageParser.parseDeviceStatus('offline'), isFalse);
    expect(MqttMessageParser.parseDeviceStatus('unknown'), isNull);
  });
}
