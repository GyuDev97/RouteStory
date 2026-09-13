import 'gps_point.dart';
import 'stop.dart';
import 'trip_photo.dart';

class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.startTime,
    this.endTime,
    required this.totalDistance,
    this.gpsPoints = const [],
    this.stops = const [],
    this.photos = const [],
    this.privacySetting = 'private',
    this.shareSetting = 'off',
    this.status = 'completed',
  });
  final String id, title, privacySetting, shareSetting, status;
  final DateTime startTime;
  final DateTime? endTime;
  final double totalDistance;
  final List<GpsPoint> gpsPoints;
  final List<Stop> stops;
  final List<TripPhoto> photos;
}
