import '../entities/gps_point.dart';
import '../entities/manual_marker.dart';
import '../entities/stop.dart';
import '../entities/trip.dart';

abstract interface class TripRepository {
  Future<List<Trip>> getRecentTrips();
  Future<Trip?> getTrip(String id);
  Future<Trip?> getRecordingTrip();
  Future<void> saveTrip(Trip trip);
  Future<void> saveGpsPoint(String tripId, GpsPoint point);
  Future<void> saveManualMarker(ManualMarker marker);
  Future<List<ManualMarker>> getManualMarkers(String tripId);

  /// Every stored stop of the trip, including excluded ones.
  Future<List<Stop>> getAllStops(String tripId);

  /// Applies stop changes (and optionally the analysis status) atomically.
  /// GPS points, markers and the trip row are never touched.
  Future<void> saveStopChanges(
    String tripId, {
    List<Stop> upserts = const [],
    List<String> deleteIds = const [],
    StopAnalysisStatus? status,
  });
  Future<void> setStopAnalysisStatus(String tripId, StopAnalysisStatus status);
}
