import '../entities/stop.dart';

/// User edits on stops. Every edit flags the stop as user-modified so
/// re-analysis leaves it alone.
abstract final class StopEditing {
  static Stop rename(Stop stop, String name) {
    final trimmed = name.trim();
    return stop.copyWith(
      placeName: trimmed,
      isNameEdited: trimmed.isNotEmpty,
      isUserModified: true,
    );
  }

  static Stop exclude(Stop stop) =>
      stop.copyWith(isExcluded: true, isUserModified: true);

  static Stop restore(Stop stop) => stop.copyWith(isExcluded: false);

  /// Merges two neighbouring stops into one; [earlier] must not start after
  /// [later]. Nothing is dropped: both memos, linked markers and (if both were
  /// renamed) the second name are carried over.
  static Stop merge(Stop earlier, Stop later) {
    final end = [
      earlier.departureTime ?? earlier.arrivalTime,
      later.departureTime ?? later.arrivalTime,
    ].reduce((a, b) => a.isAfter(b) ? a : b);
    final arrival = earlier.arrivalTime.isBefore(later.arrivalTime)
        ? earlier.arrivalTime
        : later.arrivalTime;

    // Keep the automatic stop's identity so re-analysis still recognises it.
    final keepLater =
        earlier.source == StopSource.manual &&
        later.source == StopSource.automatic;
    final primary = keepLater ? later : earlier;
    final secondary = keepLater ? earlier : later;

    final (latitude, longitude) = _position(earlier, later);

    var name = primary.placeName;
    String? extraMemo;
    if (primary.isNameEdited && secondary.isNameEdited) {
      if (secondary.placeName != primary.placeName) {
        extraMemo = '병합 전 장소: ${secondary.placeName}';
      }
    } else if (secondary.isNameEdited) {
      name = secondary.placeName;
    }
    final memo = _joinDistinct([primary.memo, secondary.memo, extraMemo]);
    final markerIds = {...primary.markerIds, ...secondary.markerIds}.toList();

    return Stop(
      id: primary.id,
      tripId: primary.tripId,
      placeName: name,
      latitude: latitude,
      longitude: longitude,
      arrivalTime: arrival,
      departureTime: end,
      memo: memo,
      photoIds: {...primary.photoIds, ...secondary.photoIds}.toList(),
      source: earlier.source == later.source
          ? earlier.source
          : StopSource.automatic,
      isNameEdited: primary.isNameEdited || secondary.isNameEdited,
      isUserModified: true,
      markerIds: markerIds,
    );
  }

  static (double, double) _position(Stop a, Stop b) {
    final aPoint = a.dwell == null || a.dwell == Duration.zero;
    final bPoint = b.dwell == null || b.dwell == Duration.zero;
    if (aPoint && !bPoint) return (b.latitude, b.longitude);
    if (bPoint && !aPoint) return (a.latitude, a.longitude);
    final wa = (a.dwell?.inSeconds ?? 0) + 60;
    final wb = (b.dwell?.inSeconds ?? 0) + 60;
    return (
      (a.latitude * wa + b.latitude * wb) / (wa + wb),
      (a.longitude * wa + b.longitude * wb) / (wa + wb),
    );
  }

  static String? _joinDistinct(List<String?> parts) {
    final seen = <String>[];
    for (final part in parts) {
      final text = part?.trim();
      if (text != null && text.isNotEmpty && !seen.contains(text)) {
        seen.add(text);
      }
    }
    return seen.isEmpty ? null : seen.join('\n');
  }
}
