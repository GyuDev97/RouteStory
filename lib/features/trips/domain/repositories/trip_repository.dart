import '../entities/gps_point.dart';
import '../entities/manual_marker.dart';
import '../entities/stop.dart';
import '../entities/trip.dart';
import '../entities/trip_photo.dart';

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
  /// [photoStopRemap] re-points photos from a removed stop id to its
  /// replacement in the same transaction (used by merges).
  Future<void> saveStopChanges(
    String tripId, {
    List<Stop> upserts = const [],
    List<String> deleteIds = const [],
    StopAnalysisStatus? status,
    Map<String, String> photoStopRemap = const {},
  });
  Future<void> setStopAnalysisStatus(String tripId, StopAnalysisStatus status);

  /// Every stored photo reference of the trip, including excluded ones.
  Future<List<TripPhoto>> getPhotos(String tripId);

  /// Inserts or replaces photo rows (and optionally the match status)
  /// atomically. Never deletes; photo files are never touched.
  Future<void> savePhotos(
    String tripId, {
    List<TripPhoto> upserts = const [],
    PhotoMatchStatus? status,
  });
  Future<void> setPhotoMatchStatus(String tripId, PhotoMatchStatus status);

  /// User edits of the trip itself: its title and chosen cover photo.
  /// [clearCover] returns the cover to automatic selection.
  Future<void> updateTripDetails(
    String tripId, {
    String? title,
    String? coverPhotoId,
    bool clearCover = false,
  });
}
