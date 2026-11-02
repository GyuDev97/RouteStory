import '../entities/gps_point.dart';
import 'distance_calculator.dart';

/// Read-only summary of a trip's stored GPS points, for development checks.
class GpsDebugStats {
  const GpsDebugStats({
    required this.pointCount,
    this.firstTime,
    this.lastTime,
    this.maxGap,
    this.averageInterval,
    this.averageAccuracy,
    required this.overAccuracyCount,
    required this.stopCount,
  });

  final int pointCount;
  final DateTime? firstTime, lastTime;

  /// Largest time between two consecutive stored points.
  final Duration? maxGap;
  final Duration? averageInterval;
  final double? averageAccuracy;

  /// Stored points whose accuracy value is worse than the limit. The recorder
  /// already drops such points, so this is normally 0.
  final int overAccuracyCount;
  final int stopCount;

  static GpsDebugStats fromPoints(
    List<GpsPoint> points, {
    required int stopCount,
    double accuracyLimit = DistanceCalculator.maximumAccuracyMeters,
  }) {
    if (points.isEmpty) {
      return GpsDebugStats(
        pointCount: 0,
        overAccuracyCount: 0,
        stopCount: stopCount,
      );
    }
    final sorted = [...points]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    var maxGap = Duration.zero;
    for (var i = 1; i < sorted.length; i++) {
      final gap = sorted[i].timestamp.difference(sorted[i - 1].timestamp);
      if (gap > maxGap) maxGap = gap;
    }
    final span = sorted.last.timestamp.difference(sorted.first.timestamp);
    return GpsDebugStats(
      pointCount: sorted.length,
      firstTime: sorted.first.timestamp,
      lastTime: sorted.last.timestamp,
      maxGap: sorted.length > 1 ? maxGap : null,
      averageInterval: sorted.length > 1 ? span ~/ (sorted.length - 1) : null,
      averageAccuracy:
          sorted.fold<double>(0, (sum, p) => sum + p.accuracy) / sorted.length,
      overAccuracyCount: sorted.where((p) => p.accuracy > accuracyLimit).length,
      stopCount: stopCount,
    );
  }
}
