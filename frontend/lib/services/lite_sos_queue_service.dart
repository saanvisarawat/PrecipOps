import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class LiteSosRequest {
  final String clientId;
  final double latitude;
  final double longitude;
  final String description;

  const LiteSosRequest({
    required this.clientId,
    required this.latitude,
    required this.longitude,
    required this.description,
  });
}

/// sqflite-backed local queue for the Lite SOS endpoint (POST
/// /api/reports/lite) — the whole point of that endpoint is working on
/// poor/2G connectivity, so a single one-shot request that just fails
/// silently on a bad network defeats the purpose. Every lite SOS is
/// persisted here first (survives the app being killed mid-retry), then
/// [LiteSosController] keeps pinging the endpoint until it gets a
/// successful response, at which point the row is removed. Mirrors
/// `OfflineQueueService`'s pattern for the richer SOS flow.
class LiteSosQueueService {
  static const _dbName = 'floodops_lite_sos_queue.db';
  static const _table = 'queued_lite_sos';

  Database? _db;

  void _ensureDatabaseFactory() {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    } else if (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

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
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            description TEXT NOT NULL,
            queued_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> enqueue(LiteSosRequest request) async {
    try {
      final db = await _database;
      await db.insert(
        _table,
        {
          'client_id': request.clientId,
          'latitude': request.latitude,
          'longitude': request.longitude,
          'description': request.description,
          'queued_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // A platform without a working sqflite backend loses "survives app
      // restart" but the in-flight retry loop still works this session.
    }
  }

  Future<List<LiteSosRequest>> getAll() async {
    try {
      final db = await _database;
      final rows = await db.query(_table, orderBy: 'queued_at ASC');
      return rows
          .map((row) => LiteSosRequest(
                clientId: row['client_id'] as String,
                latitude: row['latitude'] as double,
                longitude: row['longitude'] as double,
                description: row['description'] as String,
              ))
          .toList();
    } catch (_) {
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

  Future<void> remove(String clientId) async {
    try {
      final db = await _database;
      await db.delete(_table, where: 'client_id = ?', whereArgs: [clientId]);
    } catch (_) {
      // Nothing to clean up if the store never worked in the first place.
    }
  }
}
