enum AlertType { gasLeak, heavyUse, loadLimit, deviceOffline }

class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.occurredAt,
    required this.acknowledgedAt,
  });

  final int id;
  final AlertType type;
  final String title;
  final String message;
  final DateTime occurredAt;
  final DateTime? acknowledgedAt;

  bool get isAcknowledged => acknowledgedAt != null;

  factory AlertRecord.fromRow(Map<String, Object?> row) {
    final typeName = row['type']! as String;
    return AlertRecord(
      id: row['id']! as int,
      type: AlertType.values.byName(typeName),
      title: row['title']! as String,
      message: row['message']! as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        row['occurred_at_ms']! as int,
      ),
      acknowledgedAt: row['acknowledged_at_ms'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              row['acknowledged_at_ms']! as int,
            ),
    );
  }
}
