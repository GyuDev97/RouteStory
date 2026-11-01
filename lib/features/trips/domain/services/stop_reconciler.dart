import '../entities/manual_marker.dart';
import '../entities/stop.dart';
import 'distance_calculator.dart';
import 'stop_candidate.dart';
import 'stop_detection_config.dart';

class StopChanges {
  const StopChanges({required this.upserts, required this.deleteIds});
  final List<Stop> upserts;
  final List<String> deleteIds;
}

/// Merges fresh detection results into the stops already stored for a trip
/// without losing user edits.
///
/// Policy:
/// * An existing stop is matched to a candidate by time overlap alone (two
///   stops of one trip cannot overlap), so merged or moved stops still match.
/// * Matched + untouched: times and position are refreshed, id is stable.
/// * Matched + excluded or user-modified: kept exactly as the user left it.
/// * Unmatched automatic stop: removed only if untouched; otherwise kept.
/// * ManualMarkers are never deleted. A marker that fits an automatic stop
///   (time within tolerance and within radius) is linked to it; any other
///   marker becomes its own `manual` stop.
abstract final class StopReconciler {
  static StopChanges reconcile({
    required String tripId,
    required List<Stop> existing,
    required List<StopCandidate> candidates,
    required List<ManualMarker> markers,
    StopDetectionConfig config = const StopDetectionConfig(),
  }) {
    final existingAuto = existing
        .where((s) => !_isMarkerStop(s))
        .toList(growable: false);
    final matchedIds = <String>{};
    final result = <Stop>[];
    final usedIds = {for (final s in existing) s.id};

    for (final candidate in candidates) {
      final match = existingAuto
          .where((s) => _overlaps(s, candidate))
          .cast<Stop?>()
          .firstOrNull;
      if (match == null) {
        var id = 'stop-$tripId-${candidate.arrivalTime.millisecondsSinceEpoch}';
        while (!usedIds.add(id)) {
          id = '$id-b';
        }
        result.add(
          Stop(
            id: id,
            tripId: tripId,
            placeName: '',
            latitude: candidate.latitude,
            longitude: candidate.longitude,
            arrivalTime: candidate.arrivalTime,
            departureTime: candidate.departureTime,
          ),
        );
        continue;
      }
      for (final s in existingAuto.where((s) => _overlaps(s, candidate))) {
        matchedIds.add(s.id);
      }
      if (result.any((s) => s.id == match.id)) continue;
      result.add(
        match.isExcluded || match.isUserModified
            ? match
            : match.copyWith(
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                arrivalTime: candidate.arrivalTime,
                departureTime: candidate.departureTime,
              ),
      );
    }
    for (final stop in existingAuto) {
      if (!matchedIds.contains(stop.id) &&
          (stop.isExcluded || stop.isUserModified)) {
        result.add(stop);
      }
    }

    final markerChanges = _linkMarkers(tripId, existing, result, markers, config);
    final finalStops = markerChanges;
    final finalIds = {for (final s in finalStops) s.id};
    final deleteIds = [
      for (final s in existing)
        if (!finalIds.contains(s.id)) s.id,
    ];
    final previousById = {for (final s in existing) s.id: s};
    final upserts = [
      for (final s in finalStops)
        if (!_sameStop(previousById[s.id], s)) s,
    ];
    return StopChanges(upserts: upserts, deleteIds: deleteIds);
  }

  static List<Stop> _linkMarkers(
    String tripId,
    List<Stop> existing,
    List<Stop> autoStops,
    List<ManualMarker> markers,
    StopDetectionConfig config,
  ) {
    final linked = <String, List<String>>{};
    final memoFor = <String, String>{};
    final standalone = <ManualMarker>[];
    final visible = autoStops.where((s) => !s.isExcluded).toList();
    for (final marker in markers) {
      final stop =
          visible.where((s) => s.markerIds.contains(marker.id)).firstOrNull ??
          _nearestFit(visible, marker, config);
      if (stop == null) {
        standalone.add(marker);
        continue;
      }
      linked.putIfAbsent(stop.id, () => []).add(marker.id);
      final memo = marker.memo?.trim();
      if (memo != null && memo.isNotEmpty) {
        memoFor[stop.id] = [?memoFor[stop.id], memo].join('\n');
      }
    }

    final out = <Stop>[
      for (final s in autoStops)
        s.copyWith(
          markerIds: linked[s.id] ?? const [],
          memo: (s.memo == null || s.memo!.isEmpty) && memoFor[s.id] != null
              ? memoFor[s.id]
              : null,
        ),
    ];
    final existingById = {for (final s in existing) s.id: s};
    for (final marker in standalone) {
      final id = markerStopId(marker.id);
      final previous = existingById[id];
      out.add(
        previous ??
            Stop(
              id: id,
              tripId: tripId,
              placeName: '',
              latitude: marker.latitude,
              longitude: marker.longitude,
              arrivalTime: marker.timestamp,
              departureTime: marker.timestamp,
              memo: marker.memo,
              source: StopSource.manual,
              markerIds: [marker.id],
            ),
      );
    }
    // Marker stops the user edited or excluded survive even if their marker
    // now fits an automatic stop; untouched ones are dropped.
    for (final stop in existing.where(_isMarkerStop)) {
      if (!out.any((s) => s.id == stop.id) &&
          (stop.isExcluded || stop.isUserModified)) {
        out.add(stop);
      }
    }
    return out;
  }

  static Stop? _nearestFit(
    List<Stop> stops,
    ManualMarker marker,
    StopDetectionConfig config,
  ) {
    Stop? best;
    var bestOffset = const Duration(days: 365);
    for (final stop in stops) {
      final end = stop.departureTime ?? stop.arrivalTime;
      final from = stop.arrivalTime.subtract(config.markerTimeTolerance);
      final to = end.add(config.markerTimeTolerance);
      if (marker.timestamp.isBefore(from) || marker.timestamp.isAfter(to)) {
        continue;
      }
      final distance = DistanceCalculator.metersBetweenCoordinates(
        stop.latitude,
        stop.longitude,
        marker.latitude,
        marker.longitude,
      );
      if (distance > config.stopRadiusMeters) continue;
      final offset = marker.timestamp.isBefore(stop.arrivalTime)
          ? stop.arrivalTime.difference(marker.timestamp)
          : marker.timestamp.isAfter(end)
          ? marker.timestamp.difference(end)
          : Duration.zero;
      if (offset < bestOffset) {
        best = stop;
        bestOffset = offset;
      }
    }
    return best;
  }

  static String markerStopId(String markerId) => 'stop-marker-$markerId';

  static bool _isMarkerStop(Stop s) => s.id.startsWith('stop-marker-');

  static bool _overlaps(Stop stop, StopCandidate candidate) =>
      !stop.arrivalTime.isAfter(candidate.departureTime) &&
      !(stop.departureTime ?? stop.arrivalTime).isBefore(candidate.arrivalTime);

  static bool _sameStop(Stop? a, Stop b) =>
      a != null &&
      a.placeName == b.placeName &&
      a.latitude == b.latitude &&
      a.longitude == b.longitude &&
      a.arrivalTime == b.arrivalTime &&
      a.departureTime == b.departureTime &&
      a.memo == b.memo &&
      a.source == b.source &&
      a.isExcluded == b.isExcluded &&
      a.isNameEdited == b.isNameEdited &&
      a.isUserModified == b.isUserModified &&
      a.markerIds.join(',') == b.markerIds.join(',');
}
