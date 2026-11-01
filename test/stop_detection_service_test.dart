import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/domain/entities/gps_point.dart';
import 'package:route_story/features/trips/domain/services/stop_detection_service.dart';

import 'support/gps_scenario.dart';

const detector = StopDetectionService();

Matcher near(DateTime expected, {int seconds = 60}) => predicate<DateTime>(
  (actual) => actual.difference(expected).inSeconds.abs() <= seconds,
  'within $seconds s of $expected',
);

void main() {
  group('stop detection scenarios', () {
    test('30 min of driving then a 40 min cafe stop -> 1 stop', () {
      final s = GpsScenario()..move(30.min, speed: 10);
      final cafeLat = s.lat, cafeLng = s.lng;
      final arrival = s.now;
      s.stay(40.min);
      final departure = s.now;
      s.move(10.min, speed: 10);

      final stops = detector.detect(s.points);

      expect(stops, hasLength(1));
      expect(stops.single.arrivalTime, near(arrival));
      expect(stops.single.departureTime, near(departure));
      expect(
        metersBetween(cafeLat, cafeLng, stops.single.latitude, stops.single.longitude),
        lessThan(30),
      );
      expect(stops.single.dwell.inMinutes, inInclusiveRange(38, 41));
    });

    test('20 min at a sight -> 1 stop', () {
      final s = GpsScenario()..move(15.min, speed: 12);
      final arrival = s.now;
      s.stay(20.min, jitter: 20);
      final departure = s.now;
      s.move(15.min, speed: 12);

      final stops = detector.detect(s.points);

      expect(stops, hasLength(1));
      expect(stops.single.arrivalTime, near(arrival));
      expect(stops.single.departureTime, near(departure));
    });

    test('2 min at a traffic light -> no stop', () {
      final s = GpsScenario()
        ..move(10.min, speed: 10)
        ..stay(2.min, every: const Duration(seconds: 5))
        ..move(10.min, speed: 10);
      expect(detector.detect(s.points), isEmpty);
    });

    test('5 min GPS silence while travelling -> no fake stop', () {
      final s = GpsScenario()
        ..move(10.min, speed: 10)
        ..silence(5.min, speed: 10)
        ..move(10.min, speed: 10);
      expect(detector.detect(s.points), isEmpty);
    });

    test('silence is not counted as dwell on its own', () {
      // 3 min of fixes, 5 min nothing, 3 min of fixes at the same place:
      // only 6 min were observed, so it must not become a 11 min stop.
      final s = GpsScenario()
        ..move(5.min, speed: 10)
        ..stay(2.min)
        ..silence(5.min)
        ..stay(2.min);
      expect(detector.detect(s.points), isEmpty);
    });

    test('a 200 m GPS jump during a stop does not split it', () {
      final s = GpsScenario()..move(10.min, speed: 10);
      final arrival = s.now;
      s
        ..stay(15.min)
        ..spike(200, 0)
        ..stay(15.min);
      final departure = s.now;
      s.move(10.min, speed: 10);

      final stops = detector.detect(s.points);

      expect(stops, hasLength(1));
      expect(stops.single.arrivalTime, near(arrival));
      expect(stops.single.departureTime, near(departure));
    });

    test('a burst of drift (3 fixes 200 m away) does not split a stop', () {
      final s = GpsScenario()
        ..stay(15.min)
        ..spike(200, 0)
        ..spike(210, 10)
        ..spike(205, 5)
        ..stay(15.min);
      expect(detector.detect(s.points), hasLength(1));
    });

    for (final speed in [0.3, 0.1]) {
      test('30 min of slow movement at $speed m/s is not one stop', () {
        final s = GpsScenario()
          ..move(30.min, speed: speed, every: const Duration(seconds: 20));
        expect(detector.detect(s.points), isEmpty);
      });
    }

    test('slow traffic is rejected using reported speed', () {
      // Stop-and-go jam: positions stay inside 100 m for 20 min, but the
      // device reports driving speed for most fixes.
      final s = GpsScenario()..stay(20.min, every: const Duration(seconds: 15));
      final jam = [
        for (final entry in s.points.indexed)
          GpsPoint(
            latitude: entry.$2.latitude,
            longitude: entry.$2.longitude,
            altitude: entry.$2.altitude,
            timestamp: entry.$2.timestamp,
            accuracy: entry.$2.accuracy,
            speed: entry.$1.isEven || entry.$1 % 3 == 0 ? 3.0 : 0.2,
          ),
      ];
      expect(detector.detect(jam), isEmpty);
      // Same positions with no moving speed are a real stop.
      expect(detector.detect(s.points), hasLength(1));
    });

    test('a real stop at the end of a slow crawl is still found', () {
      final s = GpsScenario()
        ..move(15.min, speed: 0.3, every: const Duration(seconds: 20));
      final arrival = s.now;
      s.stay(25.min);
      final stops = detector.detect(s.points);
      expect(stops, hasLength(1));
      expect(stops.single.arrivalTime.isAfter(arrival.subtract(5.min)), isTrue);
    });

    test('revisiting a place later gives two separate stops', () {
      final s = GpsScenario()..move(10.min, speed: 10);
      final lat = s.lat, lng = s.lng;
      final firstArrival = s.now;
      s
        ..stay(20.min)
        ..move(40.min, speed: 10)
        ..move(40.min, speed: -10);
      // back at the same spot
      final secondArrival = s.now;
      s.stay(20.min);

      final stops = detector.detect(s.points);

      expect(stops, hasLength(2));
      expect(stops[0].arrivalTime, near(firstArrival));
      expect(stops[1].arrivalTime, near(secondArrival, seconds: 120));
      expect(metersBetween(lat, lng, stops[1].latitude, stops[1].longitude), lessThan(40));
    });

    test('0, 1 and 2 points never throw and give no stop', () {
      final s = GpsScenario()..stay(10.min, every: const Duration(minutes: 5));
      for (var n = 0; n <= 2; n++) {
        expect(detector.detect(s.points.take(n).toList()), isEmpty);
      }
    });

    test('unsorted input gives the same result as sorted input', () {
      final s = GpsScenario()
        ..move(10.min, speed: 10)
        ..stay(20.min)
        ..move(10.min, speed: 10);
      final expected = detector.detect(s.points);
      final shuffled = s.points.reversed.toList();
      final actual = detector.detect(shuffled);
      expect(actual, hasLength(1));
      expect(actual.single.arrivalTime, expected.single.arrivalTime);
      expect(actual.single.departureTime, expected.single.departureTime);
    });

    test('invalid, inaccurate and duplicate fixes are ignored', () {
      final s = GpsScenario()..stay(20.min);
      final noisy = [
        ...s.points,
        GpsPoint(latitude: double.nan, longitude: 127, altitude: 0, timestamp: s.now, accuracy: 5),
        GpsPoint(latitude: 95, longitude: 127, altitude: 0, timestamp: s.now, accuracy: 5),
        GpsPoint(latitude: 0, longitude: 0, altitude: 0, timestamp: s.now, accuracy: 5),
        // Far away but with a poor accuracy value: must not break the stop.
        GpsPoint(latitude: 37.6, longitude: 127.1, altitude: 0, timestamp: s.points[10].timestamp.add(const Duration(seconds: 1)), accuracy: 400),
        s.points[5],
        s.points[5],
      ];
      final stops = detector.detect(noisy);
      expect(stops, hasLength(1));
      expect(stops.single.dwell.inMinutes, greaterThanOrEqualTo(18));
    });

    test('long trips (30k points) are processed quickly', () {
      final s = GpsScenario();
      for (var day = 0; day < 3; day++) {
        for (var leg = 0; leg < 6; leg++) {
          s
            ..move(60.min, speed: 15, every: const Duration(seconds: 2))
            ..stay(30.min, every: const Duration(seconds: 20))
            ..move(30.min, speed: -15, every: const Duration(seconds: 2));
        }
        s.silence((8 * 60).min);
      }
      expect(s.points.length, greaterThan(30000));
      final watch = Stopwatch()..start();
      final stops = detector.detect(s.points);
      watch.stop();
      expect(stops.length, 18);
      expect(watch.elapsedMilliseconds, lessThan(5000));
    });
  });
}

