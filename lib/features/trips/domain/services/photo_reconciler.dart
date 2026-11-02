import '../entities/trip_photo.dart';
import 'photo_matcher.dart';

/// Turns match results into stored photos without losing user edits.
///
/// * A photo is identified by its library id (or path), so re-running never
///   creates a second row for the same photo.
/// * Photos the user moved, detached or excluded are left exactly as they are.
/// * Untouched photos get the fresh match result.
/// * Stored photos that the scan no longer returns (deleted, access revoked)
///   are kept; their rows are only references and the UI shows a placeholder.
abstract final class PhotoReconciler {
  static String photoId(String tripId, String key) => 'photo-$tripId-$key';

  static List<TripPhoto> reconcile({
    required String tripId,
    required List<TripPhoto> existing,
    required List<PhotoMatch> matches,
  }) {
    final byId = {for (final p in existing) p.id: p};
    final upserts = <TripPhoto>[];
    for (final match in matches) {
      final id = photoId(tripId, match.photo.key);
      final previous = byId[id];
      if (previous != null &&
          (previous.isManuallyEdited || previous.isExcluded)) {
        continue;
      }
      final next = TripPhoto(
        id: id,
        tripId: tripId,
        assetId: match.photo.assetId,
        localPath: match.photo.localPath ?? '',
        latitude: match.photo.latitude,
        longitude: match.photo.longitude,
        takenAt: match.photo.takenAt,
        stopId: match.stopId,
        matchMethod: match.method,
        matchConfidence: match.confidence,
        width: match.photo.width,
        height: match.photo.height,
      );
      if (previous == null || !_same(previous, next)) upserts.add(next);
    }
    return upserts;
  }

  static bool _same(TripPhoto a, TripPhoto b) =>
      a.stopId == b.stopId &&
      a.matchMethod == b.matchMethod &&
      a.matchConfidence == b.matchConfidence &&
      a.takenAt == b.takenAt &&
      a.latitude == b.latitude &&
      a.longitude == b.longitude &&
      a.localPath == b.localPath &&
      a.width == b.width &&
      a.height == b.height;
}

/// User edits on photos. Each one flags the photo as manually edited so that
/// re-matching leaves it alone. Original files are never touched.
abstract final class PhotoEditing {
  static TripPhoto moveToStop(TripPhoto photo, String stopId) => photo.copyWith(
    stopId: stopId,
    matchMethod: PhotoMatchMethod.manual,
    matchConfidence: 1,
    isManuallyEdited: true,
    isExcluded: false,
  );

  static TripPhoto detach(TripPhoto photo) => photo.copyWith(
    clearStop: true,
    matchMethod: PhotoMatchMethod.none,
    matchConfidence: 0,
    isManuallyEdited: true,
  );

  static TripPhoto exclude(TripPhoto photo) =>
      photo.copyWith(isExcluded: true, isManuallyEdited: true);

  static TripPhoto restore(TripPhoto photo) =>
      photo.copyWith(isExcluded: false);
}
