import 'dart:math';
import '../entities/gps_point.dart';

abstract final class DistanceCalculator {
  static const maximumAccuracyMeters = 50.0;
  static const maximumSpeedMetersPerSecond = 75.0;
  static double metersBetween(GpsPoint a, GpsPoint b) => metersBetweenCoordinates(
    a.latitude,
    a.longitude,
    b.latitude,
    b.longitude,
  );

  static double metersBetweenCoordinates(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadius = 6371000.0;
    final lat = _radians(latitudeB - latitudeA);
    final lng = _radians(longitudeB - longitudeA);
    final h =
        sin(lat / 2) * sin(lat / 2) +
        cos(_radians(latitudeA)) *
            cos(_radians(latitudeB)) *
            sin(lng / 2) *
            sin(lng / 2);
    return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h));
  }

  static bool isPlausible(GpsPoint? previous, GpsPoint next) {
    if (next.accuracy > maximumAccuracyMeters) return false;
    if (previous == null) return true;
    final seconds =
        next.timestamp.difference(previous.timestamp).inMilliseconds / 1000;
    if (seconds <= 0) return false;
    return metersBetween(previous, next) / seconds <=
        maximumSpeedMetersPerSecond;
  }

  static double _radians(double degree) => degree * pi / 180;
}
