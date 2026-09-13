class GpsPoint {
  const GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.timestamp,
    required this.accuracy,
    this.speed,
    this.heading,
  });
  final double latitude, longitude, altitude, accuracy;
  final double? speed, heading;
  final DateTime timestamp;
}
