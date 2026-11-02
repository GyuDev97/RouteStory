import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/core/services/photo_library_service.dart';
import 'package:route_story/features/trips/application/photo_matching_service.dart';
import 'package:route_story/features/trips/application/stop_service.dart';
import 'package:route_story/features/trips/application/trip_task_queue.dart';
import 'package:route_story/features/trips/data/repositories/local_trip_repository.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/photo_metadata.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/entities/trip_photo.dart';
import 'package:route_story/features/trips/domain/repositories/trip_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_photo_library.dart';
import 'support/trip_seed.dart';

DateTime at(int h, int m) => DateTime(2026, 9, 1, h, m);

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
    group('photo matching (${entry.key})', () {
      late TripRepository repo;
      late FakePhotoLibrary library;
      late StopService stops;
      late PhotoMatchingService photos;
      late Seeded seeded;

      // Trip: 09:00-10:45. Cafe 09:20-10:00, sight 10:20-10:40.
      setUp(() async {
        repo = entry.value();
        final queue = TripTaskQueue();
        stops = StopService(repo, queue: queue);
        library = FakePhotoLibrary(
          photos: [
            PhotoMetadata(
              assetId: 'cafe-gps',
              takenAt: at(9, 40),
              latitude: 0, // replaced below
              longitude: 0,
            ),
          ],
        );
        photos = PhotoMatchingService(
          repo,
          library,
          queue: queue,
          ensureStops: stops.analyze,
        );
        seeded = await seed(repo);
        library.photos = [
          PhotoMetadata(
            assetId: 'cafe-gps',
            takenAt: at(9, 40),
            latitude: seeded.cafeLat,
            longitude: seeded.cafeLng,
          ),
          PhotoMetadata(assetId: 'cafe-nogps', takenAt: at(9, 50)),
          PhotoMetadata(assetId: 'road', takenAt: at(9, 10)),
          PhotoMetadata(assetId: 'sight', takenAt: at(10, 30)),
          PhotoMetadata(assetId: 'no-time'),
          PhotoMetadata(assetId: 'yesterday', takenAt: DateTime(2026, 8, 31, 12)),
        ];
      });

      TripPhoto find(Trip t, String asset) =>
          t.photos.firstWhere((p) => p.assetId == asset);

      test('analyzes stops first, then matches and stores photos', () async {
        // Stop analysis has not run yet: matching triggers it.
        expect(await photos.match(tripId), PhotoMatchOutcome.completed);

        final trip = (await repo.getTrip(tripId))!;
        expect(trip.stopAnalysisStatus, StopAnalysisStatus.completed);
        expect(trip.photoMatchStatus, PhotoMatchStatus.completed);
        expect(trip.stops, hasLength(2));
        final cafe = trip.stops[0], sight = trip.stops[1];
        expect(find(trip, 'cafe-gps').stopId, cafe.id);
        expect(find(trip, 'cafe-gps').matchMethod, PhotoMatchMethod.timeAndLocation);
        expect(find(trip, 'cafe-nogps').stopId, cafe.id);
        expect(find(trip, 'cafe-nogps').matchMethod, PhotoMatchMethod.time);
        expect(find(trip, 'sight').stopId, sight.id);
        expect(find(trip, 'road').isRoutePhoto, isTrue);
        expect(find(trip, 'no-time').isUnclassified, isTrue);
        expect(trip.photos.any((p) => p.assetId == 'yesterday'), isFalse);
        expect(trip.photos, hasLength(5));
        // Only the trip's time window was queried.
        expect(library.lastFrom!.isAfter(at(8, 0)), isTrue);
        expect(library.lastTo!.isBefore(at(12, 0)), isTrue);
      });

      test('11. re-matching does not duplicate photos', () async {
        await photos.match(tripId);
        await photos.match(tripId);
        await photos.match(tripId);
        expect((await repo.getPhotos(tripId)), hasLength(5));
      });

      test('8. a photo moved by the user stays where the user put it', () async {
        await photos.match(tripId);
        var trip = (await repo.getTrip(tripId))!;
        final sight = trip.stops[1];
        final moved = find(trip, 'cafe-gps');
        await photos.moveToStop(tripId, moved.id, sight.id);

        await photos.match(tripId);
        await stops.analyze(tripId);
        await photos.match(tripId);

        trip = (await repo.getTrip(tripId))!;
        expect(find(trip, 'cafe-gps').stopId, sight.id);
        expect(find(trip, 'cafe-gps').matchMethod, PhotoMatchMethod.manual);
        expect(find(trip, 'cafe-gps').isManuallyEdited, isTrue);
      });

      test('detaching and attaching manually are kept too', () async {
        await photos.match(tripId);
        var trip = (await repo.getTrip(tripId))!;
        await photos.detach(tripId, find(trip, 'cafe-nogps').id);
        await photos.moveToStop(tripId, find(trip, 'no-time').id, trip.stops[0].id);
        await photos.match(tripId);
        trip = (await repo.getTrip(tripId))!;
        expect(find(trip, 'cafe-nogps').isUnclassified, isTrue);
        expect(find(trip, 'no-time').stopId, trip.stops[0].id);
      });

      test('9. an excluded photo stays excluded after re-matching', () async {
        await photos.match(tripId);
        var trip = (await repo.getTrip(tripId))!;
        await photos.exclude(tripId, find(trip, 'sight').id);
        await photos.match(tripId);
        trip = (await repo.getTrip(tripId))!;
        expect(find(trip, 'sight').isExcluded, isTrue);
        expect(trip.activePhotos.any((p) => p.assetId == 'sight'), isFalse);
        await photos.restore(tripId, find(trip, 'sight').id);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.activePhotos.any((p) => p.assetId == 'sight'), isTrue);
      });

      test('cover photo choice survives re-matching and merging', () async {
        await photos.match(tripId);
        var trip = (await repo.getTrip(tripId))!;
        final cafe = trip.stops[0];
        await photos.setCover(tripId, cafe.id, find(trip, 'cafe-nogps').id);
        await photos.match(tripId);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.stops[0].coverPhotoId, find(trip, 'cafe-nogps').id);

        // Merging moves the absorbed stop's photos onto the merged stop.
        await stops.mergeWithNext(tripId, cafe.id);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.stops, hasLength(1));
        expect(trip.stops.single.coverPhotoId, find(trip, 'cafe-nogps').id);
        expect(
          trip.photos.where((p) => p.stopId != null).every(
            (p) => p.stopId == trip.stops.single.id,
          ),
          isTrue,
        );
        expect(find(trip, 'sight').stopId, trip.stops.single.id);
      });

      test('no photo permission: trip untouched, can run again once allowed', () async {
        library.access = PhotoAccess.denied;
        library.afterRequest = PhotoAccess.full;
        expect(await photos.match(tripId), PhotoMatchOutcome.noAccess);
        var trip = (await repo.getTrip(tripId))!;
        expect(trip.photoMatchStatus, PhotoMatchStatus.noAccess);
        expect(trip.photos, isEmpty);
        expect(trip.gpsPoints, hasLength(seeded.pointCount));
        expect(trip.stops, hasLength(2));
        expect(library.requestCalls, 0, reason: 'background runs never prompt');

        expect(
          await photos.match(tripId, requestPermission: true),
          PhotoMatchOutcome.completed,
        );
        trip = (await repo.getTrip(tripId))!;
        expect(trip.photoMatchStatus, PhotoMatchStatus.completed);
        expect(trip.photos, hasLength(5));
      });

      test('limited access is recorded and uses the shared photos', () async {
        library.access = PhotoAccess.limited;
        library.photos = [library.photos.first];
        expect(await photos.match(tripId), PhotoMatchOutcome.limited);
        final trip = (await repo.getTrip(tripId))!;
        expect(trip.photoMatchStatus, PhotoMatchStatus.limited);
        expect(trip.photos, hasLength(1));
      });

      test('a library error marks the step failed without touching the trip', () async {
        library.failOnFind = true;
        expect(await photos.match(tripId), PhotoMatchOutcome.failed);
        var trip = (await repo.getTrip(tripId))!;
        expect(trip.photoMatchStatus, PhotoMatchStatus.failed);
        expect(trip.status, 'completed');
        expect(trip.gpsPoints, hasLength(seeded.pointCount));
        expect(trip.stops, hasLength(2));

        library.failOnFind = false;
        expect(await photos.match(tripId), PhotoMatchOutcome.completed);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.photoMatchStatus, PhotoMatchStatus.completed);
      });

      test('10. deleted originals / revoked access keep the record and edits', () async {
        await photos.match(tripId);
        var trip = (await repo.getTrip(tripId))!;
        await photos.exclude(tripId, find(trip, 'sight').id);
        library.deleted.addAll({'cafe-gps', 'sight'});

        expect(await photos.match(tripId), PhotoMatchOutcome.completed);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.photos, hasLength(5), reason: 'rows are never auto-deleted');
        expect(find(trip, 'sight').isExcluded, isTrue);
        expect(await library.thumbnail('cafe-gps'), isNull);

        // Access revoked afterwards: nothing is lost either.
        library.access = PhotoAccess.denied;
        expect(await photos.match(tripId), PhotoMatchOutcome.noAccess);
        trip = (await repo.getTrip(tripId))!;
        expect(trip.photos, hasLength(5));
      });

      test('picker fallback adds photos without permission and without duplicates', () async {
        library.access = PhotoAccess.denied;
        library.picked = [
          const PhotoMetadata(
            localPath: '/cache/IMG_1.jpg',
            takenAt: null,
          ),
          PhotoMetadata(localPath: '/cache/IMG_2.jpg', takenAt: at(9, 45)),
        ];
        await photos.addPickedPhotos(tripId);
        await photos.addPickedPhotos(tripId);
        final trip = (await repo.getTrip(tripId))!;
        expect(trip.photos, hasLength(2));
        final timed = trip.photos.firstWhere((p) => p.takenAt != null);
        expect(timed.stopId, trip.stops[0].id);
        expect(trip.photos.firstWhere((p) => p.takenAt == null).isUnclassified, isTrue);
      });

      test('matchPending only runs for real completed trips', () async {
        final all = await repo.getRecentTrips();
        expect(await photos.matchPending(all.where((t) => t.isDemo)), isFalse);
        expect(await photos.matchPending(all.where((t) => !t.isDemo)), isTrue);
        final again = await repo.getRecentTrips();
        expect(await photos.matchPending(again.where((t) => !t.isDemo)), isFalse);
      });

      test('simultaneous requests run one search', () async {
        await Future.wait([photos.match(tripId), photos.match(tripId)]);
        expect(library.findCalls, 1);
      });

      test('12. hundreds of photos are stored and matched in time', () async {
        library.photos = [
          for (var i = 0; i < 400; i++)
            PhotoMetadata(
              assetId: 'bulk$i',
              takenAt: at(9, 0).add(Duration(seconds: i * 9)),
            ),
        ];
        final watch = Stopwatch()..start();
        await photos.match(tripId);
        watch.stop();
        expect((await repo.getPhotos(tripId)).length, 400);
        expect(watch.elapsedMilliseconds, lessThan(8000));
      });
    });
  }

  test('database v2 -> v3 keeps stops and adds photo columns', () async {
    final dir = Directory.systemTemp.createTempSync('route_story_db_v2');
    final path = '${dir.path}/route_story.db';
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE trips (id TEXT PRIMARY KEY, title TEXT NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER, total_distance REAL NOT NULL, status TEXT NOT NULL, privacy_setting TEXT NOT NULL, share_setting TEXT NOT NULL, stop_analysis_status TEXT NOT NULL DEFAULT \'pending\')',
          );
          await db.execute(
            'CREATE TABLE gps_points (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, altitude REAL NOT NULL, timestamp INTEGER NOT NULL, accuracy REAL NOT NULL, speed REAL, heading REAL)',
          );
          await db.execute(
            'CREATE TABLE manual_markers (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, timestamp INTEGER NOT NULL, memo TEXT)',
          );
          await db.execute(
            'CREATE TABLE stops (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, place_name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, arrival_time INTEGER NOT NULL, departure_time INTEGER, source TEXT NOT NULL, memo TEXT, is_excluded INTEGER NOT NULL DEFAULT 0, is_name_edited INTEGER NOT NULL DEFAULT 0, is_user_modified INTEGER NOT NULL DEFAULT 0, marker_ids TEXT NOT NULL DEFAULT \'\')',
          );
        },
      ),
    );
    await v2.insert('trips', {
      'id': 't',
      'title': 'v2 여행',
      'start_time': 1000,
      'end_time': 2000,
      'total_distance': 1234.5,
      'status': 'completed',
      'privacy_setting': 'private',
      'share_setting': 'off',
      'stop_analysis_status': 'completed',
    });
    await v2.insert('stops', {
      'id': 's',
      'trip_id': 't',
      'place_name': '내가 지은 이름',
      'latitude': 37.5,
      'longitude': 127.0,
      'arrival_time': 1100,
      'source': 'automatic',
      'is_name_edited': 1,
      'is_user_modified': 1,
    });
    await v2.close();

    final repo = LocalTripRepository(
      databaseOpener: () =>
          LocalTripRepository.openAt(path, factory: databaseFactoryFfi),
    );
    final trip = (await repo.getTrip('t'))!;
    expect(trip.totalDistance, 1234.5, reason: 'stored values are not converted');
    expect(trip.stops.single.placeName, '내가 지은 이름');
    expect(trip.stops.single.coverPhotoId, isNull);
    expect(trip.photoMatchStatus, PhotoMatchStatus.pending);
    expect(trip.photos, isEmpty);
    await repo.savePhotos(
      't',
      upserts: [const TripPhoto(id: 'p', tripId: 't', assetId: 'a')],
      status: PhotoMatchStatus.completed,
    );
    expect((await repo.getPhotos('t')).single.assetId, 'a');
  });
}
