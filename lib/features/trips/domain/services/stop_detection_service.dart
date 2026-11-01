import '../entities/gps_point.dart';
import 'distance_calculator.dart';
import 'stop_candidate.dart';
import 'stop_detection_config.dart';

/// Rule-based stop detection: a stop is a place where the points stay inside
/// a radius around a running centroid for at least [StopDetectionConfig.minDwell].
///
/// Pure Dart. Input points may be unsorted, duplicated or invalid; the
/// result is conservative (uncertain cases are not reported as stops).
class StopDetectionService {
  const StopDetectionService([this.config = const StopDetectionConfig()]);
  final StopDetectionConfig config;

  List<StopCandidate> detect(List<GpsPoint> rawPoints) {
    final points = cleanPoints(rawPoints);
    if (points.length < 2) return const [];
    final merged = _mergeFragments(_cluster(points));
    return [
      for (final cluster in merged)
        if (_isStop(cluster.points)) _toCandidate(cluster.points),
    ];
  }

  /// Drops invalid fixes, sorts by time, de-duplicates timestamps and removes
  /// physically impossible jumps.
  List<GpsPoint> cleanPoints(List<GpsPoint> rawPoints) {
    final indexed = <(int, GpsPoint)>[
      for (final entry in rawPoints.indexed)
        if (_isValid(entry.$2)) (entry.$1, entry.$2),
    ];
    indexed.sort((a, b) {
      final byTime = a.$2.timestamp.compareTo(b.$2.timestamp);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
    final unique = <GpsPoint>[];
    for (final (_, point) in indexed) {
      if (unique.isNotEmpty && unique.last.timestamp == point.timestamp) {
        if (point.accuracy < unique.last.accuracy) unique.last = point;
        continue;
      }
      unique.add(point);
    }
    final kept = <GpsPoint>[];
    var rejectedInARow = 0;
    for (final point in unique) {
      if (kept.isEmpty || rejectedInARow >= 3 || _speedPlausible(kept.last, point)) {
        kept.add(point);
        rejectedInARow = 0;
      } else {
        rejectedInARow++;
      }
    }
    return kept;
  }

  bool _isValid(GpsPoint p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      !(p.latitude.abs() < 1e-9 && p.longitude.abs() < 1e-9) &&
      p.accuracy.isFinite &&
      p.accuracy >= 0 &&
      p.accuracy <= config.maxAccuracyMeters;

  bool _speedPlausible(GpsPoint a, GpsPoint b) {
    final seconds = b.timestamp.difference(a.timestamp).inMilliseconds / 1000;
    if (seconds <= 0) return false;
    return DistanceCalculator.metersBetween(a, b) / seconds <=
        config.maxSpeedMetersPerSecond;
  }

  List<_Cluster> _cluster(List<GpsPoint> points) {
    final clusters = <_Cluster>[];
    var start = 0;
    while (start < points.length) {
      final cluster = _Cluster()..add(start, points[start]);
      var lastInlier = start;
      var outside = 0;
      for (var j = start + 1; j < points.length; j++) {
        final point = points[j];
        final silence = point.timestamp.difference(points[lastInlier].timestamp);
        final inside =
            DistanceCalculator.metersBetweenCoordinates(
              point.latitude,
              point.longitude,
              cluster.latitude,
              cluster.longitude,
            ) <=
            config.stopRadiusMeters;
        if (!inside) {
          outside++;
          if (silence > config.driftTolerance) break;
          continue;
        }
        if (outside > 0 && silence > config.driftTolerance) break;
        if (silence > config.maxGap &&
            !_isStationaryGap(points[lastInlier], point, silence)) {
          break;
        }
        cluster.add(j, point);
        lastInlier = j;
        outside = 0;
      }
      if (cluster.points.length >= 2) {
        final dwell = cluster.points.last.timestamp.difference(
          cluster.points.first.timestamp,
        );
        if (dwell >= config.minDwell && !_passesMotionChecks(cluster.points)) {
          // Likely slow traffic: retry from later in the window so a real
          // stop at its end is not swallowed.
          start = start + 1 > cluster.indices[cluster.indices.length ~/ 3]
              ? start + 1
              : cluster.indices[cluster.indices.length ~/ 3];
          continue;
        }
        clusters.add(cluster);
      }
      start = lastInlier + 1;
    }
    return clusters;
  }

  bool _isStationaryGap(GpsPoint before, GpsPoint after, Duration silence) =>
      silence <= config.maxStationaryGap &&
      DistanceCalculator.metersBetween(before, after) <=
          config.stationaryGapRadiusMeters;

  List<_Cluster> _mergeFragments(List<_Cluster> clusters) {
    final merged = <_Cluster>[];
    for (final cluster in clusters) {
      // Rejoin with the latest earlier fragment at the same place that ended
      // shortly before; whatever lies in between was a brief drift burst.
      var target = -1;
      for (var k = merged.length - 1; k >= 0; k--) {
        final gap = cluster.points.first.timestamp.difference(
          merged[k].points.last.timestamp,
        );
        if (gap > config.fragmentMergeGap) break;
        final distance = DistanceCalculator.metersBetweenCoordinates(
          merged[k].latitude,
          merged[k].longitude,
          cluster.latitude,
          cluster.longitude,
        );
        if (distance <= config.stopRadiusMeters) {
          target = k;
          break;
        }
      }
      if (target < 0) {
        merged.add(cluster);
        continue;
      }
      merged.removeRange(target + 1, merged.length);
      for (final entry in cluster.indices.indexed) {
        merged[target].add(entry.$2, cluster.points[entry.$1]);
      }
    }
    return merged;
  }

  bool _isStop(List<GpsPoint> points) =>
      points.length >= config.minPoints &&
      points.last.timestamp.difference(points.first.timestamp) >=
          config.minDwell &&
      _passesMotionChecks(points);

  /// Rejects windows that look like slow traffic rather than a visit.
  bool _passesMotionChecks(List<GpsPoint> points) {
    final speeds = [
      for (final p in points)
        if (p.speed != null && p.speed!.isFinite && p.speed! >= 0) p.speed!,
    ];
    if (speeds.length >= 3) {
      final moving = speeds
          .where((s) => s > config.movingSpeedMetersPerSecond)
          .length;
      if (moving / speeds.length > config.maxMovingFraction) return false;
    }
    if (points.length >= 6) {
      final first = points.first.timestamp;
      final span = points.last.timestamp.difference(first);
      final early = first.add(span ~/ 3);
      final late = first.add(span * 2 ~/ 3);
      final head = points.where((p) => !p.timestamp.isAfter(early)).toList();
      final tail = points.where((p) => !p.timestamp.isBefore(late)).toList();
      if (head.isNotEmpty && tail.isNotEmpty) {
        final drift = DistanceCalculator.metersBetweenCoordinates(
          _median([for (final p in head) p.latitude]),
          _median([for (final p in head) p.longitude]),
          _median([for (final p in tail) p.latitude]),
          _median([for (final p in tail) p.longitude]),
        );
        if (drift > config.maxNetDriftMeters) return false;
      }
    }
    return true;
  }

  StopCandidate _toCandidate(List<GpsPoint> points) => StopCandidate(
    latitude: _median([for (final p in points) p.latitude]),
    longitude: _median([for (final p in points) p.longitude]),
    arrivalTime: points.first.timestamp,
    departureTime: points.last.timestamp,
    pointCount: points.length,
  );

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

class _Cluster {
  final points = <GpsPoint>[];
  final indices = <int>[];
  double _sumLatitude = 0, _sumLongitude = 0;
  double get latitude => _sumLatitude / points.length;
  double get longitude => _sumLongitude / points.length;
  void add(int index, GpsPoint point) {
    indices.add(index);
    points.add(point);
    _sumLatitude += point.latitude;
    _sumLongitude += point.longitude;
  }
}
