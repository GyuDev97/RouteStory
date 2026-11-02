import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/entities/gps_point.dart';
import '../../domain/entities/manual_marker.dart';
import '../../domain/entities/stop.dart';
import '../../domain/entities/trip.dart';
import '../../domain/entities/trip_photo.dart';
import '../../domain/repositories/trip_repository.dart';
import 'memory_trip_repository.dart';

class LocalTripRepository implements TripRepository {
  LocalTripRepository({
    TripRepository? demoRepository,
    Future<Database> Function()? databaseOpener,
  }) : _demoRepository = demoRepository ?? MemoryTripRepository(),
       _databaseOpener = databaseOpener;
  final TripRepository _demoRepository;
  final Future<Database> Function()? _databaseOpener;
  Future<Database>? _database;
  Future<Database> get _db => _database ??= (_databaseOpener ?? _open)();

  static const databaseVersion = 4;

  /// Opens the DB at [path] with this repository's schema and migrations.
  static Future<Database> openAt(
    String path, {
    DatabaseFactory? factory,
    bool singleInstance = true,
  }) {
    final options = OpenDatabaseOptions(
      version: databaseVersion,
      singleInstance: singleInstance,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE trips (id TEXT PRIMARY KEY, title TEXT NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER, total_distance REAL NOT NULL, status TEXT NOT NULL, privacy_setting TEXT NOT NULL, share_setting TEXT NOT NULL, stop_analysis_status TEXT NOT NULL DEFAULT \'pending\', photo_match_status TEXT NOT NULL DEFAULT \'pending\', cover_photo_id TEXT)',
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
        await _createStopsTable(db);
        await _createPhotosTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Additive only; existing trips, points and markers are kept.
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE trips ADD COLUMN stop_analysis_status TEXT NOT NULL DEFAULT \'pending\'',
          );
          await _createStopsTable(db);
        } else if (oldVersion < 3) {
          await db.execute('ALTER TABLE stops ADD COLUMN cover_photo_id TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE trips ADD COLUMN photo_match_status TEXT NOT NULL DEFAULT \'pending\'',
          );
          await _createPhotosTable(db);
        } else if (oldVersion < 4) {
          await db.execute('ALTER TABLE photos ADD COLUMN width INTEGER');
          await db.execute('ALTER TABLE photos ADD COLUMN height INTEGER');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE trips ADD COLUMN cover_photo_id TEXT');
        }
      },
    );
    return (factory ?? databaseFactory).openDatabase(path, options: options);
  }

  static Future<void> _createStopsTable(Database db) async {
    await db.execute(
      'CREATE TABLE stops (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, place_name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, arrival_time INTEGER NOT NULL, departure_time INTEGER, source TEXT NOT NULL, memo TEXT, is_excluded INTEGER NOT NULL DEFAULT 0, is_name_edited INTEGER NOT NULL DEFAULT 0, is_user_modified INTEGER NOT NULL DEFAULT 0, marker_ids TEXT NOT NULL DEFAULT \'\', cover_photo_id TEXT)',
    );
    await db.execute(
      'CREATE INDEX stops_trip_time ON stops(trip_id, arrival_time)',
    );
  }

  static Future<void> _createPhotosTable(Database db) async {
    await db.execute(
      'CREATE TABLE photos (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, asset_id TEXT, local_path TEXT NOT NULL DEFAULT \'\', taken_at INTEGER, latitude REAL, longitude REAL, stop_id TEXT, match_method TEXT NOT NULL, confidence REAL NOT NULL DEFAULT 0, is_manually_edited INTEGER NOT NULL DEFAULT 0, is_excluded INTEGER NOT NULL DEFAULT 0, width INTEGER, height INTEGER)',
    );
    await db.execute('CREATE INDEX photos_trip ON photos(trip_id)');
  }

  Future<Database> _open() async =>
      openAt(join(await getDatabasesPath(), 'route_story.db'));

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

  @override
  Future<List<ManualMarker>> getManualMarkers(String tripId) async =>
      (await (await _db).query(
            'manual_markers',
            where: 'trip_id = ?',
            whereArgs: [tripId],
            orderBy: 'timestamp',
          ))
          .map(
            (row) => ManualMarker(
              id: row['id'] as String,
              tripId: row['trip_id'] as String,
              latitude: row['latitude'] as double,
              longitude: row['longitude'] as double,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                row['timestamp'] as int,
              ),
              memo: row['memo'] as String?,
            ),
          )
          .toList();

  @override
  Future<List<Stop>> getAllStops(String tripId) async =>
      (await (await _db).query(
            'stops',
            where: 'trip_id = ?',
            whereArgs: [tripId],
            orderBy: 'arrival_time',
          ))
          .map(_stopFromRow)
          .toList();

  @override
  Future<void> saveStopChanges(
    String tripId, {
    List<Stop> upserts = const [],
    List<String> deleteIds = const [],
    StopAnalysisStatus? status,
    Map<String, String> photoStopRemap = const {},
  }) async => (await _db).transaction((txn) async {
    for (final id in deleteIds) {
      await txn.delete(
        'stops',
        where: 'id = ? AND trip_id = ?',
        whereArgs: [id, tripId],
      );
    }
    for (final stop in upserts) {
      await txn.insert(
        'stops',
        _stopMap(tripId, stop),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final remap in photoStopRemap.entries) {
      await txn.update(
        'photos',
        {'stop_id': remap.value},
        where: 'trip_id = ? AND stop_id = ?',
        whereArgs: [tripId, remap.key],
      );
    }
    if (status != null) {
      await txn.update(
        'trips',
        {'stop_analysis_status': status.name},
        where: 'id = ?',
        whereArgs: [tripId],
      );
    }
  });

  @override
  Future<void> setStopAnalysisStatus(
    String tripId,
    StopAnalysisStatus status,
  ) async => (await _db).update(
    'trips',
    {'stop_analysis_status': status.name},
    where: 'id = ?',
    whereArgs: [tripId],
  );

  Map<String, Object?> _stopMap(String tripId, Stop stop) => {
    'id': stop.id,
    'trip_id': tripId,
    'place_name': stop.placeName,
    'latitude': stop.latitude,
    'longitude': stop.longitude,
    'arrival_time': stop.arrivalTime.millisecondsSinceEpoch,
    'departure_time': stop.departureTime?.millisecondsSinceEpoch,
    'source': stop.source.name,
    'memo': stop.memo,
    'is_excluded': stop.isExcluded ? 1 : 0,
    'is_name_edited': stop.isNameEdited ? 1 : 0,
    'is_user_modified': stop.isUserModified ? 1 : 0,
    'marker_ids': stop.markerIds.join(','),
    'cover_photo_id': stop.coverPhotoId,
  };

  Stop _stopFromRow(Map<String, Object?> row) => Stop(
    id: row['id'] as String,
    tripId: row['trip_id'] as String,
    placeName: row['place_name'] as String,
    latitude: row['latitude'] as double,
    longitude: row['longitude'] as double,
    arrivalTime: DateTime.fromMillisecondsSinceEpoch(
      row['arrival_time'] as int,
    ),
    departureTime: row['departure_time'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['departure_time'] as int),
    source: StopSource.values.firstWhere(
      (s) => s.name == row['source'],
      orElse: () => StopSource.automatic,
    ),
    memo: row['memo'] as String?,
    isExcluded: row['is_excluded'] == 1,
    isNameEdited: row['is_name_edited'] == 1,
    isUserModified: row['is_user_modified'] == 1,
    markerIds: (row['marker_ids'] as String)
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList(),
    coverPhotoId: row['cover_photo_id'] as String?,
  );

  @override
  Future<List<TripPhoto>> getPhotos(String tripId) async =>
      (await (await _db).query(
            'photos',
            where: 'trip_id = ?',
            whereArgs: [tripId],
            orderBy: 'taken_at',
          ))
          .map(_photoFromRow)
          .toList();

  @override
  Future<void> savePhotos(
    String tripId, {
    List<TripPhoto> upserts = const [],
    PhotoMatchStatus? status,
  }) async => (await _db).transaction((txn) async {
    for (final photo in upserts) {
      await txn.insert('photos', {
        'id': photo.id,
        'trip_id': tripId,
        'asset_id': photo.assetId,
        'local_path': photo.localPath,
        'taken_at': photo.takenAt?.millisecondsSinceEpoch,
        'latitude': photo.latitude,
        'longitude': photo.longitude,
        'stop_id': photo.stopId,
        'match_method': photo.matchMethod.name,
        'confidence': photo.matchConfidence,
        'is_manually_edited': photo.isManuallyEdited ? 1 : 0,
        'is_excluded': photo.isExcluded ? 1 : 0,
        'width': photo.width,
        'height': photo.height,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (status != null) {
      await txn.update(
        'trips',
        {'photo_match_status': status.name},
        where: 'id = ?',
        whereArgs: [tripId],
      );
    }
  });

  @override
  Future<void> setPhotoMatchStatus(
    String tripId,
    PhotoMatchStatus status,
  ) async => (await _db).update(
    'trips',
    {'photo_match_status': status.name},
    where: 'id = ?',
    whereArgs: [tripId],
  );

  TripPhoto _photoFromRow(Map<String, Object?> row) => TripPhoto(
    id: row['id'] as String,
    tripId: row['trip_id'] as String,
    assetId: row['asset_id'] as String?,
    localPath: (row['local_path'] as String?) ?? '',
    takenAt: row['taken_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['taken_at'] as int),
    latitude: row['latitude'] as double?,
    longitude: row['longitude'] as double?,
    stopId: row['stop_id'] as String?,
    matchMethod: PhotoMatchMethod.values.firstWhere(
      (m) => m.name == row['match_method'],
      orElse: () => PhotoMatchMethod.none,
    ),
    matchConfidence: (row['confidence'] as num?)?.toDouble() ?? 0,
    isManuallyEdited: row['is_manually_edited'] == 1,
    isExcluded: row['is_excluded'] == 1,
    width: row['width'] as int?,
    height: row['height'] as int?,
  );

  @override
  Future<void> updateTripDetails(
    String tripId, {
    String? title,
    String? coverPhotoId,
    bool clearCover = false,
  }) async {
    final values = <String, Object?>{
      'title': ?title,
      if (clearCover) 'cover_photo_id': null else 'cover_photo_id': ?coverPhotoId,
    };
    if (values.isEmpty) return;
    await (await _db).update('trips', values, where: 'id = ?', whereArgs: [tripId]);
  }

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
    final stops = await getAllStops(row['id'] as String);
    final photos = await getPhotos(row['id'] as String);
    return Trip(
      id: row['id'] as String,
      title: row['title'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(row['start_time'] as int),
      endTime: row['end_time'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['end_time'] as int),
      totalDistance: row['total_distance'] as double,
      gpsPoints: points,
      stops: stops.where((s) => !s.isExcluded).toList(),
      excludedStops: stops.where((s) => s.isExcluded).toList(),
      photos: photos,
      privacySetting: row['privacy_setting'] as String,
      shareSetting: row['share_setting'] as String,
      status: row['status'] as String,
      stopAnalysisStatus: StopAnalysisStatus.values.firstWhere(
        (s) => s.name == row['stop_analysis_status'],
        orElse: () => StopAnalysisStatus.pending,
      ),
      photoMatchStatus: PhotoMatchStatus.values.firstWhere(
        (s) => s.name == row['photo_match_status'],
        orElse: () => PhotoMatchStatus.pending,
      ),
      coverPhotoId: row['cover_photo_id'] as String?,
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
    'stop_analysis_status': trip.stopAnalysisStatus.name,
    'photo_match_status': trip.photoMatchStatus.name,
  };
}

