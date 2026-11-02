import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/repositories/trip_repository.dart';

import 'gps_scenario.dart';

const tripId = 'trip-1';

/// Cafe (40 min) -> 20 min drive -> sight (20 min), starting 2026-09-01 09:00.
class Seeded {
  late DateTime cafeArrival, cafeDeparture, sightArrival, sightDeparture;
  late double cafeLat, cafeLng, sightLat, sightLng;
  late int pointCount;
}

Future<Seeded> seed(TripRepository repo, {bool withPoints = true}) async {
  final s = GpsScenario()..move(20.min, speed: 10);
  final seeded = Seeded()
    ..cafeLat = s.lat
    ..cafeLng = s.lng
    ..cafeArrival = s.now;
  s.stay(40.min);
  seeded.cafeDeparture = s.now;
  s.move(20.min, speed: 10);
  seeded
    ..sightLat = s.lat
    ..sightLng = s.lng
    ..sightArrival = s.now;
  s.stay(20.min);
  seeded.sightDeparture = s.now;
  s.move(5.min, speed: 10);
  await repo.saveTrip(
    Trip(
      id: tripId,
      title: '오늘의 여정',
      startTime: DateTime(2026, 9, 1, 9),
      endTime: s.now,
      totalDistance: 1000,
    ),
  );
  if (withPoints) {
    for (final p in s.points) {
      await repo.saveGpsPoint(tripId, p);
    }
  }
  seeded.pointCount = s.points.length;
  return seeded;
}

