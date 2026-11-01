import 'dart:math';

import 'package:route_story/features/trips/domain/entities/gps_point.dart';

/// Builds synthetic GPS tracks segment by segment.
class GpsScenario {
  GpsScenario({DateTime? start, double lat = 37.50, double lng = 127.00, int seed = 7})
    : _clock = start ?? DateTime(2026, 9, 1, 9),
      _lat = lat,
      _lng = lng,
      _random = Random(seed);

  static const metersPerDegreeLat = 111320.0;
  static double metersPerDegreeLng(double lat) =>
      111320.0 * cos(lat * pi / 180);

  final Random _random;
  DateTime _clock;
  final double _lat;
  double _lng;
  final points = <GpsPoint>[];

  DateTime get now => _clock;
  double get lat => _lat;
  double get lng => _lng;

  GpsPoint _make(double lat, double lng, DateTime time, double speed) =>
      GpsPoint(
        latitude: lat,
        longitude: lng,
        altitude: 20,
        timestamp: time,
        accuracy: 8,
        speed: speed,
      );

  /// Straight movement heading east at [speed] m/s with a fix every [every].
  GpsScenario move(
    Duration duration, {
    required double speed,
    Duration every = const Duration(seconds: 5),
    bool reportSpeed = true,
  }) {
    final steps = duration.inSeconds ~/ every.inSeconds;
    for (var i = 0; i < steps; i++) {
      _clock = _clock.add(every);
      _lng += speed * every.inSeconds / metersPerDegreeLng(_lat);
      points.add(_make(_lat, _lng, _clock, reportSpeed ? speed : -1));
    }
    return this;
  }

  /// Standing still with GPS jitter of up to [jitter] metres.
  GpsScenario stay(
    Duration duration, {
    Duration every = const Duration(seconds: 30),
    double jitter = 15,
  }) {
    final steps = duration.inSeconds ~/ every.inSeconds;
    for (var i = 0; i < steps; i++) {
      _clock = _clock.add(every);
      final dx = (_random.nextDouble() * 2 - 1) * jitter;
      final dy = (_random.nextDouble() * 2 - 1) * jitter;
      points.add(
        _make(
          _lat + dy / metersPerDegreeLat,
          _lng + dx / metersPerDegreeLng(_lat),
          _clock,
          0.2,
        ),
      );
    }
    return this;
  }

  /// A single fix [north]/[east] metres away from the current position.
  GpsScenario spike(double north, double east) {
    _clock = _clock.add(const Duration(seconds: 30));
    points.add(
      _make(
        _lat + north / metersPerDegreeLat,
        _lng + east / metersPerDegreeLng(_lat),
        _clock,
        0.2,
      ),
    );
    return this;
  }

  /// No fixes for [duration]; the traveller keeps moving at [speed] m/s.
  GpsScenario silence(Duration duration, {double speed = 0}) {
    _clock = _clock.add(duration);
    _lng += speed * duration.inSeconds / metersPerDegreeLng(_lat);
    return this;
  }
}

double metersBetween(double lat1, double lng1, double lat2, double lng2) {
  final dy = (lat2 - lat1) * GpsScenario.metersPerDegreeLat;
  final dx = (lng2 - lng1) * GpsScenario.metersPerDegreeLng(lat1);
  return sqrt(dx * dx + dy * dy);
}

extension MinutesInt on int {
  Duration get min => Duration(minutes: this);
}

