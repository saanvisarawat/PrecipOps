import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../api/models/report_models.dart';

/// sqflite's default `databaseFactory` only works on Android/iOS/macOS.
/// This app also needs to run in this dev environment's Windows desktop
/// and Chrome targets, so pick an ffi-backed factory there. Real mobile
/// builds never hit these branches.
void _ensureDatabaseFactory() {
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

/// Real (not mocked) local offline queue for SOS reports, backed by
/// sqflite. When the device has no connectivity, [SosController] writes
/// here instead of calling the API. When connectivity returns, the queue
/// is drained via `PreciopsApi.bulkSyncReports` and rows are deleted.
class OfflineQueueService {
  static const _dbName = 'floodops_offline_queue.db';
  static const _table = 'queued_reports';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _ensureDatabaseFactory();
    final dbPath = kIsWeb ? '' : await getDatabasesPath();
    final path = kIsWeb ? _dbName : p.join(dbPath, _dbName);
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            client_id TEXT PRIMARY KEY,
            description TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            client_timestamp TEXT NOT NULL,
            queued_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> enqueue(CreateReportRequest request) async {
    final db = await _database;
    await db.insert(
      _table,
      {
        'client_id': request.clientId,
        'description': request.description,
        'latitude': request.latitude,
        'longitude': request.longitude,
        'client_timestamp': request.clientTimestamp.toIso8601String(),
        'queued_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<CreateReportRequest>> getAll() async {
    try {
      final db = await _database;
      final rows = await db.query(_table, orderBy: 'queued_at ASC');
      return rows
          .map((row) => CreateReportRequest(
                clientId: row['client_id'] as String,
                description: row['description'] as String,
                latitude: row['latitude'] as double,
                longitude: row['longitude'] as double,
                clientTimestamp: DateTime.parse(row['client_timestamp'] as String),
              ))
          .toList();
    } catch (_) {
      // Platforms without a working sqflite backend (e.g. this dev
      // sandbox's web target without the ffi_web worker assets set up)
      // degrade to an empty queue instead of crashing the screen.
      return [];
    }
  }

  Future<int> count() async {
    try {
      final db = await _database;
      final result = await db.rawQuery('SELECT COUNT(*) as c FROM $_table');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> removeByClientIds(List<String> clientIds) async {
    if (clientIds.isEmpty) return;
    final db = await _database;
    final placeholders = List.filled(clientIds.length, '?').join(',');
    await db.delete(_table, where: 'client_id IN ($placeholders)', whereArgs: clientIds);
  }

  Future<void> clear() async {
    final db = await _database;
    await db.delete(_table);
  }
}
