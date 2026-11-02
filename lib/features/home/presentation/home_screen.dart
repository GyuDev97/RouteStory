import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/route_story_button.dart';
import '../../trips/presentation/trip_photo_widgets.dart';
import '../../trips/application/trip_providers.dart';
import '../../trips/application/trip_recording_controller.dart';
import '../../trips/domain/entities/trip.dart';
import '../../trips/domain/services/distance_formatter.dart';
import '../../trips/presentation/record_trip_screen.dart';
import '../../trips/presentation/trip_result_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(recentTripsProvider);
    final recording = ref.watch(tripRecordingControllerProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      children: [
        const Text(
          'ROUTE\nSTORY',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            height: .9,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 44),
        Text(
          '오늘의 길을\n한 편의 이야기로.',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 16),
        const Text('움직인 길과 기억하고 싶은 순간을 조용히 모읍니다.'),
        const SizedBox(height: 28),
        RouteStoryButton(
          label: '여행 시작',
          icon: Icons.arrow_forward,
          onPressed: () async {
            final started = await ref
                .read(tripRecordingControllerProvider.notifier)
                .start();
            if (!context.mounted) return;
            if (started) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecordTripScreen()),
              );
            } else {
              final message =
                  ref.read(tripRecordingControllerProvider).message ??
                  '위치를 준비하지 못했어요.';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  action: SnackBarAction(
                    label: '설정 열기',
                    onPressed: () => ref
                        .read(locationTrackingServiceProvider)
                        .openAppSettings(),
                  ),
                ),
              );
            }
          },
        ),
        if (recording.phase == RecordingPhase.recording) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const RecordTripScreen())),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.sand,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.location_history,
                    color: AppTheme.forest,
                    size: 19,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '기록 중이던 여행이 있습니다.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 17, color: AppTheme.forest),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 42),
        const Text(
          '최근 여행',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        trips.when(
          data: (items) => Column(
            children: items
                .take(2)
                .map((trip) => _TripCard(trip: trip))
                .toList(),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const Text('여행을 불러오지 못했어요.'),
        ),
      ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});
  final Trip trip;
  String get _date =>
      '${trip.startTime.year}. ${trip.startTime.month.toString().padLeft(2, '0')}. ${trip.startTime.day.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TripResultScreen(trip: trip))),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.line),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 74,
                height: 74,
                child: TripCoverImage(trip: trip),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(_date, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 7),
                  Text(
                    '${formatKilometers(trip.totalDistance)} · ${trip.stops.length} Stops · ${trip.activePhotos.length} Photos',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.forest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


