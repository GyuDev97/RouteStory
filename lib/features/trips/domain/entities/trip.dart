import 'gps_point.dart';
import 'stop.dart';
import 'trip_photo.dart';

enum StopAnalysisStatus { pending, completed, failed }

enum PhotoMatchStatus {
  pending,
  completed,

  /// Done, but the user only shared some photos with the app.
  limited,

  /// No photo permission; matching could not run.
  noAccess,
  failed,
}

class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    required this.totalDistance,
    this.gpsPoints = const [],
    this.stops = const [],
    this.excludedStops = const [],
    this.photos = const [],
    this.privacySetting = 'private',
    this.shareSetting = 'off',
    this.status = 'completed',
    this.stopAnalysisStatus = StopAnalysisStatus.pending,
    this.photoMatchStatus = PhotoMatchStatus.pending,
    this.coverPhotoId,
    this.isDemo = false,
  });
  final String id, title, privacySetting, shareSetting, status;
  final DateTime startTime;
  final DateTime? endTime;

  /// Metres. Convert with `formatKilometers` only when displaying.
  final double totalDistance;
  final List<GpsPoint> gpsPoints;

  /// Visible stops, in time order.
  final List<Stop> stops;

  /// Stops the user removed; kept for restore and re-analysis protection.
  final List<Stop> excludedStops;

  /// All photos including excluded ones; see [activePhotos].
  final List<TripPhoto> photos;
  final StopAnalysisStatus stopAnalysisStatus;
  final PhotoMatchStatus photoMatchStatus;

  /// The photo the user chose as the trip's cover. Null means "automatic".
  final String? coverPhotoId;

  /// Sample trips shown before any real trip exists. Never analyzed or edited.
  final bool isDemo;

  List<TripPhoto> get activePhotos =>
      photos.where((p) => !p.isExcluded).toList(growable: false);

  Trip copyWith({
    String? title,
    String? coverPhotoId,
    bool clearCover = false,
    List<GpsPoint>? gpsPoints,
    List<Stop>? stops,
    List<Stop>? excludedStops,
    List<TripPhoto>? photos,
    StopAnalysisStatus? stopAnalysisStatus,
    PhotoMatchStatus? photoMatchStatus,
  }) => Trip(
    id: id,
    title: title ?? this.title,
    startTime: startTime,
    endTime: endTime,
    totalDistance: totalDistance,
    gpsPoints: gpsPoints ?? this.gpsPoints,
    stops: stops ?? this.stops,
    excludedStops: excludedStops ?? this.excludedStops,
    photos: photos ?? this.photos,
    privacySetting: privacySetting,
    shareSetting: shareSetting,
    status: status,
    stopAnalysisStatus: stopAnalysisStatus ?? this.stopAnalysisStatus,
    photoMatchStatus: photoMatchStatus ?? this.photoMatchStatus,
    coverPhotoId: clearCover ? null : coverPhotoId ?? this.coverPhotoId,
    isDemo: isDemo,
  );
}
