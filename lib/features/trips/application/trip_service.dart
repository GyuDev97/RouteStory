import '../domain/repositories/trip_repository.dart';
import 'trip_task_queue.dart';

/// User edits of the trip itself (title, cover photo). Stored separately from
/// analysis results, so re-analysis can never overwrite them.
class TripService {
  TripService(this._repository, {TripTaskQueue? queue})
    : _queue = queue ?? TripTaskQueue();
  final TripRepository _repository;
  final TripTaskQueue _queue;

  /// Blank titles are ignored.
  Future<void> rename(String tripId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return Future.value();
    return _queue.run(
      tripId,
      () => _repository.updateTripDetails(tripId, title: trimmed),
    );
  }

  Future<void> setCoverPhoto(String tripId, String photoId) => _queue.run(
    tripId,
    () => _repository.updateTripDetails(tripId, coverPhotoId: photoId),
  );

  /// Back to automatic cover selection.
  Future<void> clearCoverPhoto(String tripId) => _queue.run(
    tripId,
    () => _repository.updateTripDetails(tripId, clearCover: true),
  );
}
