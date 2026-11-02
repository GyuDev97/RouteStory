/// Thresholds for photo matching. Initial hypotheses, to be tuned with real
/// trips.
class PhotoMatchingConfig {
  const PhotoMatchingConfig({
    this.tripTimeMargin = const Duration(minutes: 5),
    this.stopTimeMargin = const Duration(minutes: 3),
    this.stopPhotoRadiusMeters = 250,
    this.maxRouteGap = const Duration(minutes: 5),
    this.maxRouteConflictMeters = 500,
  });

  /// Photos taken this long before the start / after the end still count.
  /// Everything further outside the trip is ignored.
  final Duration tripTimeMargin;

  /// A photo taken this close to a stop's span still counts as "at the stop".
  final Duration stopTimeMargin;

  /// A photo's own GPS must be within this distance of the stop. Larger than
  /// the 100 m stop radius because photo GPS is less precise.
  final double stopPhotoRadiusMeters;

  /// Route placement needs GPS fixes on both sides of the photo no further
  /// apart than this; otherwise the position would be a guess.
  final Duration maxRouteGap;

  /// If the photo's own GPS is further than this from the position
  /// interpolated from the route, time and place contradict: stay unclassified.
  final double maxRouteConflictMeters;
}
