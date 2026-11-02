enum PhotoMatchMethod {
  /// Not placed anywhere (unclassified).
  none,
  timeAndLocation,
  time,

  /// Taken while moving; placed on the route, not on a stop.
  route,
  manual,
}

/// A photo of a trip. Only metadata and a reference are stored, never the
/// image itself. [assetId] is the OS photo library id (preferred); [localPath]
/// is only a hint (or the bundled image of demo trips) and may stop existing.
class TripPhoto {
  const TripPhoto({
    required this.id,
    this.tripId = '',
    this.assetId,
    this.localPath = '',
    this.latitude,
    this.longitude,
    this.takenAt,
    this.stopId,
    this.matchMethod = PhotoMatchMethod.none,
    this.matchConfidence = 0,
    this.isManuallyEdited = false,
    this.isExcluded = false,
    this.width,
    this.height,
  });
  final String id, tripId, localPath;
  final String? assetId;
  final double? latitude, longitude;
  final DateTime? takenAt;
  final String? stopId;
  final PhotoMatchMethod matchMethod;
  final double matchConfidence;

  /// The user moved, detached or excluded this photo; re-matching leaves it.
  final bool isManuallyEdited;
  final bool isExcluded;

  /// Pixel size when the library reported it (used only to prefer larger photos).
  final int? width, height;

  bool get isOnStop => stopId != null;
  bool get isRoutePhoto => stopId == null && matchMethod == PhotoMatchMethod.route;
  bool get isUnclassified =>
      stopId == null && matchMethod != PhotoMatchMethod.route;

  TripPhoto copyWith({
    String? stopId,
    bool clearStop = false,
    PhotoMatchMethod? matchMethod,
    double? matchConfidence,
    bool? isManuallyEdited,
    bool? isExcluded,
  }) => TripPhoto(
    id: id,
    tripId: tripId,
    assetId: assetId,
    localPath: localPath,
    latitude: latitude,
    longitude: longitude,
    takenAt: takenAt,
    stopId: clearStop ? null : stopId ?? this.stopId,
    matchMethod: matchMethod ?? this.matchMethod,
    matchConfidence: matchConfidence ?? this.matchConfidence,
    isManuallyEdited: isManuallyEdited ?? this.isManuallyEdited,
    isExcluded: isExcluded ?? this.isExcluded,
    width: width,
    height: height,
  );
}
