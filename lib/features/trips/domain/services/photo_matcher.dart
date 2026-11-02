import '../entities/gps_point.dart';
import '../entities/photo_metadata.dart';
import '../entities/stop.dart';
import '../entities/trip_photo.dart';
import 'distance_calculator.dart';
import 'photo_matching_config.dart';
import 'stop_detection_service.dart';

class PhotoMatch {
  const PhotoMatch({
    required this.photo,
    required this.method,
    this.stopId,
    this.confidence = 0,
  });
  final PhotoMetadata photo;
  final PhotoMatchMethod method;
  final String? stopId;
  final double confidence;
}

/// Pure photo-to-stop matching.
///
/// Order: time+location, time only, route, otherwise unclassified. Anything
/// ambiguous or contradictory is left unclassified rather than guessed, and a
/// photo is never attached to the "nearest" stop just because none fits.
class PhotoMatcher {
  const PhotoMatcher([this.config = const PhotoMatchingConfig()]);
  final PhotoMatchingConfig config;

  /// Returns one result per photo taken within the trip window; photos outside
  /// it are dropped.
  List<PhotoMatch> match({
    required DateTime tripStart,
    required DateTime tripEnd,
    required List<Stop> stops,
    required List<GpsPoint> gpsPoints,
    required List<PhotoMetadata> photos,
  }) {
    final visibleStops = stops.where((s) => !s.isExcluded).toList();
    final route = const StopDetectionService().cleanPoints(gpsPoints);
    final from = tripStart.subtract(config.tripTimeMargin);
    final to = tripEnd.add(config.tripTimeMargin);
    final seen = <String>{};
    final results = <PhotoMatch>[];
    for (final photo in photos) {
      if (!seen.add(photo.key)) continue;
      final taken = photo.takenAt;
      if (taken == null) {
        results.add(PhotoMatch(photo: photo, method: PhotoMatchMethod.none));
        continue;
      }
      if (taken.isBefore(from) || taken.isAfter(to)) continue;
      results.add(_matchOne(photo, taken, visibleStops, route));
    }
    return results;
  }

  PhotoMatch _matchOne(
    PhotoMetadata photo,
    DateTime taken,
    List<Stop> stops,
    List<GpsPoint> route,
  ) {
    const unclassified = PhotoMatchMethod.none;
    final candidates = _timeCandidates(stops, taken);
    if (candidates.isNotEmpty) {
      if (photo.hasLocation) {
        final near = [
          for (final stop in candidates)
            if (_distanceToStop(photo, stop) <= config.stopPhotoRadiusMeters)
              stop,
        ];
        if (near.length != 1) {
          // Wrong place for the time, or several fits: do not decide.
          return PhotoMatch(photo: photo, method: unclassified);
        }
        final d = _distanceToStop(photo, near.single);
        return PhotoMatch(
          photo: photo,
          method: PhotoMatchMethod.timeAndLocation,
          stopId: near.single.id,
          confidence: 0.95 - 0.25 * (d / config.stopPhotoRadiusMeters),
        );
      }
      if (candidates.length == 1) {
        return PhotoMatch(
          photo: photo,
          method: PhotoMatchMethod.time,
          stopId: candidates.single.id,
          confidence: _strictlyInside(candidates.single, taken) ? 0.7 : 0.55,
        );
      }
      return PhotoMatch(photo: photo, method: unclassified);
    }
    return _matchRoute(photo, taken, route);
  }

  /// Stops that were being visited at [taken]. If exactly one stop contains
  /// the time, only that one counts; otherwise those within the margin do.
  List<Stop> _timeCandidates(List<Stop> stops, DateTime taken) {
    final strict = stops.where((s) => _strictlyInside(s, taken)).toList();
    if (strict.length == 1) return strict;
    return [
      for (final s in stops)
        if (!taken.isBefore(s.arrivalTime.subtract(config.stopTimeMargin)) &&
            !taken.isAfter(_end(s).add(config.stopTimeMargin)))
          s,
    ];
  }

  PhotoMatch _matchRoute(
    PhotoMetadata photo,
    DateTime taken,
    List<GpsPoint> route,
  ) {
    const unclassified = PhotoMatchMethod.none;
    final estimate = _positionAt(route, taken);
    if (estimate == null) {
      return PhotoMatch(photo: photo, method: unclassified);
    }
    var confidence = 0.8 - 0.4 * (estimate.gap.inSeconds / config.maxRouteGap.inSeconds);
    if (photo.hasLocation) {
      final conflict = DistanceCalculator.metersBetweenCoordinates(
        photo.latitude!,
        photo.longitude!,
        estimate.latitude,
        estimate.longitude,
      );
      if (conflict > config.maxRouteConflictMeters) {
        return PhotoMatch(photo: photo, method: unclassified);
      }
    } else {
      confidence -= 0.1;
    }
    return PhotoMatch(
      photo: photo,
      method: PhotoMatchMethod.route,
      confidence: confidence.clamp(0.1, 1.0),
    );
  }

  /// Interpolated route position at [time], or null when the surrounding
  /// fixes are missing or too far apart in time to trust.
  _Estimate? _positionAt(List<GpsPoint> route, DateTime time) {
    if (route.isEmpty) return null;
    var lo = 0, hi = route.length - 1;
    if (time.isBefore(route.first.timestamp) ||
        time.isAfter(route.last.timestamp)) {
      return null;
    }
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (route[mid].timestamp.isAfter(time)) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final a = route[lo], b = route[hi];
    final gap = b.timestamp.difference(a.timestamp);
    if (gap > config.maxRouteGap) return null;
    if (gap == Duration.zero) {
      return _Estimate(a.latitude, a.longitude, gap);
    }
    final f = time.difference(a.timestamp).inMilliseconds / gap.inMilliseconds;
    return _Estimate(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
      gap,
    );
  }

  double _distanceToStop(PhotoMetadata photo, Stop stop) =>
      DistanceCalculator.metersBetweenCoordinates(
        photo.latitude!,
        photo.longitude!,
        stop.latitude,
        stop.longitude,
      );

  DateTime _end(Stop s) => s.departureTime ?? s.arrivalTime;

  bool _strictlyInside(Stop s, DateTime t) =>
      !t.isBefore(s.arrivalTime) && !t.isAfter(_end(s));
}

class _Estimate {
  const _Estimate(this.latitude, this.longitude, this.gap);
  final double latitude, longitude;
  final Duration gap;
}
