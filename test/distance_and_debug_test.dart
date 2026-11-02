import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/application/trip_providers.dart';
import 'package:route_story/features/trips/application/trip_recording_controller.dart';
import 'package:route_story/core/services/location_tracking_service.dart';
import 'package:route_story/features/trips/data/repositories/local_trip_repository.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/gps_point.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/services/distance_calculator.dart';
import 'package:route_story/features/trips/domain/services/distance_formatter.dart';
import 'package:route_story/features/trips/domain/services/gps_debug_stats.dart';
import 'package:route_story/features/trips/presentation/gps_debug_screen.dart';
import 'package:route_story/features/trips/presentation/trip_result_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_photo_library.dart';

class _Replay implements LocationTrackingService {
  _Replay(this.points);
  final List<GpsPoint> points;
  @override
  Future<LocationReadiness> ensureReady() async => LocationReadiness.ready;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<GpsPoint> watchPoints() => Stream.fromIterable(points);
}

GpsPoint pt(double lat, double lng, DateTime t, {double accuracy = 8}) =>
    GpsPoint(
      latitude: lat,
      longitude: lng,
      altitude: 0,
      timestamp: t,
      accuracy: accuracy,
    );

void main() {
  group('distance units (metres inside, km only for display)', () {
    test('formatKilometers converts metres', () {
      expect(formatKilometers(5000), '5.0 km');
      expect(formatKilometers(184600), '184.6 km');
      expect(formatKilometers(0), '0.0 km');
      expect(formatKilometers(432), '0.4 km');
    });

    test('0.001 degree of latitude is about 111 m', () {
      final d = DistanceCalculator.metersBetweenCoordinates(37.5, 127, 37.501, 127);
      expect(d, inInclusiveRange(110, 112));
    });

    test('demo trips store metres like real trips', () async {
      final demo = await MemoryTripRepository().getRecentTrips();
      expect(demo.first.totalDistance, 184600);
      expect(formatKilometers(demo.first.totalDistance), '184.6 km');
      expect(demo.every((t) => t.isDemo), isTrue);
    });

    test('a recorded trip accumulates metres', () async {
      final t0 = DateTime.now().subtract(const Duration(minutes: 5));
      final container = ProviderContainer(
        overrides: [
          tripRepositoryProvider.overrideWithValue(MemoryTripRepository()),
          photoLibraryServiceProvider.overrideWithValue(FakePhotoLibrary()),
          locationTrackingServiceProvider.overrideWithValue(
            _Replay([
              pt(37.5, 127, t0),
              pt(37.501, 127, t0.add(const Duration(seconds: 30))),
              pt(37.502, 127, t0.add(const Duration(seconds: 60))),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(tripRecordingControllerProvider.notifier);
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final trip = (await controller.finish())!;
      expect(trip.totalDistance, inInclusiveRange(220, 224));
    });

    test('stored distance is returned unchanged by the database', () async {
      sqfliteFfiInit();
      final repo = LocalTripRepository(
        databaseOpener: () => LocalTripRepository.openAt(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
          singleInstance: false,
        ),
      );
      await repo.saveTrip(
        Trip(
          id: 'x',
          title: 't',
          startTime: DateTime(2026),
          totalDistance: 12345.6,
        ),
      );
      expect((await repo.getTrip('x'))!.totalDistance, 12345.6);
    });

    testWidgets('result screen shows kilometres for a real trip', (tester) async {
      final repo = MemoryTripRepository();
      final trip = Trip(
        id: 'real',
        title: '오늘의 여정',
        startTime: DateTime(2026, 9, 1, 9),
        endTime: DateTime(2026, 9, 1, 10),
        totalDistance: 5230,
        stopAnalysisStatus: StopAnalysisStatus.completed,
        photoMatchStatus: PhotoMatchStatus.completed,
      );
      await repo.saveTrip(trip);
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripRepositoryProvider.overrideWithValue(repo),
            photoLibraryServiceProvider.overrideWithValue(FakePhotoLibrary()),
          ],
          child: MaterialApp(home: TripResultScreen(trip: trip)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5.2 km'), findsOneWidget);
      expect(find.textContaining('5230'), findsNothing);
    });
  });

  group('GPS debug stats', () {
    test('summarises count, span, gaps, intervals and accuracy', () {
      final t = DateTime(2026, 9, 1, 9);
      final stats = GpsDebugStats.fromPoints(
        [
          pt(37.5, 127, t.add(const Duration(seconds: 120)), accuracy: 20),
          pt(37.5, 127, t, accuracy: 10),
          pt(37.5, 127, t.add(const Duration(seconds: 30)), accuracy: 60),
        ],
        stopCount: 2,
      );
      expect(stats.pointCount, 3);
      expect(stats.firstTime, t);
      expect(stats.lastTime, t.add(const Duration(seconds: 120)));
      expect(stats.maxGap, const Duration(seconds: 90));
      expect(stats.averageInterval, const Duration(seconds: 60));
      expect(stats.averageAccuracy, 30);
      expect(stats.overAccuracyCount, 1);
      expect(stats.stopCount, 2);
    });

    test('empty and single-point trips do not throw', () {
      final empty = GpsDebugStats.fromPoints(const [], stopCount: 0);
      expect(empty.pointCount, 0);
      expect(empty.maxGap, isNull);
      final one = GpsDebugStats.fromPoints([pt(37, 127, DateTime(2026))], stopCount: 0);
      expect(one.pointCount, 1);
      expect(one.maxGap, isNull);
      expect(one.averageInterval, isNull);
    });

    testWidgets('debug screen renders the numbers', (tester) async {
      final t = DateTime(2026, 9, 1, 9);
      await tester.pumpWidget(
        MaterialApp(
          home: GpsDebugScreen(
            trip: Trip(
              id: 'd',
              title: '점검',
              startTime: t,
              totalDistance: 1500,
              gpsPoints: [pt(37.5, 127, t), pt(37.5, 127, t.add(const Duration(minutes: 2)))],
            ),
          ),
        ),
      );
      expect(find.text('GPS 포인트 수'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('2분 0초'), findsWidgets);
      expect(find.text('1.5 km'), findsOneWidget);
    });
  });
}
