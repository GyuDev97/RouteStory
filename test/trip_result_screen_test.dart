import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:route_story/features/trips/application/trip_providers.dart';
import 'package:route_story/features/trips/data/repositories/memory_trip_repository.dart';
import 'package:route_story/features/trips/domain/entities/stop.dart';
import 'package:route_story/features/trips/domain/entities/trip.dart';
import 'package:route_story/features/trips/presentation/trip_result_screen.dart';

void main() {
  testWidgets('real trip shows stops with times and no photo placeholders', (
    tester,
  ) async {
    final repo = MemoryTripRepository();
    final trip = Trip(
      id: 'real-1',
      title: '오늘의 여정',
      startTime: DateTime(2026, 9, 1, 9),
      endTime: DateTime(2026, 9, 1, 18),
      totalDistance: 12,
      stopAnalysisStatus: StopAnalysisStatus.completed,
      stops: [
        Stop(
          id: 's',
          tripId: 'real-1',
          placeName: '',
          latitude: 37.5,
          longitude: 127,
          arrivalTime: DateTime(2026, 9, 1, 10, 0),
          departureTime: DateTime(2026, 9, 1, 10, 40),
        ),
        Stop(
          id: 'named',
          tripId: 'real-1',
          placeName: '성수 카페',
          latitude: 37.5,
          longitude: 127,
          arrivalTime: DateTime(2026, 9, 1, 12, 0),
          departureTime: DateTime(2026, 9, 1, 13, 5),
        ),
      ],
    );
    await repo.saveTrip(trip);
    await repo.saveStopChanges('real-1', upserts: trip.stops);
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: TripResultScreen(trip: trip)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();

    expect(find.text('방문 장소 1'), findsOneWidget);
    expect(find.text('성수 카페'), findsOneWidget);
    expect(find.textContaining('10:00 도착 · 10:40 출발 · 40분 체류'), findsOneWidget);
    expect(find.textContaining('1시간 5분 체류'), findsOneWidget);
    expect(find.textContaining('Photos'), findsNothing);
  });

  testWidgets('demo trip keeps its photo timeline', (tester) async {
    final repo = MemoryTripRepository();
    final demo = (await repo.getRecentTrips()).first;
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: TripResultScreen(trip: demo)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(demo.isDemo, isTrue);
    expect(find.text('4 Photos'), findsOneWidget);
  });
}


