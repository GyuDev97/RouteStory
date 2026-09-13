import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/location_tracking_service.dart';
import '../data/repositories/local_trip_repository.dart';
import '../data/services/geolocator_location_service.dart';
import '../domain/entities/trip.dart';
import '../domain/repositories/trip_repository.dart';

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => LocalTripRepository(),
);
final locationTrackingServiceProvider = Provider<LocationTrackingService>(
  (ref) => GeolocatorLocationTrackingService(),
);
final recentTripsProvider = FutureProvider<List<Trip>>(
  (ref) => ref.watch(tripRepositoryProvider).getRecentTrips(),
);
