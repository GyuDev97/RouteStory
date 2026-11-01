enum StopSource { automatic, manual }

class Stop {
  const Stop({
    required this.id,
    this.tripId = '',
    required this.placeName,
    required this.latitude,
    required this.longitude,
    required this.arrivalTime,
    this.departureTime,
    this.memo,
    this.photoIds = const [],
    this.source = StopSource.automatic,
    this.isExcluded = false,
    this.isNameEdited = false,
    this.isUserModified = false,
    this.markerIds = const [],
  });

  /// An empty [placeName] means the stop has not been named yet.
  final String id, tripId, placeName;
  final double latitude, longitude;
  final DateTime arrivalTime;
  final DateTime? departureTime;
  final String? memo;
  final List<String> photoIds;
  final StopSource source;

  /// The user removed this stop; it is kept so re-analysis cannot resurrect it.
  final bool isExcluded;
  final bool isNameEdited;

  /// Any user edit (rename, memo, merge). Protects the stop from re-analysis.
  final bool isUserModified;

  /// ManualMarkers that were linked to this stop.
  final List<String> markerIds;

  Duration? get dwell => departureTime?.difference(arrivalTime);

  Stop copyWith({
    String? placeName,
    double? latitude,
    double? longitude,
    DateTime? arrivalTime,
    DateTime? departureTime,
    String? memo,
    StopSource? source,
    bool? isExcluded,
    bool? isNameEdited,
    bool? isUserModified,
    List<String>? markerIds,
  }) => Stop(
    id: id,
    tripId: tripId,
    placeName: placeName ?? this.placeName,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    arrivalTime: arrivalTime ?? this.arrivalTime,
    departureTime: departureTime ?? this.departureTime,
    memo: memo ?? this.memo,
    photoIds: photoIds,
    source: source ?? this.source,
    isExcluded: isExcluded ?? this.isExcluded,
    isNameEdited: isNameEdited ?? this.isNameEdited,
    isUserModified: isUserModified ?? this.isUserModified,
    markerIds: markerIds ?? this.markerIds,
  );
}
