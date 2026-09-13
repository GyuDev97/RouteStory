import 'dart:math';
import '../entities/gps_point.dart';

abstract final class DistanceCalculator {
  static const maximumAccuracyMeters = 50.0;
  static const maximumSpeedMetersPerSecond = 75.0;
  static double metersBetween(GpsPoint a, GpsPoint b) {
    const earthRadius = 6371000.0;
    final lat = _radians(b.latitude - a.latitude);
    final lng = _radians(b.longitude - a.longitude);
    final h =
        sin(lat / 2) * sin(lat / 2) +
        cos(_radians(a.latitude)) *
            cos(_radians(b.latitude)) *
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
