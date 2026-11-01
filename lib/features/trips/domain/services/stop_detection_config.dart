/// Tunable thresholds for rule-based stop detection.
///
/// These are initial values for testing, not tuned results.
class StopDetectionConfig {
  const StopDetectionConfig({
    this.stopRadiusMeters = 100,
    this.minDwell = const Duration(minutes: 10),
    this.minPoints = 3,
    this.maxAccuracyMeters = 50,
    this.maxGap = const Duration(minutes: 3),
    this.maxStationaryGap = const Duration(minutes: 90),
    this.stationaryGapRadiusMeters = 50,
    this.driftTolerance = const Duration(seconds: 90),
    this.fragmentMergeGap = const Duration(minutes: 5),
    this.movingSpeedMetersPerSecond = 1.5,
    this.maxMovingFraction = 0.25,
    this.maxNetDriftMeters = 50,
    this.maxSpeedMetersPerSecond = 75,
    this.markerTimeTolerance = const Duration(minutes: 3),
  });

  /// Points must stay within this distance of the cluster centroid.
  final double stopRadiusMeters;

  /// Minimum time between first and last point of a stop.
  final Duration minDwell;

  /// A stop needs at least this many valid points; fewer is too little
  /// evidence to call a visit.
  final int minPoints;

  /// Points with a worse (larger) accuracy value are ignored.
  final double maxAccuracyMeters;

  /// A silence up to this long between two points of a stop counts as dwell.
  final Duration maxGap;

  /// A longer silence counts as dwell only if both neighbouring points are
  /// within [stationaryGapRadiusMeters] of each other and the silence is no
  /// longer than this. (The recorder uses a 10 m distance filter, so a truly
  /// stationary phone emits almost no points.)
  final Duration maxStationaryGap;
  final double stationaryGapRadiusMeters;

  /// Points outside the radius for at most this long are treated as GPS
  /// drift and do not end the stop.
  final Duration driftTolerance;

  /// Neighbouring fragments at the same place closer in time than this are
  /// merged into one stop.
  final Duration fragmentMergeGap;

  /// Reported speed above this counts as "moving" (traffic-jam guard).
  final double movingSpeedMetersPerSecond;
  final double maxMovingFraction;

  /// Max displacement between the first and last third of a stop (creeping
  /// traffic guard).
  final double maxNetDriftMeters;

  /// Jumps faster than this are rejected as GPS errors.
  final double maxSpeedMetersPerSecond;

  /// A ManualMarker links to a stop if made within this margin of its span.
  final Duration markerTimeTolerance;
}
