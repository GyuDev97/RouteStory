import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import 'trip_photo_widgets.dart';
import '../application/trip_providers.dart';
import '../domain/entities/trip.dart';
import '../domain/services/distance_formatter.dart';
import 'trip_result_screen.dart';

class TripsScreen extends ConsumerWidget {
  const TripsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(recentTripsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 30),
      children: [
        const Text(
          '여행',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        const Text('완성된 길과 아직 정리 중인 이야기'),
        const SizedBox(height: 30),
        trips.when(
          data: (items) => Column(
            children: items.map((trip) => _ArchiveItem(trip: trip)).toList(),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const Text('여행을 불러올 수 없어요.'),
        ),
      ],
    );
  }
}

class _ArchiveItem extends StatelessWidget {
  const _ArchiveItem({required this.trip});
  final Trip trip;
  String get _date =>
      '${trip.startTime.year}. ${trip.startTime.month.toString().padLeft(2, '0')}. ${trip.startTime.day.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 38),
    child: InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TripResultScreen(trip: trip))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: TripCoverImage(trip: trip),
            ),
          ),
          const SizedBox(height: 15),
          Text(trip.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(_date, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            '${formatKilometers(trip.totalDistance)} · ${trip.stops.length} Stops',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.forest,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}


