import '../entities/stop.dart';
import '../entities/trip.dart';
import '../entities/trip_photo.dart';
import '../entities/trip_timeline.dart';

/// Builds the result timeline from a trip's stored stops, photos and
/// cover choices. Pure and deterministic; it never invents places or content.
abstract final class TripTimelineBuilder {
  static TripTimeline build(Trip trip) {
    final stops = [...trip.stops]
      ..sort((a, b) {
        final byTime = a.arrivalTime.compareTo(b.arrivalTime);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final active = trip.activePhotos.toList()..sort(_byTime);
    final stopIds = {for (final s in stops) s.id};

    final byStop = <String, List<TripPhoto>>{};
    final route = <TripPhoto>[];
    final unclassified = <TripPhoto>[];
    for (final photo in active) {
      final stopId = photo.stopId;
      if (stopId != null && stopIds.contains(stopId)) {
        byStop.putIfAbsent(stopId, () => []).add(photo);
      } else if (stopId == null && photo.isRoutePhoto) {
        route.add(photo);
      } else {
        unclassified.add(photo);
      }
    }

    return TripTimeline(
      stops: [
        for (final entry in stops.indexed)
          TimelineStop(
            stop: entry.$2,
            order: entry.$1 + 1,
            photos: _coverFirst(byStop[entry.$2.id] ?? const [], entry.$2),
          ),
      ],
      routePhotos: route,
      unclassifiedPhotos: unclassified,
      excludedPhotos: trip.photos.where((p) => p.isExcluded).toList()
        ..sort(_byTime),
      coverPhoto: TripCoverSelector.select(trip),
    );
  }

  static List<TripPhoto> _coverFirst(List<TripPhoto> photos, Stop stop) {
    final cover = photos.where((p) => p.id == stop.coverPhotoId).firstOrNull;
    if (cover == null) return photos;
    return [cover, ...photos.where((p) => p.id != cover.id)];
  }

  static int _byTime(TripPhoto a, TripPhoto b) {
    final at = a.takenAt, bt = b.takenAt;
    if (at == null && bt == null) return a.id.compareTo(b.id);
    if (at == null) return 1;
    if (bt == null) return -1;
    final c = at.compareTo(bt);
    return c != 0 ? c : a.id.compareTo(b.id);
  }
}

/// Picks the trip's representative photo without judging image quality.
///
/// 1. The photo the user chose, if it is still part of the result.
/// 2. Otherwise, in this order of preference:
///    * not known to be small (shorter side under [minSide] px);
///    * placed on a stop, then on the route, then unclassified;
///    * the representative photo of its stop;
///    * higher matching confidence;
///    * earlier capture time, then id, so the choice is always the same.
abstract final class TripCoverSelector {
  static const minSide = 600;

  static TripPhoto? select(Trip trip) {
    final active = trip.activePhotos;
    if (active.isEmpty) return null;
    final manual = trip.coverPhotoId;
    if (manual != null) {
      final chosen = active.where((p) => p.id == manual).firstOrNull;
      if (chosen != null) return chosen;
    }
    final stopsById = {for (final s in trip.stops) s.id: s};
    int size(TripPhoto p) {
      final w = p.width, h = p.height;
      if (w == null || h == null) return 1; // unknown
      return (w < h ? w : h) >= minSide ? 0 : 2;
    }

    int placement(TripPhoto p) => p.stopId != null && stopsById.containsKey(p.stopId)
        ? 0
        : p.isRoutePhoto
        ? 1
        : 2;
    bool isStopCover(TripPhoto p) =>
        stopsById[p.stopId]?.coverPhotoId == p.id;

    final sorted = [...active]
      ..sort((a, b) {
        var c = size(a).compareTo(size(b));
        if (c != 0) return c;
        c = placement(a).compareTo(placement(b));
        if (c != 0) return c;
        c = (isStopCover(a) ? 0 : 1).compareTo(isStopCover(b) ? 0 : 1);
        if (c != 0) return c;
        c = b.matchConfidence.compareTo(a.matchConfidence);
        if (c != 0) return c;
        final at = a.takenAt, bt = b.takenAt;
        if (at != null || bt != null) {
          if (at == null) return 1;
          if (bt == null) return -1;
          c = at.compareTo(bt);
          if (c != 0) return c;
        }
        return a.id.compareTo(b.id);
      });
    return sorted.first;
  }
}
