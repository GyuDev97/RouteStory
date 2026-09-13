import '../entities/gps_point.dart';
import '../entities/manual_marker.dart';
import '../entities/trip.dart';

abstract interface class TripRepository {
  Future<List<Trip>> getRecentTrips();
  Future<Trip?> getTrip(String id);
  Future<Trip?> getRecordingTrip();
  Future<void> saveTrip(Trip trip);
  Future<void> saveGpsPoint(String tripId, GpsPoint point);
  Future<void> saveManualMarker(ManualMarker marker);
}
