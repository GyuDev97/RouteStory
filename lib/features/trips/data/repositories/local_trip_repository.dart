import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/gps_point.dart';
import '../../domain/entities/manual_marker.dart';
import '../../domain/entities/trip.dart';
import '../../domain/repositories/trip_repository.dart';
import 'memory_trip_repository.dart';

class LocalTripRepository implements TripRepository {
  LocalTripRepository({TripRepository? demoRepository})
    : _demoRepository = demoRepository ?? MemoryTripRepository();
  final TripRepository _demoRepository;
  Future<Database>? _database;
  Future<Database> get _db => _database ??= _open();

  Future<Database> _open() async => openDatabase(
    join(await getDatabasesPath(), 'route_story.db'),
    version: 1,
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE trips (id TEXT PRIMARY KEY, title TEXT NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER, total_distance REAL NOT NULL, status TEXT NOT NULL, privacy_setting TEXT NOT NULL, share_setting TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE gps_points (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, altitude REAL NOT NULL, timestamp INTEGER NOT NULL, accuracy REAL NOT NULL, speed REAL, heading REAL)',
      );
      await db.execute(
        'CREATE INDEX gps_points_trip_time ON gps_points(trip_id, timestamp)',
      );
      await db.execute(
        'CREATE TABLE manual_markers (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, timestamp INTEGER NOT NULL, memo TEXT)',
      );
    },
  );

  @override
  Future<List<Trip>> getRecentTrips() async {
    final rows = await (await _db).query(
      'trips',
      where: "status = 'completed'",
      orderBy: 'start_time DESC',
    );
    if (rows.isEmpty) return _demoRepository.getRecentTrips();
    return Future.wait(rows.map(_readTrip));
  }

  @override
  Future<Trip?> getTrip(String id) async {
    final rows = await (await _db).query(
      'trips',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _readTrip(rows.first);
  }

  @override
  Future<Trip?> getRecordingTrip() async {
    final rows = await (await _db).query(
      'trips',
      where: "status = 'recording'",
      orderBy: 'start_time DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _readTrip(rows.first);
  }

  @override
  Future<void> saveTrip(Trip trip) async => (await _db).insert(
    'trips',
    _tripMap(trip),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  @override
  Future<void> saveGpsPoint(String tripId, GpsPoint point) async =>
      (await _db).insert('gps_points', {
        'trip_id': tripId,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'altitude': point.altitude,
        'timestamp': point.timestamp.millisecondsSinceEpoch,
        'accuracy': point.accuracy,
        'speed': point.speed,
        'heading': point.heading,
      });
  @override
  Future<void> saveManualMarker(ManualMarker marker) async =>
      (await _db).insert('manual_markers', {
        'id': marker.id,
        'trip_id': marker.tripId,
        'latitude': marker.latitude,
        'longitude': marker.longitude,
        'timestamp': marker.timestamp.millisecondsSinceEpoch,
        'memo': marker.memo,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Trip> _readTrip(Map<String, Object?> row) async {
    final db = await _db;
    final points =
        (await db.query(
              'gps_points',
              where: 'trip_id = ?',
              whereArgs: [row['id']],
              orderBy: 'timestamp',
            ))
            .map(
              (point) => GpsPoint(
                latitude: point['latitude'] as double,
                longitude: point['longitude'] as double,
                altitude: point['altitude'] as double,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  point['timestamp'] as int,
                ),
                accuracy: point['accuracy'] as double,
                speed: point['speed'] as double?,
                heading: point['heading'] as double?,
              ),
            )
            .toList();
    return Trip(
      id: row['id'] as String,
      title: row['title'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
      endTime: row['end_time'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['end_time'] as int),
      totalDistance: row['total_distance'] as double,
      gpsPoints: points,
      privacySetting: row['privacy_setting'] as String,
      shareSetting: row['share_setting'] as String,
      status: row['status'] as String,
    );
  }

  Map<String, Object?> _tripMap(Trip trip) => {
    'id': trip.id,
    'title': trip.title,
    'start_time': trip.startTime.millisecondsSinceEpoch,
    'end_time': trip.endTime?.millisecondsSinceEpoch,
    'total_distance': trip.totalDistance,
    'status': trip.status,
    'privacy_setting': trip.privacySetting,
    'share_setting': trip.shareSetting,
  };
}
