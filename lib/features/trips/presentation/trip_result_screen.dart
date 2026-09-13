import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_preview.dart';
import '../../../core/widgets/route_story_button.dart';
import '../../../core/widgets/trip_image.dart';
import '../domain/entities/stop.dart';
import '../domain/entities/trip.dart';
import '../domain/entities/trip_photo.dart';

class TripResultScreen extends StatelessWidget {
  const TripResultScreen({super.key, required this.trip});
  final Trip trip;
  String get _date =>
      '${trip.startTime.year}. ${trip.startTime.month.toString().padLeft(2, '0')}. ${trip.startTime.day.toString().padLeft(2, '0')}';
  String get _duration {
    final d = (trip.endTime ?? DateTime.now()).difference(trip.startTime);
    return '${d.inHours}시간 ${d.inMinutes.remainder(60)}분';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, size: 20),
              ),
              const Spacer(),
              const Icon(Icons.more_horiz, size: 20),
            ],
          ),
          const SizedBox(height: 22),
          Text(trip.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 7),
          Text(_date, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 26),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: TripImage(
                path: trip.photos.isEmpty ? null : trip.photos.first.localPath,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              _Metric(
                value: '${trip.totalDistance.toStringAsFixed(1)} km',
                label: '총 이동거리',
              ),
              _Metric(value: _duration, label: '여행시간'),
              _Metric(value: '${trip.stops.length}', label: 'Stops'),
            ],
          ),
          const SizedBox(height: 42),
          const Text(
            'YOUR ROUTE',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.forest,
            ),
          ),
          const SizedBox(height: 13),
          MapPreview(points: trip.gpsPoints),
          const SizedBox(height: 42),
          const Text(
            '여행 타임라인',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 18),
          ...trip.stops.indexed.map(
            (entry) => _StopStory(
              stop: entry.$2,
              photos: _photosFor(entry.$2),
              isLast: entry.$1 == trip.stops.length - 1,
            ),
          ),
          if (trip.stops.isEmpty) const Text('기록된 장소가 아직 없어요.'),
          const SizedBox(height: 18),
          RouteStoryButton(
            label: '여행 영상 만들기',
            icon: Icons.play_circle_outline,
            onPressed: () => _comingSoon(context, '여행 영상 생성은 다음 단계에서 연결됩니다.'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _comingSoon(context, '공유 페이지는 서버 연결 후 제공됩니다.'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppTheme.forest,
              side: const BorderSide(color: AppTheme.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('여행 페이지 공유'),
          ),
        ],
      ),
    ),
  );
  List<TripPhoto> _photosFor(Stop stop) =>
      trip.photos.where((photo) => stop.photoIds.contains(photo.id)).toList();
  void _comingSoon(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF68665F)),
        ),
      ],
    ),
  );
}

class _StopStory extends StatelessWidget {
  const _StopStory({
    required this.stop,
    required this.photos,
    required this.isLast,
  });
  final Stop stop;
  final List<TripPhoto> photos;
  final bool isLast;
  String get _time =>
      '${stop.arrivalTime.hour.toString().padLeft(2, '0')}:${stop.arrivalTime.minute.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            _time,
            style: const TextStyle(fontSize: 12, color: Color(0xFF68665F)),
          ),
        ),
        Column(
          children: [
            const SizedBox(height: 5),
            Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: AppTheme.forest,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: AppTheme.line,
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.placeName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _PhotoStrip(photos: photos),
                const SizedBox(height: 9),
                Text(
                  '${photos.length} Photos',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.forest,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos});
  final List<TripPhoto> photos;
  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final shown = photos.take(2).toList();
    if (shown.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 8,
          child: TripImage(path: shown.first.localPath),
        ),
      );
    }
    return SizedBox(
      height: 116,
      child: Row(
        children: [
          for (final photo in shown)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: photo == shown.last ? 0 : 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: TripImage(path: photo.localPath),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
