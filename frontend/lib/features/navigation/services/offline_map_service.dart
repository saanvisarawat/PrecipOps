import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../models/offline_region.dart';
import 'tile_math.dart';

class InsufficientStorageException implements Exception {
  const InsufficientStorageException();
}

/// Default zoom range for a downloaded district: 10 (regional overview)
/// through 14 (street-level in towns) — enough to pan/zoom a shelter's
/// neighborhood offline without downloading tens of thousands of tiles.
const int kOfflineMinZoom = 10;
const int kOfflineMaxZoom = 14;

/// Downloads, stores and serves OSM raster tiles for offline use.
///
/// Tiles live once on disk at `<support dir>/offline_tiles/{z}/{x}/{y}.png`
/// regardless of which region(s) requested them — a `region_tiles` join
/// table tracks which regions reference which tile so overlapping regions
/// never redownload a tile the other already has, and deleting a region
/// only removes tiles no other region still needs.
///
/// LIMITATION: this caches map *imagery* for offline browsing. It does not
/// give the app a road graph, so it cannot power real offline turn-by-turn
/// routing — see [StraightLineRoutingService] in routing_service.dart for
/// the offline routing fallback, and the plan notes in the PR description
/// for what a real offline routing engine would additionally require.
class OfflineMapService {
  static const _dbName = 'floodops_offline_maps.db';
  static const _regionsTable = 'offline_regions';
  static const _tilesTable = 'region_tiles';
  static const _tileUrlTemplate = 'https://tile.openstreetmap.org';
  // OSM's tile usage policy requires a descriptive User-Agent identifying
  // the app — anonymous/browser-spoofed UAs risk being rate-limited.
  static const _userAgent = 'Preciops/1.0 (offline-map-download)';

  Database? _db;
  Directory? _tileDir;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'User-Agent': _userAgent},
    responseType: ResponseType.bytes,
  ));
  final Set<String> _cancelledRegionIds = {};

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
          CREATE TABLE $_regionsTable (
            id TEXT PRIMARY KEY,
            district_name TEXT NOT NULL,
            north REAL NOT NULL,
            south REAL NOT NULL,
            east REAL NOT NULL,
            west REAL NOT NULL,
            min_zoom INTEGER NOT NULL,
            max_zoom INTEGER NOT NULL,
            total_tiles INTEGER NOT NULL,
            downloaded_tiles INTEGER NOT NULL,
            bytes INTEGER NOT NULL,
            status TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_tilesTable (
            region_id TEXT NOT NULL,
            z INTEGER NOT NULL,
            x INTEGER NOT NULL,
            y INTEGER NOT NULL,
            PRIMARY KEY (region_id, z, x, y)
          )
        ''');
      },
    );
    return _db!;
  }

  Future<Directory> get _tilesDirectory async {
    if (_tileDir != null) return _tileDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'offline_tiles'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _tileDir = dir;
    return dir;
  }

  File _tileFile(Directory dir, TileCoord t) => File(p.join(dir.path, '${t.z}', '${t.x}', '${t.y}.png'));

  bool _looksLikeValidPng(Uint8List bytes) =>
      bytes.length > 200 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;

  /// Read a cached tile's bytes, or null if not cached / corrupted.
  Future<Uint8List?> readTile(TileCoord t) async {
    try {
      final file = _tileFile(await _tilesDirectory, t);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (!_looksLikeValidPng(bytes)) return null;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Write-through cache used by [OfflineTileProvider] while browsing
  /// online — seeds the shared tile cache organically so a later region
  /// download skips whatever the user already looked at.
  Future<void> cacheTileBytes(TileCoord t, Uint8List bytes) async {
    if (!_looksLikeValidPng(bytes)) return;
    try {
      final file = _tileFile(await _tilesDirectory, t);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // Best-effort cache write; browsing must not fail because the disk
      // cache couldn't be written.
    }
  }

  Future<Uint8List> _fetchTileFromNetwork(TileCoord t) async {
    final url = '$_tileUrlTemplate/${t.z}/${t.x}/${t.y}.png';
    final response = await _dio.get<List<int>>(url);
    return Uint8List.fromList(response.data!);
  }

  /// Used by [OfflineTileProvider] for organic (browse-triggered) caching:
  /// fetches whatever URL flutter_map resolved for this tile (respecting
  /// its own subdomain/User-Agent handling) and writes it into the shared
  /// disk cache so a later region download can skip it.
  Future<Uint8List> fetchAndCacheTile(TileCoord t, String url, Map<String, String> headers) async {
    final response = await _dio.get<List<int>>(url, options: Options(headers: headers));
    final bytes = Uint8List.fromList(response.data!);
    await cacheTileBytes(t, bytes);
    return bytes;
  }

  Future<List<OfflineRegion>> listRegions() async {
    final db = await _database;
    final rows = await db.query(_regionsTable, orderBy: 'updated_at DESC');
    return rows.map(_fromRow).toList();
  }

  OfflineRegion _fromRow(Map<String, Object?> row) => OfflineRegion(
        id: row['id'] as String,
        districtName: row['district_name'] as String,
        north: row['north'] as double,
        south: row['south'] as double,
        east: row['east'] as double,
        west: row['west'] as double,
        minZoom: row['min_zoom'] as int,
        maxZoom: row['max_zoom'] as int,
        totalTiles: row['total_tiles'] as int,
        downloadedTiles: row['downloaded_tiles'] as int,
        bytes: row['bytes'] as int,
        status: OfflineRegionStatus.values.firstWhere((s) => s.name == row['status']),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );

  /// Tile count for a bounds/zoom combination, so the download screen can
  /// show a real estimate before the user confirms.
  int estimateTileCount({
    required double north,
    required double south,
    required double east,
    required double west,
    int minZoom = kOfflineMinZoom,
    int maxZoom = kOfflineMaxZoom,
  }) =>
      TileMath.tilesForBounds(north: north, south: south, east: east, west: west, minZoom: minZoom, maxZoom: maxZoom)
          .length;

  void cancelDownload(String regionId) => _cancelledRegionIds.add(regionId);

  /// Downloads (or resumes/redownloads) one region. Already-cached,
  /// valid tiles are skipped rather than refetched. Reports progress via
  /// [onProgress] after (approximately) every tile.
  Future<void> downloadRegion({
    required String regionId,
    required String districtName,
    required double north,
    required double south,
    required double east,
    required double west,
    int minZoom = kOfflineMinZoom,
    int maxZoom = kOfflineMaxZoom,
    void Function(OfflineRegion region)? onProgress,
  }) async {
    _cancelledRegionIds.remove(regionId);
    final db = await _database;
    final tiles = TileMath.tilesForBounds(north: north, south: south, east: east, west: west, minZoom: minZoom, maxZoom: maxZoom);
    final now = DateTime.now().toIso8601String();

    await db.insert(
      _regionsTable,
      {
        'id': regionId,
        'district_name': districtName,
        'north': north,
        'south': south,
        'east': east,
        'west': west,
        'min_zoom': minZoom,
        'max_zoom': maxZoom,
        'total_tiles': tiles.length,
        'downloaded_tiles': 0,
        'bytes': 0,
        'status': OfflineRegionStatus.downloading.name,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final tileDir = await _tilesDirectory;
    var downloaded = 0;
    var bytesTotal = 0;
    var consecutiveFailures = 0;

    void reportAndMaybePersist({bool force = false}) {
      final region = OfflineRegion(
        id: regionId,
        districtName: districtName,
        north: north,
        south: south,
        east: east,
        west: west,
        minZoom: minZoom,
        maxZoom: maxZoom,
        totalTiles: tiles.length,
        downloadedTiles: downloaded,
        bytes: bytesTotal,
        status: OfflineRegionStatus.downloading,
        updatedAt: DateTime.now(),
      );
      onProgress?.call(region);
      if (force || downloaded % 20 == 0) {
        db.update(_regionsTable, {'downloaded_tiles': downloaded, 'bytes': bytesTotal, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [regionId]);
      }
    }

    for (final tile in tiles) {
      if (_cancelledRegionIds.contains(regionId)) {
        await db.update(_regionsTable, {'status': OfflineRegionStatus.interrupted.name, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [regionId]);
        return;
      }

      try {
        final existing = await readTile(tile);
        Uint8List bytes;
        if (existing != null) {
          bytes = existing;
        } else {
          bytes = await _fetchTileFromNetwork(tile);
          if (!_looksLikeValidPng(bytes)) {
            // Corrupted/incomplete download — one retry, then skip this
            // tile rather than aborting the whole region.
            bytes = await _fetchTileFromNetwork(tile);
          }
          if (_looksLikeValidPng(bytes)) {
            try {
              final file = _tileFile(tileDir, tile);
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes, flush: true);
            } on FileSystemException {
              throw const InsufficientStorageException();
            }
          }
        }

        await db.insert(_tilesTable, {'region_id': regionId, 'z': tile.z, 'x': tile.x, 'y': tile.y},
            conflictAlgorithm: ConflictAlgorithm.replace);
        downloaded++;
        bytesTotal += bytes.length;
        consecutiveFailures = 0;
        reportAndMaybePersist();
      } on InsufficientStorageException {
        await db.update(_regionsTable, {'status': OfflineRegionStatus.failed.name, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id = ?', whereArgs: [regionId]);
        rethrow;
      } catch (_) {
        // Network hiccup on a single tile — count it and move on; too
        // many in a row means connectivity dropped mid-download.
        consecutiveFailures++;
        if (consecutiveFailures > 25) {
          await db.update(_regionsTable, {'status': OfflineRegionStatus.interrupted.name, 'updated_at': DateTime.now().toIso8601String()},
              where: 'id = ?', whereArgs: [regionId]);
          return;
        }
      }
    }

    reportAndMaybePersist(force: true);
    await db.update(_regionsTable, {'status': OfflineRegionStatus.complete.name, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [regionId]);
  }

  /// Deletes a region's metadata and any tile files no other region still
  /// references (reference-counted, so overlapping regions are safe).
  Future<void> deleteRegion(String regionId) async {
    final db = await _database;
    final ownTiles = await db.query(_tilesTable, where: 'region_id = ?', whereArgs: [regionId]);
    final tileDir = await _tilesDirectory;

    await db.delete(_tilesTable, where: 'region_id = ?', whereArgs: [regionId]);
    await db.delete(_regionsTable, where: 'id = ?', whereArgs: [regionId]);

    for (final row in ownTiles) {
      final z = row['z'] as int, x = row['x'] as int, y = row['y'] as int;
      final stillReferenced = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM $_tilesTable WHERE z = ? AND x = ? AND y = ?',
            [z, x, y],
          )) ??
          0;
      if (stillReferenced == 0) {
        final file = _tileFile(tileDir, TileCoord(z, x, y));
        if (await file.exists()) await file.delete();
      }
    }
  }
}
