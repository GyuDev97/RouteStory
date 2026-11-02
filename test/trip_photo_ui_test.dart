import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/application/trip_providers.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/domain/entities/trip_photo.dart';
import 'package:route_story/features/trips/presentation/trip_result_screen.dart';

import 'support/fake_photo_library.dart';

Future<void> pump(
  WidgetTester tester,
  Trip trip,
  FakePhotoLibrary library,
  MemoryTripRepository repo,
) async {
  tester.view.physicalSize = const Size(900, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripRepositoryProvider.overrideWithValue(repo),
        photoLibraryServiceProvider.overrideWithValue(library),
      ],
      child: MaterialApp(home: TripResultScreen(trip: trip)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<(MemoryTripRepository, Trip)> setup(
    List<TripPhoto> photos, {
    PhotoMatchStatus status = PhotoMatchStatus.completed,
  }) async {
    final repo = MemoryTripRepository();
    final trip = Trip(
      id: 'real',
      title: '오늘의 여정',
      startTime: DateTime(2026, 9, 1, 9),
      endTime: DateTime(2026, 9, 1, 12),
      totalDistance: 9000,
      stopAnalysisStatus: StopAnalysisStatus.completed,
      photoMatchStatus: status,
    );
    await repo.saveTrip(trip);
    await repo.saveStopChanges(
      'real',
      upserts: [
        Stop(
          id: 's1',
          tripId: 'real',
          placeName: '성수 카페',
          latitude: 37.5,
          longitude: 127,
          arrivalTime: DateTime(2026, 9, 1, 10),
          departureTime: DateTime(2026, 9, 1, 10, 40),
        ),
      ],
    );
    await repo.savePhotos('real', upserts: photos, status: status);
    return (repo, (await repo.getTrip('real'))!);
  }

  TripPhoto photo(String id, {String? stopId, PhotoMatchMethod? m}) => TripPhoto(
    id: id,
    tripId: 'real',
    assetId: id,
    takenAt: DateTime(2026, 9, 1, 10, 5),
    stopId: stopId,
    matchMethod: m ?? (stopId == null ? PhotoMatchMethod.none : PhotoMatchMethod.time),
  );

  testWidgets('stop photos, route photos and photos to check are shown', (tester) async {
    final (repo, trip) = await setup([
      photo('a', stopId: 's1'),
      photo('b', stopId: 's1'),
      photo('c', stopId: 's1'),
      photo('r', m: PhotoMatchMethod.route),
      photo('u'),
    ]);
    await pump(tester, trip, FakePhotoLibrary(), repo);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('3 Photos'), findsOneWidget);
    expect(find.text('이동 중 찍은 사진'), findsOneWidget);
    expect(find.text('확인이 필요한 사진'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stop without photos hides the photo area', (tester) async {
    final (repo, trip) = await setup([]);
    await pump(tester, trip, FakePhotoLibrary(), repo);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining('Photos'), findsNothing);
    expect(find.text('이 시간대에 찍은 사진을 찾지 못했어요.'), findsOneWidget);
  });

  testWidgets('deleted originals show a placeholder, not a crash', (tester) async {
    final (repo, trip) = await setup([photo('gone', stopId: 's1')]);
    final library = FakePhotoLibrary()..deleted.add('gone');
    await pump(tester, trip, library, repo);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no permission explains it and offers allow / pick / settings', (tester) async {
    final (repo, trip) = await setup([], status: PhotoMatchStatus.noAccess);
    await pump(tester, trip, FakePhotoLibrary(), repo);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.textContaining('사진 접근이 허용되지 않아'), findsOneWidget);
    expect(find.text('사진 접근 허용'), findsOneWidget);
    expect(find.text('사진 직접 선택'), findsOneWidget);
    expect(find.text('설정 열기'), findsOneWidget);
  });

  testWidgets('moving a photo from the action sheet persists', (tester) async {
    final (repo, trip) = await setup([photo('u')]);
    await repo.saveStopChanges(
      'real',
      upserts: [
        Stop(
          id: 's2',
          tripId: 'real',
          placeName: '전망대',
          latitude: 37.6,
          longitude: 127,
          arrivalTime: DateTime(2026, 9, 1, 11),
          departureTime: DateTime(2026, 9, 1, 11, 30),
        ),
      ],
    );
    final fresh = (await repo.getTrip('real'))!;
    expect(trip.stops, hasLength(1));
    await pump(tester, fresh, FakePhotoLibrary(), repo);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Image).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('장소에 연결'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전망대 · 11:00'));
    await tester.pumpAndSettle();
    final stored = (await repo.getPhotos('real')).single;
    expect(stored.stopId, 's2');
    expect(stored.isManuallyEdited, isTrue);
  });

  testWidgets('demo trip never shows photo sections or touches the library', (tester) async {
    final repo = MemoryTripRepository();
    final demo = (await repo.getRecentTrips()).first;
    await pump(tester, demo, FakePhotoLibrary(), repo);
    expect(find.text('사진 다시 찾기'), findsNothing);
  });
}
