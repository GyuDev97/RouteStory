import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/core/services/location_tracking_service.dart';
import 'package:route_story/features/trips/application/trip_providers.dart';
import 'package:route_story/features/trips/application/trip_recording_controller.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/gps_point.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';

import 'support/gps_scenario.dart';

class _ReplayLocation implements LocationTrackingService {
  _ReplayLocation(this.points);
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

void main() {
  test('finishing a trip analyzes its recorded points into stops', () async {
    final scenario = GpsScenario(start: DateTime.now().subtract(const Duration(hours: 3)))
      ..move(10.min, speed: 10)
      ..stay(30.min)
      ..move(10.min, speed: 10);
    final repo = MemoryTripRepository();
    final container = ProviderContainer(
      overrides: [
        tripRepositoryProvider.overrideWithValue(repo),
        locationTrackingServiceProvider.overrideWithValue(
          _ReplayLocation(scenario.points),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(tripRecordingControllerProvider.notifier);

    expect(await controller.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final trip = (await controller.finish())!;

    expect(trip.stopAnalysisStatus, StopAnalysisStatus.completed);
    expect(trip.gpsPoints, isNotEmpty);
    expect(trip.stops, hasLength(1));
    expect(trip.stops.single.source, StopSource.automatic);
    expect(trip.stops.single.dwell!.inMinutes, inInclusiveRange(28, 31));
  });
}
