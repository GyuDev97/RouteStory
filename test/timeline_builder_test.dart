import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/entities/trip_photo.dart';
import 'package:route_story/features/trips/domain/services/trip_progress.dart';
import 'package:route_story/features/trips/domain/services/trip_timeline_builder.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 9, 1, h, m);

Stop stop(String id, int h, {String? cover, bool excluded = false}) => Stop(
  id: id,
  tripId: 't',
  placeName: id,
  latitude: 37.5,
  longitude: 127,
  arrivalTime: at(h),
  departureTime: at(h, 40),
  coverPhotoId: cover,
  isExcluded: excluded,
);

TripPhoto photo(
  String id, {
  String? stopId,
  PhotoMatchMethod? method,
  int? h,
  int m = 0,
  int? w,
  int? hh,
  double confidence = 0.7,
  bool excluded = false,
}) => TripPhoto(
  id: id,
  tripId: 't',
  assetId: id,
  takenAt: h == null ? null : at(h, m),
  stopId: stopId,
  matchMethod:
      method ?? (stopId == null ? PhotoMatchMethod.none : PhotoMatchMethod.time),
  matchConfidence: confidence,
  width: w,
  height: hh,
  isExcluded: excluded,
);

Trip trip({
  List<Stop> stops = const [],
  List<TripPhoto> photos = const [],
  String? cover,
  List<Stop> excludedStops = const [],
  StopAnalysisStatus stopStatus = StopAnalysisStatus.completed,
  PhotoMatchStatus photoStatus = PhotoMatchStatus.completed,
}) => Trip(
  id: 't',
  title: '여행',
  startTime: at(9),
  endTime: at(18),
  totalDistance: 1000,
  stops: stops,
  excludedStops: excludedStops,
  photos: photos,
  coverPhotoId: cover,
  stopAnalysisStatus: stopStatus,
  photoMatchStatus: photoStatus,
);

void main() {
  group('timeline', () {
    test('stops are ordered by arrival and carry their photos, cover first', () {
      final timeline = TripTimelineBuilder.build(
        trip(
          stops: [stop('late', 14), stop('early', 10, cover: 'b')],
          photos: [
            photo('a', stopId: 'early', h: 10, m: 5),
            photo('b', stopId: 'early', h: 10, m: 20),
            photo('c', stopId: 'late', h: 14, m: 5),
          ],
        ),
      );
      expect(timeline.stops.map((s) => s.stop.id), ['early', 'late']);
      expect(timeline.stops.map((s) => s.order), [1, 2]);
      expect(timeline.stops[0].photos.map((p) => p.id), ['b', 'a']);
      expect(timeline.stops[0].cover!.id, 'b');
      expect(timeline.stops[1].photos.map((p) => p.id), ['c']);
    });

    test('no stops, several photos: nothing is dropped', () {
      final timeline = TripTimelineBuilder.build(
        trip(
          photos: [
            photo('r1', method: PhotoMatchMethod.route, h: 10),
            photo('r2', method: PhotoMatchMethod.route, h: 11),
            photo('u1'),
            photo('u2', h: 12),
          ],
        ),
      );
      expect(timeline.stops, isEmpty);
      expect(timeline.routePhotos.map((p) => p.id), ['r1', 'r2']);
      expect(timeline.unclassifiedPhotos.map((p) => p.id), ['u2', 'u1']);
      expect(timeline.activePhotoCount, 4);
      expect(timeline.hasContent, isTrue);
      expect(timeline.coverPhoto, isNotNull);
    });

    test('stops without photos and trips with nothing at all are fine', () {
      final onlyStops = TripTimelineBuilder.build(
        trip(stops: [stop('a', 10), stop('b', 12)]),
      );
      expect(onlyStops.stops, hasLength(2));
      expect(onlyStops.stops.every((s) => s.photos.isEmpty && s.cover == null), isTrue);
      expect(onlyStops.coverPhoto, isNull);

      final empty = TripTimelineBuilder.build(trip());
      expect(empty.hasContent, isFalse);
      expect(empty.coverPhoto, isNull);
    });

    test('route-only trip', () {
      final t = TripTimelineBuilder.build(
        trip(photos: [photo('r', method: PhotoMatchMethod.route, h: 10)]),
      );
      expect(t.routePhotos, hasLength(1));
      expect(t.unclassifiedPhotos, isEmpty);
      expect(t.coverPhoto!.id, 'r');
    });

    test('photos on a missing or excluded stop are shown as unclassified', () {
      final t = TripTimelineBuilder.build(
        trip(
          stops: [stop('a', 10)],
          excludedStops: [stop('gone', 12, excluded: true)],
          photos: [
            photo('onGone', stopId: 'gone', h: 12),
            photo('onNothing', stopId: 'deleted-stop', h: 13),
            photo('ok', stopId: 'a', h: 10),
          ],
        ),
      );
      expect(t.unclassifiedPhotos.map((p) => p.id), ['onGone', 'onNothing']);
      expect(t.stops.single.photos.map((p) => p.id), ['ok']);
    });

    test('excluded photos leave the result but can be listed for restore', () {
      final t = TripTimelineBuilder.build(
        trip(
          stops: [stop('a', 10)],
          photos: [
            photo('keep', stopId: 'a', h: 10),
            photo('drop', stopId: 'a', h: 10, m: 5, excluded: true),
          ],
        ),
      );
      expect(t.stops.single.photos.map((p) => p.id), ['keep']);
      expect(t.excludedPhotos.map((p) => p.id), ['drop']);
      expect(t.activePhotoCount, 1);
    });

    test('a stop with dozens of photos keeps every one', () {
      final photos = [
        for (var i = 0; i < 40; i++) photo('p$i', stopId: 'a', h: 10, m: i % 40),
      ];
      final t = TripTimelineBuilder.build(trip(stops: [stop('a', 10)], photos: photos));
      expect(t.stops.single.photos, hasLength(40));
    });

    test('building twice gives the same result', () {
      final tr = trip(
        stops: [stop('a', 10), stop('b', 12)],
        photos: [
          photo('x', stopId: 'a', h: 10, m: 1),
          photo('y', stopId: 'b', h: 12, m: 1),
          photo('z', method: PhotoMatchMethod.route, h: 11),
        ],
      );
      final one = TripTimelineBuilder.build(tr);
      final two = TripTimelineBuilder.build(tr);
      expect(one.coverPhoto!.id, two.coverPhoto!.id);
      expect(
        one.stops.map((s) => s.photos.map((p) => p.id).toList()).toList(),
        two.stops.map((s) => s.photos.map((p) => p.id).toList()).toList(),
      );
    });

    test('large trip builds fast (50 stops, 600 photos)', () {
      final stops = [for (var i = 0; i < 50; i++) stop('s$i', 9 + i ~/ 6)];
      final photos = [
        for (var i = 0; i < 600; i++)
          photo(
            'p$i',
            stopId: i % 7 == 0 ? null : 's${i % 50}',
            method: i % 7 == 0 ? PhotoMatchMethod.route : null,
            h: 9 + i % 9,
            m: i % 60,
          ),
      ];
      final watch = Stopwatch()..start();
      final t = TripTimelineBuilder.build(trip(stops: stops, photos: photos));
      watch.stop();
      expect(t.activePhotoCount, 600);
      expect(watch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('trip cover selection', () {
    test('the user\'s choice always wins', () {
      final tr = trip(
        stops: [stop('a', 10)],
        photos: [
          photo('auto', stopId: 'a', h: 10, w: 4000, hh: 3000),
          photo('mine', h: 15, w: 100, hh: 100),
        ],
        cover: 'mine',
      );
      expect(TripCoverSelector.select(tr)!.id, 'mine');
    });

    test('a chosen photo that was excluded falls back to automatic', () {
      final tr = trip(
        stops: [stop('a', 10)],
        photos: [
          photo('auto', stopId: 'a', h: 10),
          photo('mine', stopId: 'a', h: 11, excluded: true),
        ],
        cover: 'mine',
      );
      expect(TripCoverSelector.select(tr)!.id, 'auto');
    });

    test('photos known to be small lose against larger or unknown sizes', () {
      final tr = trip(
        stops: [stop('a', 10)],
        photos: [
          photo('small', stopId: 'a', h: 9, w: 320, hh: 240),
          photo('big', stopId: 'a', h: 10, w: 4000, hh: 3000),
        ],
      );
      expect(TripCoverSelector.select(tr)!.id, 'big');
      final unknown = trip(
        stops: [stop('a', 10)],
        photos: [
          photo('small', stopId: 'a', h: 9, w: 320, hh: 240),
          photo('unknown', stopId: 'a', h: 10),
        ],
      );
      expect(TripCoverSelector.select(unknown)!.id, 'unknown');
    });

    test('photos on a stop beat route photos beat unclassified ones', () {
      final tr = trip(
        stops: [stop('a', 12)],
        photos: [
          photo('u', h: 9),
          photo('r', method: PhotoMatchMethod.route, h: 10),
          photo('s', stopId: 'a', h: 12),
        ],
      );
      expect(TripCoverSelector.select(tr)!.id, 's');
      expect(
        TripCoverSelector.select(
          trip(photos: [photo('u', h: 9), photo('r', method: PhotoMatchMethod.route, h: 10)]),
        )!.id,
        'r',
      );
    });

    test('a stop\'s own representative photo is preferred, then confidence, then time', () {
      final withCover = trip(
        stops: [stop('a', 10, cover: 'b'), stop('c', 12)],
        photos: [
          photo('a1', stopId: 'a', h: 10),
          photo('b', stopId: 'a', h: 10, m: 30),
          photo('c1', stopId: 'c', h: 12),
        ],
      );
      expect(TripCoverSelector.select(withCover)!.id, 'b');
      final byConfidence = trip(
        stops: [stop('a', 10)],
        photos: [
          photo('lo', stopId: 'a', h: 10, confidence: 0.5),
          photo('hi', stopId: 'a', h: 10, m: 30, confidence: 0.9),
        ],
      );
      expect(TripCoverSelector.select(byConfidence)!.id, 'hi');
      final byTime = trip(
        stops: [stop('a', 10)],
        photos: [
          photo('late', stopId: 'a', h: 10, m: 30),
          photo('early', stopId: 'a', h: 10, m: 5),
        ],
      );
      expect(TripCoverSelector.select(byTime)!.id, 'early');
    });

    test('identical photos are chosen consistently (by id)', () {
      final tr = trip(
        stops: [stop('a', 10)],
        photos: [photo('b', stopId: 'a', h: 10), photo('a', stopId: 'a', h: 10)],
      );
      expect(TripCoverSelector.select(tr)!.id, 'a');
      expect(TripCoverSelector.select(trip()), isNull);
    });
  });

  group('progress', () {
    List<ProgressState> states(Trip t) =>
        TripProgress.of(t).steps.map((s) => s.state).toList();

    test('follows the stored step statuses', () {
      final start = trip(
        stopStatus: StopAnalysisStatus.pending,
        photoStatus: PhotoMatchStatus.pending,
      );
      expect(states(start), [
        ProgressState.done,
        ProgressState.running,
        ProgressState.waiting,
        ProgressState.waiting,
      ]);
      expect(TripProgress.of(start).isRunning, isTrue);

      final photos = trip(photoStatus: PhotoMatchStatus.pending);
      expect(states(photos), [
        ProgressState.done,
        ProgressState.done,
        ProgressState.running,
        ProgressState.waiting,
      ]);

      final done = trip();
      expect(states(done).every((s) => s == ProgressState.done), isTrue);
      expect(TripProgress.of(done).isComplete, isTrue);
    });

    test('failure is different from a result with zero stops', () {
      final zero = trip(); // analysis completed, no stops
      expect(zero.stops, isEmpty);
      expect(TripProgress.of(zero).hasFailure, isFalse);
      expect(TripProgress.of(zero).isComplete, isTrue);

      final failed = trip(stopStatus: StopAnalysisStatus.failed);
      final progress = TripProgress.of(failed);
      expect(progress.hasFailure, isTrue);
      expect(progress.isComplete, isFalse);
      expect(progress.steps.last.state, ProgressState.failed);
    });

    test('missing photo permission skips the step instead of failing', () {
      final p = TripProgress.of(trip(photoStatus: PhotoMatchStatus.noAccess));
      expect(p.steps[2].state, ProgressState.skipped);
      expect(p.hasFailure, isFalse);
      expect(p.steps.last.state, ProgressState.done);
    });
  });
}
