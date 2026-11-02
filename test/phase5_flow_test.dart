import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/application/photo_matching_service.dart';
import 'package:route_story/features/trips/application/stop_service.dart';
import 'package:route_story/features/trips/application/trip_providers.dart';
import 'package:route_story/features/trips/application/trip_service.dart';
import 'package:route_story/features/trips/application/trip_task_queue.dart';
import 'package:route_story/features/trips/data/repositories/local_trip_repository.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/photo_metadata.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/entities/trip_photo.dart';
import 'package:route_story/features/trips/domain/repositories/trip_repository.dart';
import 'package:route_story/features/trips/domain/services/trip_progress.dart';
import 'package:route_story/features/trips/domain/services/trip_timeline_builder.dart';
import 'package:route_story/features/trips/presentation/trip_result_screen.dart';
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
    group('result flow (${entry.key})', () {
      late TripRepository repo;
      late FakePhotoLibrary library;
      late StopService stops;
      late PhotoMatchingService photos;
      late TripService tripService;
      var stopRuns = 0;

      Future<Trip> load() async => (await repo.getTrip(tripId))!;

      setUp(() async {
        repo = entry.value();
        final queue = TripTaskQueue();
        stops = StopService(repo, queue: queue);
        stopRuns = 0;
        photos = PhotoMatchingService(
          repo,
          library = FakePhotoLibrary(),
          queue: queue,
          ensureStops: (id) {
            stopRuns++;
            return stops.analyze(id);
          },
        );
        tripService = TripService(repo, queue: queue);
        final seeded = await seed(repo);
        library.photos = [
          PhotoMetadata(
            assetId: 'cafe1',
            takenAt: at(9, 40),
            latitude: seeded.cafeLat,
            longitude: seeded.cafeLng,
            width: 4000,
            height: 3000,
          ),
          PhotoMetadata(assetId: 'cafe2', takenAt: at(9, 50), width: 4000, height: 3000),
          PhotoMetadata(assetId: 'sight', takenAt: at(10, 30), width: 300, height: 200),
          PhotoMetadata(assetId: 'road', takenAt: at(9, 10)),
          PhotoMetadata(assetId: 'unknown'),
        ];
      });

      test('everything is built automatically after one match', () async {
        await photos.match(tripId);
        final trip = await load();
        expect(TripProgress.of(trip).isComplete, isTrue);
        final timeline = TripTimelineBuilder.build(trip);
        expect(timeline.stops, hasLength(2));
        expect(timeline.stops[0].photos.map((p) => p.assetId), ['cafe1', 'cafe2']);
        expect(timeline.stops[1].photos.map((p) => p.assetId), ['sight']);
        expect(timeline.routePhotos.map((p) => p.assetId), ['road']);
        expect(timeline.unclassifiedPhotos.map((p) => p.assetId), ['unknown']);
        // Large, placed on a stop, higher confidence: the GPS+time photo.
        expect(timeline.coverPhoto!.assetId, 'cafe1');
      });

      test('reopening gives the same result and runs nothing again', () async {
        await photos.match(tripId);
        final first = TripTimelineBuilder.build(await load());
        final finds = library.findCalls;
        final runs = stopRuns;
        final second = TripTimelineBuilder.build(await load());
        expect(second.coverPhoto!.id, first.coverPhoto!.id);
        expect(second.stops.map((s) => s.photos.length), first.stops.map((s) => s.photos.length));
        expect(library.findCalls, finds);
        // Matching again does not redo the stop analysis that already finished.
        await photos.match(tripId);
        expect(stopRuns, runs);
      });

      test('trip title is stored, and survives re-analysis and re-matching', () async {
        await tripService.rename(tripId, '  제주 한 바퀴  ');
        await tripService.rename(tripId, '   ');
        await photos.match(tripId);
        await stops.analyze(tripId);
        await photos.match(tripId);
        expect((await load()).title, '제주 한 바퀴');
      });

      test('chosen cover photo survives re-matching; exclusion falls back; auto restores', () async {
        await photos.match(tripId);
        var trip = await load();
        final mine = trip.photos.firstWhere((p) => p.assetId == 'road');
        await tripService.setCoverPhoto(tripId, mine.id);
        await photos.match(tripId);
        await stops.analyze(tripId);
        trip = await load();
        expect(trip.coverPhotoId, mine.id);
        expect(TripTimelineBuilder.build(trip).coverPhoto!.id, mine.id);

        await photos.exclude(tripId, mine.id);
        trip = await load();
        expect(trip.coverPhotoId, mine.id, reason: 'the choice is remembered');
        expect(TripTimelineBuilder.build(trip).coverPhoto!.assetId, 'cafe1');
        await photos.restore(tripId, mine.id);
        expect(TripTimelineBuilder.build(await load()).coverPhoto!.id, mine.id);

        await tripService.clearCoverPhoto(tripId);
        trip = await load();
        expect(trip.coverPhotoId, isNull);
        expect(TripTimelineBuilder.build(trip).coverPhoto!.assetId, 'cafe1');
      });

      test('merging stops rebuilds the timeline with all photos', () async {
        await photos.match(tripId);
        var trip = await load();
        await stops.mergeWithNext(tripId, trip.stops[0].id);
        trip = await load();
        final timeline = TripTimelineBuilder.build(trip);
        expect(timeline.stops, hasLength(1));
        expect(
          timeline.stops.single.photos.map((p) => p.assetId).toSet(),
          {'cafe1', 'cafe2', 'sight'},
        );
        expect(timeline.unclassifiedPhotos.map((p) => p.assetId), ['unknown']);
      });

      test('moving and excluding photos shows up in the next timeline', () async {
        await photos.match(tripId);
        var trip = await load();
        final road = trip.photos.firstWhere((p) => p.assetId == 'road');
        final unknown = trip.photos.firstWhere((p) => p.assetId == 'unknown');
        await photos.moveToStop(tripId, road.id, trip.stops[1].id);
        await photos.moveToStop(tripId, unknown.id, trip.stops[0].id);
        await photos.exclude(tripId, trip.photos.firstWhere((p) => p.assetId == 'cafe2').id);
        await photos.match(tripId);

        final timeline = TripTimelineBuilder.build(await load());
        expect(timeline.routePhotos, isEmpty);
        expect(timeline.unclassifiedPhotos, isEmpty);
        expect(timeline.stops[0].photos.map((p) => p.assetId), ['cafe1', 'unknown']);
        expect(timeline.stops[1].photos.map((p) => p.assetId).toSet(), {'sight', 'road'});
        expect(timeline.excludedPhotos.map((p) => p.assetId), ['cafe2']);
      });

      test('a failed step is reported and a retry completes it', () async {
        library.failOnFind = true;
        await photos.match(tripId);
        var trip = await load();
        final progress = TripProgress.of(trip);
        expect(progress.hasFailure, isTrue);
        expect(trip.stops, hasLength(2), reason: 'GPS result is still there');
        expect(TripTimelineBuilder.build(trip).stops, hasLength(2));

        library.failOnFind = false;
        await photos.match(tripId, requestPermission: true);
        trip = await load();
        expect(TripProgress.of(trip).isComplete, isTrue);
        expect(trip.photos, isNotEmpty);
      });

      test('deleted originals still produce a complete timeline', () async {
        await photos.match(tripId);
        library.deleted.addAll({'cafe1', 'sight'});
        await photos.match(tripId);
        final timeline = TripTimelineBuilder.build(await load());
        expect(timeline.activePhotoCount, 5);
        expect(timeline.coverPhoto, isNotNull);
      });
    });
  }

  test('database v3 -> v4 keeps data and adds cover/size columns', () async {
    final dir = Directory.systemTemp.createTempSync('route_story_db_v3');
    final path = '${dir.path}/route_story.db';
    final v3 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE trips (id TEXT PRIMARY KEY, title TEXT NOT NULL, start_time INTEGER NOT NULL, end_time INTEGER, total_distance REAL NOT NULL, status TEXT NOT NULL, privacy_setting TEXT NOT NULL, share_setting TEXT NOT NULL, stop_analysis_status TEXT NOT NULL DEFAULT \'pending\', photo_match_status TEXT NOT NULL DEFAULT \'pending\')',
          );
          await db.execute(
            'CREATE TABLE gps_points (id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, altitude REAL NOT NULL, timestamp INTEGER NOT NULL, accuracy REAL NOT NULL, speed REAL, heading REAL)',
          );
          await db.execute(
            'CREATE TABLE manual_markers (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, timestamp INTEGER NOT NULL, memo TEXT)',
          );
          await db.execute(
            'CREATE TABLE stops (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, place_name TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, arrival_time INTEGER NOT NULL, departure_time INTEGER, source TEXT NOT NULL, memo TEXT, is_excluded INTEGER NOT NULL DEFAULT 0, is_name_edited INTEGER NOT NULL DEFAULT 0, is_user_modified INTEGER NOT NULL DEFAULT 0, marker_ids TEXT NOT NULL DEFAULT \'\', cover_photo_id TEXT)',
          );
          await db.execute(
            'CREATE TABLE photos (id TEXT PRIMARY KEY, trip_id TEXT NOT NULL, asset_id TEXT, local_path TEXT NOT NULL DEFAULT \'\', taken_at INTEGER, latitude REAL, longitude REAL, stop_id TEXT, match_method TEXT NOT NULL, confidence REAL NOT NULL DEFAULT 0, is_manually_edited INTEGER NOT NULL DEFAULT 0, is_excluded INTEGER NOT NULL DEFAULT 0)',
          );
        },
      ),
    );
    await v3.insert('trips', {
      'id': 't',
      'title': '내 여행',
      'start_time': 1000,
      'total_distance': 777.0,
      'status': 'completed',
      'privacy_setting': 'private',
      'share_setting': 'off',
      'stop_analysis_status': 'completed',
      'photo_match_status': 'completed',
    });
    await v3.insert('photos', {
      'id': 'p',
      'trip_id': 't',
      'asset_id': 'a',
      'match_method': 'time',
      'is_manually_edited': 1,
    });
    await v3.close();

    final repo = LocalTripRepository(
      databaseOpener: () =>
          LocalTripRepository.openAt(path, factory: databaseFactoryFfi),
    );
    var trip = (await repo.getTrip('t'))!;
    expect(trip.title, '내 여행');
    expect(trip.totalDistance, 777.0);
    expect(trip.coverPhotoId, isNull);
    expect(trip.photos.single.isManuallyEdited, isTrue);
    expect(trip.photos.single.width, isNull);
    await repo.updateTripDetails('t', title: '바뀐 제목', coverPhotoId: 'p');
    trip = (await repo.getTrip('t'))!;
    expect(trip.title, '바뀐 제목');
    expect(trip.coverPhotoId, 'p');
    await repo.updateTripDetails('t', clearCover: true);
    expect((await repo.getTrip('t'))!.coverPhotoId, isNull);
  });

  group('result screen', () {
    Future<(MemoryTripRepository, Trip)> setup({
      PhotoMatchStatus photoStatus = PhotoMatchStatus.completed,
      StopAnalysisStatus stopStatus = StopAnalysisStatus.completed,
      int stopCount = 1,
      int photoCount = 0,
    }) async {
      final repo = MemoryTripRepository();
      await repo.saveTrip(
        Trip(
          id: 'real',
          title: '오늘의 여정',
          startTime: at(9, 0),
          endTime: at(20, 0),
          totalDistance: 9000,
          stopAnalysisStatus: stopStatus,
          photoMatchStatus: photoStatus,
        ),
      );
      await repo.saveStopChanges(
        'real',
        upserts: [
          for (var i = 0; i < stopCount; i++)
            Stop(
              id: 's$i',
              tripId: 'real',
              placeName: '장소$i',
              latitude: 37.5,
              longitude: 127,
              arrivalTime: at(9 + i % 10, 0),
              departureTime: at(9 + i % 10, 40),
            ),
        ],
      );
      await repo.savePhotos(
        'real',
        upserts: [
          for (var i = 0; i < photoCount; i++)
            TripPhoto(
              id: 'p$i',
              tripId: 'real',
              assetId: 'p$i',
              takenAt: at(9 + i % 10, 5 + i % 30),
              stopId: stopCount == 0 ? null : 's${i % stopCount}',
              matchMethod: stopCount == 0
                  ? PhotoMatchMethod.route
                  : PhotoMatchMethod.time,
              width: 4000,
              height: 3000,
            ),
        ],
      );
      return (repo, (await repo.getTrip('real'))!);
    }

    Future<void> pump(
      WidgetTester tester,
      MemoryTripRepository repo,
      Trip trip, {
      FakePhotoLibrary? library,
      bool settle = true,
    }) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripRepositoryProvider.overrideWithValue(repo),
            photoLibraryServiceProvider.overrideWithValue(
              library ?? FakePhotoLibrary(),
            ),
          ],
          child: MaterialApp(home: TripResultScreen(trip: trip)),
        ),
      );
      settle ? await tester.pumpAndSettle() : await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('shows live progress while steps are still running', (tester) async {
      final (repo, trip) = await setup(photoStatus: PhotoMatchStatus.pending);
      await pump(tester, repo, trip, settle: false);
      expect(find.text('여행을 정리하고 있어요'), findsOneWidget);
      expect(find.text('GPS 기록 정리'), findsOneWidget);
      expect(find.text('방문 장소 분석'), findsOneWidget);
      expect(find.text('사진 연결'), findsOneWidget);
      expect(find.text('여행 결과 구성'), findsOneWidget);
      expect(find.text('장소0'), findsOneWidget, reason: 'GPS result already shown');
    });

    testWidgets('hides progress when done, offers retry when failed', (tester) async {
      final (repo, trip) = await setup();
      await pump(tester, repo, trip);
      expect(find.text('여행을 정리하고 있어요'), findsNothing);
      expect(find.text('일부 단계를 마치지 못했어요'), findsNothing);
    });

    testWidgets('a failed photo step shows retry and recovers', (tester) async {
      final (repo, trip) = await setup(photoStatus: PhotoMatchStatus.failed);
      final library = FakePhotoLibrary(photos: [
        PhotoMetadata(assetId: 'found', takenAt: at(9, 10)),
      ]);
      await pump(tester, repo, trip, library: library);
      expect(find.text('일부 단계를 마치지 못했어요'), findsOneWidget);
      await tester.tap(find.text('다시 시도').first);
      await tester.pumpAndSettle();
      expect(find.text('일부 단계를 마치지 못했어요'), findsNothing);
      expect((await repo.getTrip('real'))!.photoMatchStatus, PhotoMatchStatus.completed);
      expect(await repo.getPhotos('real'), hasLength(1));
    });

    testWidgets('editing the title persists', (tester) async {
      final (repo, trip) = await setup();
      await pump(tester, repo, trip);
      await tester.tap(find.byTooltip('제목 수정'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '제주 한 바퀴');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.text('제주 한 바퀴'), findsOneWidget);
      expect((await repo.getTrip('real'))!.title, '제주 한 바퀴');
    });

    testWidgets('tapping the cover lets the user choose another photo', (tester) async {
      final (repo, trip) = await setup(photoCount: 4);
      await pump(tester, repo, trip);
      await tester.tap(find.byType(AspectRatio).first);
      await tester.pumpAndSettle();
      expect(find.text('여행 대표 사진'), findsOneWidget);
      await tester.tap(find.byType(Image).last);
      await tester.pumpAndSettle();
      expect((await repo.getTrip('real'))!.coverPhotoId, isNotNull);
    });

    testWidgets('no stops, only route photos: still a complete page', (tester) async {
      final (repo, trip) = await setup(stopCount: 0, photoCount: 6);
      await pump(tester, repo, trip);
      expect(find.text('오래 머문 장소가 없었어요.'), findsOneWidget);
      expect(find.text('이동 중 찍은 사진'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no stops and no photos is calm, not an error', (tester) async {
      final (repo, trip) = await setup(stopCount: 0);
      await pump(tester, repo, trip);
      expect(find.text('오래 머문 장소가 없었어요.'), findsOneWidget);
      expect(find.text('일부 단계를 마치지 못했어요'), findsNothing);
    });

    testWidgets('a big trip (20 stops, 300 photos) renders without trouble', (tester) async {
      final (repo, trip) = await setup(stopCount: 20, photoCount: 300);
      final watch = Stopwatch()..start();
      await pump(tester, repo, trip);
      watch.stop();
      expect(tester.takeException(), isNull);
      expect(watch.elapsedMilliseconds, lessThan(15000));
      // Only the visible part of the page builds thumbnails.
      expect(find.byType(Image).evaluate().length, lessThan(120));
    });

    testWidgets('a stop with dozens of photos can show all of them', (tester) async {
      final (repo, trip) = await setup(photoCount: 30);
      await pump(tester, repo, trip);
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('30 Photos'), findsOneWidget);
      await tester.tap(find.text('사진 26장 더 보기'));
      await tester.pumpAndSettle();
      expect(find.text('접기'), findsOneWidget);
    });
  });
}
