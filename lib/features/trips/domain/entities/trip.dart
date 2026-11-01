import 'gps_point.dart';
import 'stop.dart';
import 'trip_photo.dart';

enum StopAnalysisStatus { pending, completed, failed }

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
    this.isDemo = false,
  });
  final String id, title, privacySetting, shareSetting, status;
  final DateTime startTime;
  final DateTime? endTime;
  final double totalDistance;
  final List<GpsPoint> gpsPoints;

  /// Visible stops, in time order.
  final List<Stop> stops;

  /// Stops the user removed; kept for restore and re-analysis protection.
  final List<Stop> excludedStops;
  final List<TripPhoto> photos;
  final StopAnalysisStatus stopAnalysisStatus;

  /// Sample trips shown before any real trip exists. Never analyzed or edited.
  final bool isDemo;
}
