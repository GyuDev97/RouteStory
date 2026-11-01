import '../../domain/entities/stop.dart';
import '../../domain/entities/gps_point.dart';
import '../../domain/entities/manual_marker.dart';
import '../../domain/entities/trip.dart';
import '../../domain/entities/trip_photo.dart';
import '../../domain/repositories/trip_repository.dart';

abstract final class DemoImages {
  static const coast = 'assets/images/east_coast_hero.png';
  static const coffee = 'assets/images/coffee_stop.png';
}

class MemoryTripRepository implements TripRepository {
  final List<Trip> _trips = [
    Trip(
      id: 'coast-01',
      title: '늦여름, 동해',
      startTime: DateTime(2026, 8, 24, 9, 20),
      endTime: DateTime(2026, 8, 24, 17, 40),
      totalDistance: 184.6,
      isDemo: true,
      stopAnalysisStatus: StopAnalysisStatus.completed,
      stops: [
        Stop(
          id: 's1',
          placeName: '정동진 해변',
          latitude: 37.689,
          longitude: 129.033,
          arrivalTime: DateTime(2026, 8, 24, 11, 10),
          photoIds: const ['p1', 'p2', 'p3'],
        ),
        Stop(
          id: 's2',
          placeName: '안목 커피거리',
          latitude: 37.773,
          longitude: 128.947,
          arrivalTime: DateTime(2026, 8, 24, 14, 5),
          photoIds: const ['p4', 'p5', 'p6', 'p7'],
        ),
      ],
      photos: List.generate(
        7,
        (index) => TripPhoto(
          id: 'p${index + 1}',
          localPath: index < 3 ? DemoImages.coast : DemoImages.coffee,
          takenAt: DateTime(2026, 8, 24, 11 + index, 10),
          stopId: index < 3 ? 's1' : 's2',
        ),
      ),
    ),
    Trip(
      id: 'seorak-01',
      title: '가을의 설악',
      startTime: DateTime(2026, 9, 7, 8),
      endTime: DateTime(2026, 9, 7, 16, 30),
      totalDistance: 312,
      isDemo: true,
      stopAnalysisStatus: StopAnalysisStatus.completed,
      stops: [
        Stop(
          id: 's3',
          placeName: '한계령',
          latitude: 38.1,
          longitude: 128.3,
          arrivalTime: DateTime(2026, 9, 7, 10),
        ),
      ],
      photos: [
        TripPhoto(
          id: 'p8',
          localPath: DemoImages.coffee,
          takenAt: DateTime(2026, 9, 7, 10),
          stopId: 's3',
        ),
      ],
    ),
  ];
  final Map<String, List<Stop>> _storedStops = {};
  final List<ManualMarker> _markers = [];
  final Map<String, List<GpsPoint>> _points = {};

  Trip _withStops(Trip trip) {
    if (trip.isDemo) return trip;
    final all = [...?_storedStops[trip.id]]
      ..sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
    return Trip(
      id: trip.id,
      title: trip.title,
      startTime: trip.startTime,
      endTime: trip.endTime,
      totalDistance: trip.totalDistance,
      gpsPoints: trip.gpsPoints.isEmpty
          ? (_points[trip.id] ?? const [])
          : trip.gpsPoints,
      stops: all.where((s) => !s.isExcluded).toList(),
      excludedStops: all.where((s) => s.isExcluded).toList(),
      privacySetting: trip.privacySetting,
      shareSetting: trip.shareSetting,
      status: trip.status,
      stopAnalysisStatus: trip.stopAnalysisStatus,
    );
  }

  @override
  Future<List<Trip>> getRecentTrips() async =>
      List.unmodifiable(_trips.map(_withStops));
  @override
  Future<Trip?> getTrip(String id) async => _trips
      .where((trip) => trip.id == id)
      .map(_withStops)
      .cast<Trip?>()
      .firstOrNull;
  @override
  Future<Trip?> getRecordingTrip() async => _trips
      .where((trip) => trip.status == 'recording')
      .cast<Trip?>()
      .firstOrNull;
  @override
  Future<void> saveTrip(Trip trip) async {
    _trips.removeWhere((t) => t.id == trip.id);
    _trips.insert(0, trip);
  }

  @override
  Future<void> saveGpsPoint(String tripId, GpsPoint point) async =>
      _points.putIfAbsent(tripId, () => []).add(point);
  @override
  Future<void> saveManualMarker(ManualMarker marker) async =>
      _markers.add(marker);
  @override
  Future<List<ManualMarker>> getManualMarkers(String tripId) async =>
      _markers.where((m) => m.tripId == tripId).toList();
  @override
  Future<List<Stop>> getAllStops(String tripId) async => [
    ...?_storedStops[tripId],
  ];
  @override
  Future<void> saveStopChanges(
    String tripId, {
    List<Stop> upserts = const [],
    List<String> deleteIds = const [],
    StopAnalysisStatus? status,
  }) async {
    final stops = _storedStops.putIfAbsent(tripId, () => []);
    stops.removeWhere((s) => deleteIds.contains(s.id));
    for (final stop in upserts) {
      stops.removeWhere((s) => s.id == stop.id);
      stops.add(stop);
    }
    if (status != null) await setStopAnalysisStatus(tripId, status);
  }

  @override
  Future<void> setStopAnalysisStatus(
    String tripId,
    StopAnalysisStatus status,
  ) async {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index < 0) return;
    final t = _trips[index];
    _trips[index] = Trip(
      id: t.id,
      title: t.title,
      startTime: t.startTime,
      endTime: t.endTime,
      totalDistance: t.totalDistance,
      gpsPoints: t.gpsPoints,
      stops: t.stops,
      excludedStops: t.excludedStops,
      photos: t.photos,
      privacySetting: t.privacySetting,
      shareSetting: t.shareSetting,
      status: t.status,
      stopAnalysisStatus: status,
      isDemo: t.isDemo,
    );
  }
}
