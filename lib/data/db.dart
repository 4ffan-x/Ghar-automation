import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

Future<Database> openPowerDatabase() async {
  final databasePath = path.join(
    await getDatabasesPath(),
    'ghar_power_history.db',
  );
  return openDatabase(
    databasePath,
    version: 1,
    onCreate: createPowerHistorySchema,
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
}
