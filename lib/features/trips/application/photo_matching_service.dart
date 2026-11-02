import '../../../core/services/photo_library_service.dart';
import '../domain/entities/photo_metadata.dart';
import '../domain/entities/trip.dart';
import '../domain/entities/trip_photo.dart';
import '../domain/repositories/trip_repository.dart';
import '../domain/services/photo_matcher.dart';
import '../domain/services/photo_matching_config.dart';
import '../domain/services/photo_reconciler.dart';
import 'trip_task_queue.dart';

enum PhotoMatchOutcome { completed, limited, noAccess, failed, skipped }

/// Finds a trip's photos, matches them to stops and stores the result.
///
/// Runs after stop analysis as its own step. It only writes photo rows and the
/// photo status; GPS data, stops and photo files are never modified, and any
/// failure leaves the trip as it was so it can simply be run again.
class PhotoMatchingService {
  PhotoMatchingService(
    this._repository,
    this._library, {
    PhotoMatchingConfig config = const PhotoMatchingConfig(),
    TripTaskQueue? queue,
    Future<Object?> Function(String tripId)? ensureStops,
  }) : _matcher = PhotoMatcher(config),
       _config = config,
       _queue = queue ?? TripTaskQueue(),
       _ensureStops = ensureStops;
  final TripRepository _repository;
  final PhotoLibraryService _library;
  final PhotoMatchingConfig _config;
  final PhotoMatcher _matcher;
  final TripTaskQueue _queue;
  final Future<Object?> Function(String tripId)? _ensureStops;
  final _running = <String, Future<PhotoMatchOutcome>>{};

  /// Searches the library for the trip's photos. [requestPermission] shows the
  /// system dialog when access is missing; leave it false for background runs.
  Future<PhotoMatchOutcome> match(
    String tripId, {
    bool requestPermission = false,
  }) => _running[tripId] ??= _matchGuarded(tripId, requestPermission)
      .whenComplete(() {
        _running.remove(tripId);
      });

  Future<PhotoMatchOutcome> _matchGuarded(
    String tripId,
    bool requestPermission,
  ) async {
    await _ensureStopsAnalyzed(tripId);
    return _queue.run(tripId, () => _match(tripId, requestPermission));
  }

  /// Runs stop analysis first if it has not completed yet. Done before entering
  /// the queue because stop analysis uses the same queue.
  Future<void> _ensureStopsAnalyzed(String tripId) async {
    try {
      final trip = await _repository.getTrip(tripId);
      if (trip != null && trip.stopAnalysisStatus != StopAnalysisStatus.completed) {
        await _ensureStops?.call(tripId);
      }
    } catch (_) {}
  }

  /// Runs matching for real trips whose photos were never matched.
  Future<bool> matchPending(Iterable<Trip> trips) async {
    var changed = false;
    for (final trip in trips) {
      if (trip.isDemo ||
          trip.status != 'completed' ||
          trip.photoMatchStatus != PhotoMatchStatus.pending) {
        continue;
      }
      await match(trip.id);
      changed = true;
    }
    return changed;
  }

  Future<PhotoMatchOutcome> _match(String tripId, bool requestPermission) async {
    try {
      final trip = await _repository.getTrip(tripId);
      if (trip == null || trip.status != 'completed') {
        return PhotoMatchOutcome.skipped;
      }
      final access = requestPermission
          ? await _library.requestAccess()
          : await _library.currentAccess();
      if (access == PhotoAccess.denied) {
        await _repository.setPhotoMatchStatus(tripId, PhotoMatchStatus.noAccess);
        return PhotoMatchOutcome.noAccess;
      }
      final end = trip.endTime ?? DateTime.now();
      final found = await _library.findPhotos(
        trip.startTime.subtract(_config.tripTimeMargin),
        end.add(_config.tripTimeMargin),
      );
      final limited = access == PhotoAccess.limited;
      await _store(
        trip,
        found,
        limited ? PhotoMatchStatus.limited : PhotoMatchStatus.completed,
      );
      return limited ? PhotoMatchOutcome.limited : PhotoMatchOutcome.completed;
    } catch (_) {
      try {
        await _repository.setPhotoMatchStatus(tripId, PhotoMatchStatus.failed);
      } catch (_) {}
      return PhotoMatchOutcome.failed;
    }
  }

  /// Fallback: the user picks photos with the system picker (no permission).
  /// They are matched the same way and merged into the stored photos.
  Future<PhotoMatchOutcome> addPickedPhotos(String tripId) async {
    final picked = await _library.pickPhotos();
    if (picked.isEmpty) return PhotoMatchOutcome.skipped;
    await _ensureStopsAnalyzed(tripId);
    return _queue.run(tripId, () async {
      try {
        final trip = await _repository.getTrip(tripId);
        if (trip == null) return PhotoMatchOutcome.skipped;
        await _store(trip, picked, null);
        return PhotoMatchOutcome.completed;
      } catch (_) {
        return PhotoMatchOutcome.failed;
      }
    });
  }

  Future<void> _store(
    Trip trip,
    List<PhotoMetadata> photos,
    PhotoMatchStatus? status,
  ) async {
    final matches = _matcher.match(
      tripStart: trip.startTime,
      tripEnd: trip.endTime ?? DateTime.now(),
      stops: trip.stops,
      gpsPoints: trip.gpsPoints,
      photos: photos,
    );
    final upserts = PhotoReconciler.reconcile(
      tripId: trip.id,
      existing: await _repository.getPhotos(trip.id),
      matches: matches,
    );
    await _repository.savePhotos(trip.id, upserts: upserts, status: status);
  }

  Future<void> openSettings() => _library.openSettings();
  Future<void> manageLimitedSelection() => _library.manageLimitedSelection();

  // ---- user edits ---------------------------------------------------------

  Future<void> moveToStop(String tripId, String photoId, String stopId) =>
      _editPhoto(tripId, photoId, (p) => PhotoEditing.moveToStop(p, stopId));

  Future<void> detach(String tripId, String photoId) =>
      _editPhoto(tripId, photoId, PhotoEditing.detach);

  Future<void> exclude(String tripId, String photoId) =>
      _editPhoto(tripId, photoId, PhotoEditing.exclude);

  Future<void> restore(String tripId, String photoId) =>
      _editPhoto(tripId, photoId, PhotoEditing.restore);

  Future<void> setCover(String tripId, String stopId, String photoId) =>
      _queue.run(tripId, () async {
        final stops = await _repository.getAllStops(tripId);
        final stop = stops.where((s) => s.id == stopId).firstOrNull;
        if (stop == null) return;
        await _repository.saveStopChanges(
          tripId,
          upserts: [stop.copyWith(coverPhotoId: photoId)],
        );
      });

  Future<void> _editPhoto(
    String tripId,
    String photoId,
    TripPhoto Function(TripPhoto) edit,
  ) => _queue.run(tripId, () async {
    final photo = (await _repository.getPhotos(
      tripId,
    )).where((p) => p.id == photoId).firstOrNull;
    if (photo == null) return;
    await _repository.savePhotos(tripId, upserts: [edit(photo)]);
  });
}
