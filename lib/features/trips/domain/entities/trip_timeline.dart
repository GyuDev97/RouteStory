import 'stop.dart';
import 'trip_photo.dart';

/// One visit in the result timeline.
class TimelineStop {
  const TimelineStop({
    required this.stop,
    required this.order,
    required this.photos,
  });
  final Stop stop;

  /// 1-based position in time order.
  final int order;

  /// Photos of this visit, the representative photo first.
  final List<TripPhoto> photos;

  TripPhoto? get cover => photos.firstOrNull;
}

/// Everything the result screen shows below the header, derived from the
/// stored trip. Nothing here is stored; building it twice gives the same
/// result.
class TripTimeline {
  const TripTimeline({
    required this.stops,
    required this.routePhotos,
    required this.unclassifiedPhotos,
    required this.excludedPhotos,
    required this.coverPhoto,
  });

  /// Visits in arrival order.
  final List<TimelineStop> stops;

  /// Taken while moving; placed on the route, not on a stop.
  final List<TripPhoto> routePhotos;

  /// Not placed anywhere, or placed on a stop that no longer exists / was
  /// excluded. Never dropped from the result.
  final List<TripPhoto> unclassifiedPhotos;

  /// Photos the user removed from the result (can be restored).
  final List<TripPhoto> excludedPhotos;

  /// The trip's representative photo, or null if there is no usable photo.
  final TripPhoto? coverPhoto;

  int get activePhotoCount =>
      stops.fold(0, (n, s) => n + s.photos.length) +
      routePhotos.length +
      unclassifiedPhotos.length;
  bool get hasContent => stops.isNotEmpty || activePhotoCount > 0;
}
