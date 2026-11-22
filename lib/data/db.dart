import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openPowerDatabase() async {
  final databasePath = path.join(
    await getDatabasesPath(),
    'ghar_power_history.db',
  );
  return openDatabase(
    databasePath,
    version: 2,
    onCreate: createPowerHistorySchema,
    onUpgrade: (database, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await createNilmSchema(database);
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
