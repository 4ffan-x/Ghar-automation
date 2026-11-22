import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openPowerDatabase() async {
  final databasePath = path.join(
    await getDatabasesPath(),
    'ghar_power_history.db',
  );
  return openDatabase(
    databasePath,
    version: 3,
    onCreate: createPowerHistorySchema,
    onUpgrade: (database, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await createNilmSchema(database);
      }
      if (oldVersion < 3) {
        await createAlertSchema(database);
      }
    },
  );
}

Future<void> createPowerHistorySchema(
  DatabaseExecutor database,
  int version,
) async {
  await database.execute('''
    CREATE TABLE power_samples (
      timestamp_ms INTEGER PRIMARY KEY,
      voltage REAL NOT NULL,
      current REAL NOT NULL,
      watts REAL NOT NULL,
      kwh REAL NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE daily_energy (
      date TEXT PRIMARY KEY,
      energy_kwh REAL NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE energy_cursor (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      total_kwh REAL NOT NULL
    )
  ''');
  await database.execute(
    'CREATE INDEX power_samples_timestamp_idx ON power_samples(timestamp_ms)',
  );
  await createNilmSchema(database);
  await createAlertSchema(database);
}

Future<void> createNilmSchema(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE nilm_power_samples (
      timestamp_ms INTEGER PRIMARY KEY,
      watts REAL NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE nilm_relay_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      relay INTEGER NOT NULL,
      is_on INTEGER NOT NULL,
      timestamp_ms INTEGER NOT NULL,
      is_transition INTEGER NOT NULL,
      processed INTEGER NOT NULL
    )
  ''');
  await database.execute(
    'CREATE INDEX nilm_relay_events_timestamp_idx '
    'ON nilm_relay_events(timestamp_ms)',
  );
  await database.execute('''
    CREATE TABLE nilm_learned_samples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      relay INTEGER NOT NULL,
      watts REAL NOT NULL,
      timestamp_ms INTEGER NOT NULL
    )
  ''');
  await database.execute(
    'CREATE INDEX nilm_learned_samples_relay_idx '
    'ON nilm_learned_samples(relay, id)',
  );
}

Future<void> createAlertSchema(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE alert_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      occurred_at_ms INTEGER NOT NULL,
      acknowledged_at_ms INTEGER
    )
  ''');
  await database.execute(
    'CREATE INDEX alert_events_created_idx ON alert_events(occurred_at_ms DESC)',
  );
  await database.execute('''
    CREATE TABLE alert_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE alert_relay_state (
      relay INTEGER PRIMARY KEY,
      is_on INTEGER NOT NULL,
      on_since_ms INTEGER,
      heavy_alerted INTEGER NOT NULL DEFAULT 0
    )
  ''');
}
