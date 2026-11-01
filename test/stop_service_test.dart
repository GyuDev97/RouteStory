import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/application/stop_service.dart';
import 'package:route_story/features/trips/data/repositories/local_trip_repository.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/gps_point.dart';
import 'package:route_story/features/trips/domain/entities/manual_marker.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/repositories/trip_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/gps_scenario.dart';

class FlakyRepository implements TripRepository {
  FlakyRepository(this.inner);
  final TripRepository inner;
  var failSaves = 0;
  var saveCalls = 0;
  @override
  Future<void> saveStopChanges(
    String tripId, {
    List<Stop> upserts = const [],
    List<String> deleteIds = const [],
    StopAnalysisStatus? status,
  }) async {
    saveCalls++;
    if (failSaves > 0) {
      failSaves--;
      throw StateError('disk full');
    }
    return inner.saveStopChanges(
      tripId,
      upserts: upserts,
      deleteIds: deleteIds,
      status: status,
    );
  }

  @override
  Future<List<Trip>> getRecentTrips() => inner.getRecentTrips();
  @override
  Future<Trip?> getTrip(String id) => inner.getTrip(id);
  @override
  Future<Trip?> getRecordingTrip() => inner.getRecordingTrip();
  @override
  Future<void> saveTrip(Trip trip) => inner.saveTrip(trip);
  @override
  Future<void> saveGpsPoint(String tripId, GpsPoint point) =>
      inner.saveGpsPoint(tripId, point);
  @override
  Future<void> saveManualMarker(ManualMarker marker) =>
      inner.saveManualMarker(marker);
  @override
  Future<List<ManualMarker>> getManualMarkers(String tripId) =>
      inner.getManualMarkers(tripId);
  @override
  Future<List<Stop>> getAllStops(String tripId) => inner.getAllStops(tripId);
  @override
  Future<void> setStopAnalysisStatus(String tripId, StopAnalysisStatus s) =>
      inner.setStopAnalysisStatus(tripId, s);
}

const tripId = 'trip-1';

/// Cafe (40 min) -> 20 min drive -> sight (20 min).
class Seeded {
  late DateTime cafeArrival, cafeDeparture, sightArrival, sightDeparture;
  late double cafeLat, cafeLng, sightLat, sightLng;
  late int pointCount;
}

Future<Seeded> seed(TripRepository repo, {bool withPoints = true}) async {
  final s = GpsScenario()..move(20.min, speed: 10);
  final seeded = Seeded()
    ..cafeLat = s.lat
    ..cafeLng = s.lng
    ..cafeArrival = s.now;
  s.stay(40.min);
  seeded.cafeDeparture = s.now;
  s.move(20.min, speed: 10);
  seeded
    ..sightLat = s.lat
    ..sightLng = s.lng
    ..sightArrival = s.now;
  s.stay(20.min);
  seeded.sightDeparture = s.now;
  s.move(5.min, speed: 10);
  await repo.saveTrip(
    Trip(
      id: tripId,
      title: '오늘의 여정',
      startTime: DateTime(2026, 9, 1, 9),
      endTime: s.now,
      totalDistance: 1000,
    ),
  );
  if (withPoints) {
    for (final p in s.points) {
      await repo.saveGpsPoint(tripId, p);
    }
  }
  seeded.pointCount = s.points.length;
  return seeded;
}

void main() {
  sqfliteFfiInit();
  final factories = <String, TripRepository Function()>{
    'memory': MemoryTripRepository.new,
    'sqlite': () => LocalTripRepository(
      databaseOpener: () => LocalTripRepository.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      ),
    ),
  };

  for (final entry in factories.entries) {
    group('stop analysis (${entry.key})', () {
      late TripRepository repo;
      late StopService service;
      setUp(() {
        repo = entry.value();
        service = StopService(repo);
      });

      test('extracts, stores and reloads stops; raw data stays intact', () async {
        final seeded = await seed(repo);
        expect(await service.analyze(tripId), StopAnalysisOutcome.completed);

        final trip = (await repo.getTrip(tripId))!;
        expect(trip.stopAnalysisStatus, StopAnalysisStatus.completed);
        expect(trip.gpsPoints, hasLength(seeded.pointCount));
        expect(trip.stops, hasLength(2));
        expect(trip.stops[0].source, StopSource.automatic);
        expect(
          trip.stops[0].arrivalTime.difference(seeded.cafeArrival).inSeconds.abs(),
          lessThan(60),
        );
        expect(
          trip.stops[0].departureTime!
              .difference(seeded.cafeDeparture)
              .inSeconds
              .abs(),
          lessThan(60),
        );
        expect(
          trip.stops[1].arrivalTime.difference(seeded.sightArrival).inSeconds.abs(),
          lessThan(60),
        );
        expect(
          metersBetween(seeded.sightLat, seeded.sightLng, trip.stops[1].latitude, trip.stops[1].longitude),
          lessThan(40),
        );
        expect(trip.stops.every((s) => !trip.isDemo && s.photoIds.isEmpty), isTrue);
      });

      test('re-analysis does not duplicate stops', () async {
        await seed(repo);
        await service.analyze(tripId);
        final first = await repo.getAllStops(tripId);
        await service.analyze(tripId);
        await service.analyze(tripId);
        final again = await repo.getAllStops(tripId);
        expect(again.map((s) => s.id).toSet(), first.map((s) => s.id).toSet());
        expect(again, hasLength(2));
      });

      test('re-analysis keeps renamed and excluded stops', () async {
        await seed(repo);
        await service.analyze(tripId);
        final stops = (await repo.getTrip(tripId))!.stops;
        await service.rename(tripId, stops[0].id, '  성수 카페  ');
        await service.exclude(tripId, stops[1].id);

        await service.analyze(tripId);

        final trip = (await repo.getTrip(tripId))!;
        expect(trip.stops.map((s) => s.placeName), ['성수 카페']);
        expect(trip.stops.single.id, stops[0].id);
        expect(trip.excludedStops.map((s) => s.id), [stops[1].id]);
        expect(await repo.getAllStops(tripId), hasLength(2));

        await service.restore(tripId, stops[1].id);
        expect((await repo.getTrip(tripId))!.stops, hasLength(2));
      });

      test('merging keeps both visits\' info and survives re-analysis', () async {
        final seeded = await seed(repo);
        await service.analyze(tripId);
        final stops = (await repo.getTrip(tripId))!.stops;
        await service.rename(tripId, stops[1].id, '전망대');

        expect(await service.mergeWithNext(tripId, stops[0].id), isTrue);
        var trip = (await repo.getTrip(tripId))!;
        expect(trip.stops, hasLength(1));
        final merged = trip.stops.single;
        expect(merged.placeName, '전망대');
        expect(merged.arrivalTime, stops[0].arrivalTime);
        expect(merged.departureTime, stops[1].departureTime);
        expect(merged.isUserModified, isTrue);
        expect(
          merged.departureTime!.difference(seeded.sightDeparture).inSeconds.abs(),
          lessThan(60),
        );

        await service.analyze(tripId);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.stops, hasLength(1));
        expect(trip.stops.single.id, merged.id);
        expect(trip.stops.single.departureTime, merged.departureTime);
        expect(await service.mergeWithNext(tripId, merged.id), isFalse);
      });

      test('manual markers link to stops or become their own visit', () async {
        final seeded = await seed(repo);
        final inCafe = ManualMarker(
          id: 'm1',
          tripId: tripId,
          latitude: seeded.cafeLat + 0.0002,
          longitude: seeded.cafeLng,
          timestamp: seeded.cafeArrival.add(15.min),
          memo: '아이스 라떼',
        );
        // Same place as the cafe, but two hours after the visit ended.
        final cafeLater = ManualMarker(
          id: 'm2',
          tripId: tripId,
          latitude: seeded.cafeLat,
          longitude: seeded.cafeLng,
          timestamp: seeded.cafeDeparture.add(120.min),
        );
        // Somewhere with no stop at all.
        final roadside = ManualMarker(
          id: 'm3',
          tripId: tripId,
          latitude: seeded.cafeLat + 0.05,
          longitude: seeded.cafeLng,
          timestamp: seeded.cafeDeparture.add(5.min),
          memo: '전망 좋은 곳',
        );
        for (final m in [inCafe, cafeLater, roadside]) {
          await repo.saveManualMarker(m);
        }

        await service.analyze(tripId);
        await service.analyze(tripId);

        final trip = (await repo.getTrip(tripId))!;
        // 2 detected stops + 2 standalone markers; m1 is not shown twice.
        expect(trip.stops, hasLength(4));
        final cafe = trip.stops.firstWhere(
          (s) => s.source == StopSource.automatic && s.markerIds.isNotEmpty,
        );
        expect(cafe.markerIds, ['m1']);
        expect(cafe.memo, '아이스 라떼');
        final standalone = trip.stops.where((s) => s.source == StopSource.manual);
        expect(standalone.expand((s) => s.markerIds).toSet(), {'m2', 'm3'});
        expect(
          trip.stops.map((s) => s.arrivalTime).toList(),
          orderedEquals([...trip.stops.map((s) => s.arrivalTime)]..sort()),
        );
        // Markers are never removed.
        expect(await repo.getManualMarkers(tripId), hasLength(3));
      });

      test('excluded marker visits stay excluded after re-analysis', () async {
        final seeded = await seed(repo);
        await repo.saveManualMarker(
          ManualMarker(
            id: 'm9',
            tripId: tripId,
            latitude: seeded.cafeLat + 0.05,
            longitude: seeded.cafeLng,
            timestamp: seeded.cafeDeparture.add(5.min),
          ),
        );
        await service.analyze(tripId);
        final marker = (await repo.getTrip(tripId))!.stops.firstWhere(
          (s) => s.source == StopSource.manual,
        );
        await service.exclude(tripId, marker.id);
        await service.analyze(tripId);
        final trip = (await repo.getTrip(tripId))!;
        expect(trip.stops.where((s) => s.source == StopSource.manual), isEmpty);
        expect(trip.excludedStops.single.id, marker.id);
        expect(await repo.getManualMarkers(tripId), hasLength(1));
      });

      test('a trip without GPS points completes with zero stops', () async {
        await seed(repo, withPoints: false);
        expect(await service.analyze(tripId), StopAnalysisOutcome.completed);
        final trip = (await repo.getTrip(tripId))!;
        expect(trip.stops, isEmpty);
        expect(trip.stopAnalysisStatus, StopAnalysisStatus.completed);
      });

      test('a trip that is still recording is not analyzed', () async {
        await repo.saveTrip(
          Trip(
            id: 'rec',
            title: 't',
            startTime: DateTime(2026, 9, 1),
            totalDistance: 0,
            status: 'recording',
          ),
        );
        expect(await service.analyze('rec'), StopAnalysisOutcome.skipped);
        expect(
          (await repo.getTrip('rec'))!.stopAnalysisStatus,
          StopAnalysisStatus.pending,
        );
      });

      test('analyzePending ignores demo trips and finished analyses', () async {
        await seed(repo);
        final trips = await repo.getRecentTrips();
        expect(await service.analyzePending(trips.where((t) => t.isDemo)), isFalse);
        expect(await service.analyzePending(await _real(repo)), isTrue);
        expect(await service.analyzePending(await _real(repo)), isFalse);
      });
    });
  }

  group('failure handling', () {
    test('a failed save keeps trip data, marks failed, and can be retried', () async {
      final inner = MemoryTripRepository();
      final repo = FlakyRepository(inner);
      final service = StopService(repo);
      final seeded = await seed(repo);

      repo.failSaves = 1;
      expect(await service.analyze(tripId), StopAnalysisOutcome.failed);
      var trip = (await inner.getTrip(tripId))!;
      expect(trip.stopAnalysisStatus, StopAnalysisStatus.failed);
      expect(trip.gpsPoints, hasLength(seeded.pointCount));
      expect(trip.stops, isEmpty);

      expect(await service.analyzePending([trip]), isTrue);
      trip = (await inner.getTrip(tripId))!;
      expect(trip.stopAnalysisStatus, StopAnalysisStatus.completed);
      expect(trip.stops, hasLength(2));
    });

    test('simultaneous analysis requests run once', () async {
      final repo = FlakyRepository(MemoryTripRepository());
      final service = StopService(repo);
      await seed(repo);
      final results = await Future.wait([
        service.analyze(tripId),
        service.analyze(tripId),
        service.analyze(tripId),
      ]);
      expect(results, everyElement(StopAnalysisOutcome.completed));
      expect(repo.saveCalls, 1);
      expect(await repo.getAllStops(tripId), hasLength(2));
    });

    test('an edit made while analysis runs is not lost', () async {
      final repo = MemoryTripRepository();
      final service = StopService(repo);
      await seed(repo);
      await service.analyze(tripId);
      final stop = (await repo.getAllStops(tripId)).first;
      // Fire both without awaiting in between.
      final rename = service.rename(tripId, stop.id, '내 장소');
      final analysis = service.analyze(tripId);
      await Future.wait([rename, analysis]);
      final names = (await repo.getAllStops(tripId)).map((s) => s.placeName);
      expect(names, contains('내 장소'));
    });
  });

  group('database migration', () {
    test('v1 data survives the upgrade and gets pending analysis', () async {
      final dir = Directory.systemTemp.createTempSync('route_story_db');
      final path = '${dir.path}/route_story.db';
      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE trips (id TEXT PRIMARY KEY, title TEXT NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER, total_distance REAL NOT NULL, status TEXT NOT NULL, privacy_setting TEXT NOT NULL, share_setting TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE gps_points (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, altitude REAL NOT NULL, timestamp INTEGER NOT NULL, accuracy REAL NOT NULL, speed REAL, heading REAL)',
            );
            await db.execute(
              'CREATE TABLE manual_markers (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, timestamp INTEGER NOT NULL, memo TEXT)',
            );
          },
        ),
      );
      await v1.insert('trips', {
        'id': 'old',
        'title': '옛 여행',
        'start_time': 1000,
        'end_time': 2000,
        'total_distance': 5.0,
        'status': 'completed',
        'privacy_setting': 'private',
        'share_setting': 'off',
      });
      await v1.insert('gps_points', {
        'trip_id': 'old',
        'latitude': 37.5,
        'longitude': 127.0,
        'altitude': 1.0,
        'timestamp': 1500,
        'accuracy': 5.0,
      });
      await v1.close();

      final repo = LocalTripRepository(
        databaseOpener: () =>
            LocalTripRepository.openAt(path, factory: databaseFactoryFfi),
      );
      final trip = (await repo.getTrip('old'))!;
      expect(trip.title, '옛 여행');
      expect(trip.gpsPoints, hasLength(1));
      expect(trip.stopAnalysisStatus, StopAnalysisStatus.pending);
      expect(trip.stops, isEmpty);

      expect(await StopService(repo).analyze('old'), StopAnalysisOutcome.completed);
      expect((await repo.getTrip('old'))!.stopAnalysisStatus, StopAnalysisStatus.completed);
    });
  });
}

Future<List<Trip>> _real(TripRepository repo) async =>
    (await repo.getRecentTrips()).where((t) => !t.isDemo).toList();



