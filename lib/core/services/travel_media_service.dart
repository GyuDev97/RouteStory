import '../../features/trips/domain/entities/trip_photo.dart';

/// Future gallery/camera import boundary; this MVP does not read device media.
abstract interface class TravelMediaService {
  Future<List<TripPhoto>> findPhotosForTrip(DateTime start, DateTime end);
}
