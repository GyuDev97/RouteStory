import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/location_tracking_service.dart';
import '../data/repositories/local_trip_repository.dart';
import '../data/services/geolocator_location_service.dart';
import '../domain/entities/trip.dart';
import '../domain/repositories/trip_repository.dart';
import 'stop_service.dart';

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => LocalTripRepository(),
);
final locationTrackingServiceProvider = Provider<LocationTrackingService>(
  (ref) => GeolocatorLocationTrackingService(),
);
final stopServiceProvider = Provider<StopService>(
  (ref) => StopService(ref.watch(tripRepositoryProvider)),
);
final recentTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final repository = ref.watch(tripRepositoryProvider);
  final trips = await repository.getRecentTrips();
  // Trips whose analysis never finished (app closed, earlier failure) are
  // analyzed now; the originals are never touched.
  if (await ref.watch(stopServiceProvider).analyzePending(trips)) {
    return repository.getRecentTrips();
  }
  return trips;
});

/// Live view of one real trip (stops change after analysis and edits).
final tripDetailProvider = FutureProvider.family<Trip?, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).getTrip(tripId),
);
