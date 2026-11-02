import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/domain/entities/gps_point.dart';
import 'package:route_story/features/trips/domain/entities/photo_metadata.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip_photo.dart';
import 'package:route_story/features/trips/domain/services/photo_matcher.dart';

import 'support/gps_scenario.dart';

const matcher = PhotoMatcher();

/// 09:00-09:20 driving, 09:20-10:00 stop A, 10:00-10:20 driving, then a
/// 20 min silence, 10:40-10:50 driving, 10:50-11:10 stop B.
class World {
  World() {
    final s = GpsScenario(start: DateTime(2026, 9, 1, 9))..move(20.min, speed: 10);
    aLat = s.lat;
    aLng = s.lng;
    s.stay(40.min).move(20.min, speed: 10).silence(20.min, speed: 10);
    s.move(10.min, speed: 10);
    bLat = s.lat;
    bLng = s.lng;
    s.stay(20.min);
    points = s.points;
    end = s.now;
    stopA = Stop(
      id: 'A',
      placeName: 'A',
      latitude: aLat,
      longitude: aLng,
      arrivalTime: DateTime(2026, 9, 1, 9, 20),
      departureTime: DateTime(2026, 9, 1, 10, 0),
    );
    stopB = Stop(
      id: 'B',
      placeName: 'B',
      latitude: bLat,
      longitude: bLng,
      arrivalTime: DateTime(2026, 9, 1, 10, 50),
      departureTime: DateTime(2026, 9, 1, 11, 10),
    );
  }
  late double aLat, aLng, bLat, bLng;
  late List<GpsPoint> points;
  late DateTime end;
  late Stop stopA, stopB;
  final start = DateTime(2026, 9, 1, 9);

  List<PhotoMatch> run(List<PhotoMetadata> photos, {List<Stop>? stops}) =>
      matcher.match(
        tripStart: start,
        tripEnd: end,
        stops: stops ?? [stopA, stopB],
        gpsPoints: points,
        photos: photos,
      );

  GpsPoint pointAt(DateTime t) => points.reduce(
    (a, b) =>
        a.timestamp.difference(t).abs() <= b.timestamp.difference(t).abs()
        ? a
        : b,
  );
}

PhotoMetadata photo(
  String id,
  DateTime? at, {
  double? lat,
  double? lng,
}) => PhotoMetadata(assetId: id, takenAt: at, latitude: lat, longitude: lng);

void main() {
  late World w;
  setUp(() => w = World());

  test('1. photo with GPS taken during a stop -> that stop (time+location)', () {
    final r = w.run([
      photo('p', DateTime(2026, 9, 1, 9, 40), lat: w.aLat + 0.0005, lng: w.aLng),
    ]).single;
    expect(r.method, PhotoMatchMethod.timeAndLocation);
    expect(r.stopId, 'A');
    expect(r.confidence, greaterThan(0.7));
  });

  test('2. photo without GPS during a stop -> time match', () {
    final r = w.run([photo('p', DateTime(2026, 9, 1, 9, 40))]).single;
    expect(r.method, PhotoMatchMethod.time);
    expect(r.stopId, 'A');
  });

  test('3. photo taken while moving -> route photo, no stop', () {
    final at = DateTime(2026, 9, 1, 9, 10);
    final p = w.pointAt(at);
    final withGps = w.run([
      photo('p', at, lat: p.latitude, lng: p.longitude),
    ]).single;
    expect(withGps.method, PhotoMatchMethod.route);
    expect(withGps.stopId, isNull);
    final noGps = w.run([photo('q', at)]).single;
    expect(noGps.method, PhotoMatchMethod.route);
    expect(noGps.confidence, lessThan(withGps.confidence));
  });

  test('4. photos outside the trip time are not matched at all', () {
    final r = w.run([
      photo('early', DateTime(2026, 9, 1, 7, 0)),
      photo('late', DateTime(2026, 9, 1, 15, 0)),
      photo('inside', DateTime(2026, 9, 1, 9, 40)),
    ]);
    expect(r.map((m) => m.photo.assetId), ['inside']);
  });

  test('5. photo location far from the stop it was taken at -> held back', () {
    final r = w.run([
      photo('p', DateTime(2026, 9, 1, 9, 40), lat: w.aLat + 0.02, lng: w.aLng),
    ]).single;
    expect(r.method, PhotoMatchMethod.none);
    expect(r.stopId, isNull);
  });

  test('6. missing capture time -> unclassified', () {
    final r = w.run([photo('p', null)]).single;
    expect(r.method, PhotoMatchMethod.none);
    expect(r.stopId, isNull);
  });

  test('7. long GPS gap -> no guessed position, stays unclassified', () {
    // 10:30-10:50 there are no fixes (20 min), and no stop is active.
    final r = w.run([photo('p', DateTime(2026, 9, 1, 10, 40))]).single;
    expect(r.method, PhotoMatchMethod.none);
  });

  test('a photo on the route that contradicts its own GPS is held back', () {
    final at = DateTime(2026, 9, 1, 9, 10);
    final r = w.run([photo('p', at, lat: w.aLat + 0.05, lng: w.aLng)]).single;
    expect(r.method, PhotoMatchMethod.none);
  });

  test('no stop is chosen just because it is the nearest', () {
    // 09:10 is 10 min before stop A; GPS right at A must not force a match.
    final r = w.run([
      photo('p', DateTime(2026, 9, 1, 9, 10), lat: w.aLat, lng: w.aLng),
    ]).single;
    expect(r.stopId, isNull);
  });

  test('time overlapping two stops without GPS is not guessed', () {
    final a = w.stopA;
    final b = Stop(
      id: 'B2',
      placeName: 'B2',
      latitude: w.bLat,
      longitude: w.bLng,
      arrivalTime: a.departureTime!.add(const Duration(minutes: 2)),
      departureTime: a.departureTime!.add(const Duration(minutes: 20)),
    );
    final r = w
        .run([
          photo('p', a.departureTime!.add(const Duration(minutes: 1))),
        ], stops: [a, b])
        .single;
    expect(r.method, PhotoMatchMethod.none);
    // With GPS the right one is picked.
    final withGps = w
        .run([
          photo(
            'q',
            a.departureTime!.add(const Duration(minutes: 1)),
            lat: w.aLat,
            lng: w.aLng,
          ),
        ], stops: [a, b])
        .single;
    expect(withGps.stopId, 'A');
  });

  test('excluded stops attract no photos', () {
    final r = w.run(
      [photo('p', DateTime(2026, 9, 1, 9, 40))],
      stops: [w.stopA.copyWith(isExcluded: true), w.stopB],
    ).single;
    expect(r.stopId, isNull);
  });

  test('duplicate photos are matched once', () {
    final p = photo('p', DateTime(2026, 9, 1, 9, 40));
    expect(w.run([p, p, p]), hasLength(1));
  });

  test('12. several hundred photos match quickly', () {
    final photos = [
      for (var i = 0; i < 600; i++)
        photo(
          'p$i',
          DateTime(2026, 9, 1, 9).add(Duration(seconds: i * 6)),
          lat: i.isEven ? w.aLat : null,
          lng: i.isEven ? w.aLng : null,
        ),
    ];
    final watch = Stopwatch()..start();
    final r = w.run(photos);
    watch.stop();
    expect(r, hasLength(600));
    expect(watch.elapsedMilliseconds, lessThan(1000));
    expect(r.where((m) => m.stopId == 'A'), isNotEmpty);
  });
}
