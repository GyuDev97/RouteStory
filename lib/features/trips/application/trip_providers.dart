import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/location_tracking_service.dart';
import '../../../core/services/photo_library_service.dart';
import '../data/repositories/local_trip_repository.dart';
import '../data/services/geolocator_location_service.dart';
import '../data/services/photo_manager_library_service.dart';
import '../domain/entities/trip.dart';
import '../domain/repositories/trip_repository.dart';
import 'photo_matching_service.dart';
import 'stop_service.dart';
import 'trip_service.dart';
import 'trip_task_queue.dart';

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => LocalTripRepository(),
);
final locationTrackingServiceProvider = Provider<LocationTrackingService>(
  (ref) => GeolocatorLocationTrackingService(),
);
final photoLibraryServiceProvider = Provider<PhotoLibraryService>(
  (ref) => PhotoManagerLibraryService(),
);
final tripTaskQueueProvider = Provider<TripTaskQueue>((ref) => TripTaskQueue());
final stopServiceProvider = Provider<StopService>(
  (ref) => StopService(
    ref.watch(tripRepositoryProvider),
    queue: ref.watch(tripTaskQueueProvider),
  ),
);
final photoMatchingServiceProvider = Provider<PhotoMatchingService>(
  (ref) => PhotoMatchingService(
    ref.watch(tripRepositoryProvider),
    ref.watch(photoLibraryServiceProvider),
    queue: ref.watch(tripTaskQueueProvider),
    ensureStops: ref.watch(stopServiceProvider).analyze,
  ),
);
final tripServiceProvider = Provider<TripService>(
  (ref) => TripService(
    ref.watch(tripRepositoryProvider),
    queue: ref.watch(tripTaskQueueProvider),
  ),
);
final recentTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final repository = ref.watch(tripRepositoryProvider);
  var trips = await repository.getRecentTrips();
  // Steps that never finished (app closed, earlier failure) run now, one
  // after the other; the originals are never touched. Photo matching never
  // asks for permission here.
  final analyzed = await ref.watch(stopServiceProvider).analyzePending(trips);
  if (analyzed) trips = await repository.getRecentTrips();
  final matched = await ref
      .watch(photoMatchingServiceProvider)
      .matchPending(trips);
  return matched ? repository.getRecentTrips() : trips;
});

/// Live view of one real trip (stops and photos change after analysis and edits).
final tripDetailProvider = FutureProvider.family<Trip?, String>(
  (ref, tripId) => ref.watch(tripRepositoryProvider).getTrip(tripId),
);

/// Preview image of a library photo at the requested size; null when it is gone or unreadable.
final photoThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, int)>((ref, key) async {
      try {
        return await ref
            .watch(photoLibraryServiceProvider)
            .thumbnail(key.$1, size: key.$2);
      } catch (_) {
        return null;
      }
    });
