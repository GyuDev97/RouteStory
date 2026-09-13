import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/app/route_story_app.dart';
import 'package:route_story/core/services/location_tracking_service.dart';
import 'package:route_story/features/trips/application/trip_providers.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/gps_point.dart';

class _FakeLocationService implements LocationTrackingService {
  @override
  Future<LocationReadiness> ensureReady() async => LocationReadiness.ready;
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<GpsPoint> watchPoints() => Stream.fromIterable([
    GpsPoint(
      latitude: 37.69,
      longitude: 129.03,
      altitude: 10,
      timestamp: DateTime.now(),
      accuracy: 8,
    ),
    GpsPoint(
      latitude: 37.6902,
      longitude: 129.0302,
      altitude: 10,
      timestamp: DateTime.now().add(const Duration(seconds: 10)),
      accuracy: 8,
    ),
  ]);
}

void main() {
  testWidgets('starts, records, and completes a trip', (tester) async {
    await tester.pumpWidget(
      RouteStoryApp(
        overrides: [
          tripRepositoryProvider.overrideWithValue(MemoryTripRepository()),
          locationTrackingServiceProvider.overrideWithValue(
            _FakeLocationService(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('여행 시작'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('여행을 기록 중이에요'), findsOneWidget);
  });
}
