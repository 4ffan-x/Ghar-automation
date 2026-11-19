class RelayState {
  const RelayState({
    required this.relay,
    required this.isOn,
    required this.receivedAt,
  });

  final int relay;
  final bool isOn;
  final DateTime receivedAt;
}

class PowerReading {
  const PowerReading({
    required this.voltage,
    required this.current,
    required this.watts,
    required this.kilowattHours,
    required this.receivedAt,
  });

  final double voltage;
  final double current;
  final double watts;
  final double kilowattHours;
  final DateTime receivedAt;
}

class GasStatus {
  const GasStatus({required this.leak, this.ppm});

  final bool leak;
  final double? ppm;
}
