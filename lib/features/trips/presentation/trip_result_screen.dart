import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_preview.dart';
import '../../../core/widgets/route_story_button.dart';
import '../application/trip_providers.dart';
import '../domain/entities/stop.dart';
import '../domain/entities/trip.dart';
import '../domain/entities/trip_photo.dart';
import '../domain/services/distance_formatter.dart';
import '../domain/services/trip_timeline_builder.dart';
import 'gps_debug_screen.dart';
import 'trip_photo_sections.dart';
import 'trip_photo_widgets.dart';

class TripResultScreen extends ConsumerWidget {
  const TripResultScreen({super.key, required this.trip});
  final Trip trip;
  String _date(Trip trip) =>
      '${trip.startTime.year}. ${trip.startTime.month.toString().padLeft(2, '0')}. ${trip.startTime.day.toString().padLeft(2, '0')}';
  String _duration(Trip trip) {
    final d = (trip.endTime ?? DateTime.now()).difference(trip.startTime);
    return '${d.inHours}시간 ${d.inMinutes.remainder(60)}분';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real trips are re-read so analysis and edits show up; demo trips are
    // static sample data and never touch the database.
    final current = trip.isDemo
        ? trip
        : ref.watch(tripDetailProvider(trip.id)).value ?? trip;
    final timeline = current.isDemo ? null : TripTimelineBuilder.build(current);
    return Scaffold(
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
                if (kDebugMode && !current.isDemo)
                  IconButton(
                    tooltip: 'GPS 점검 (debug)',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GpsDebugScreen(trip: current),
                      ),
                    ),
                    icon: const Icon(Icons.bug_report_outlined, size: 20),
                  )
                else
                  const Icon(Icons.more_horiz, size: 20),
              ],
            ),
            const SizedBox(height: 22),
            if (timeline != null) ProgressBanner(trip: current),
            Row(
              children: [
                Expanded(
                  child: Text(
                    current.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                if (!current.isDemo)
                  IconButton(
                    tooltip: '제목 수정',
                    onPressed: () async {
                      final title = await _askText(
                        context,
                        '여행 제목',
                        current.title,
                        '어떤 여행이었나요?',
                      );
                      if (title == null) return;
                      await ref
                          .read(tripServiceProvider)
                          .rename(trip.id, title);
                      _refresh(ref);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(_date(current), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 26),
            GestureDetector(
              onTap: timeline != null && current.activePhotos.isNotEmpty
                  ? () async {
                      await showCoverPicker(context, ref, current);
                    }
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: TripCoverImage(trip: current),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _Metric(
                  value: formatKilometers(current.totalDistance),
                  label: '총 이동거리',
                ),
                _Metric(value: _duration(current), label: '여행시간'),
                _Metric(value: '${current.stops.length}', label: 'Stops'),
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
            MapPreview(points: current.gpsPoints),
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
            if (current.isDemo)
              ...current.stops.indexed.map(
                (entry) => _StopStory(
                  stop: entry.$2,
                  photos: _photosFor(current, entry.$2),
                  isLast: entry.$1 == current.stops.length - 1,
                ),
              )
            else
              ...timeline!.stops.map(
                (entry) => _VisitStory(
                  stop: entry.stop,
                  order: entry.order,
                  photos: entry.photos,
                  onPhotoTap: (photo) =>
                      showPhotoActions(context, ref, current, photo),
                  isLast: entry.order == timeline.stops.length,
                  onMenu: () => _openMenu(
                    context,
                    ref,
                    current,
                    entry.stop,
                    entry.order - 1,
                  ),
                ),
              ),
            if (current.stops.isEmpty) _EmptyTimeline(trip: current),
            if (timeline != null)
              PhotoSections(trip: current, timeline: timeline),
            if (!current.isDemo && current.excludedStops.isNotEmpty)
              _RestoreExcluded(trip: current, onChanged: () => _refresh(ref)),
            const SizedBox(height: 18),
            RouteStoryButton(
              label: '여행 영상 만들기',
              icon: Icons.play_circle_outline,
              onPressed: () =>
                  _comingSoon(context, '여행 영상 생성은 다음 단계에서 연결됩니다.'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () =>
                  _comingSoon(context, '공유 페이지는 서버 연결 후 제공됩니다.'),
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
  }

  List<TripPhoto> _photosFor(Trip trip, Stop stop) =>
      trip.photos.where((photo) => stop.photoIds.contains(photo.id)).toList();
  void _comingSoon(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _refresh(WidgetRef ref) {
    ref.invalidate(tripDetailProvider(trip.id));
    ref.invalidate(recentTripsProvider);
  }

  Future<void> _openMenu(
    BuildContext context,
    WidgetRef ref,
    Trip current,
    Stop stop,
    int index,
  ) async {
    final hasNext = index + 1 < current.stops.length;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetAction(
                icon: Icons.edit_outlined,
                label: '이름 수정',
                onTap: () => Navigator.pop(sheetContext, 'rename'),
              ),
              if (hasNext)
                _SheetAction(
                  icon: Icons.merge_type,
                  label: '다음 장소와 병합',
                  onTap: () => Navigator.pop(sheetContext, 'merge'),
                ),
              _SheetAction(
                icon: Icons.visibility_off_outlined,
                label: '이 장소 제외',
                onTap: () => Navigator.pop(sheetContext, 'exclude'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final service = ref.read(stopServiceProvider);
    switch (action) {
      case 'rename':
        final name = await _askName(context, stop.placeName);
        if (name == null) return;
        await service.rename(trip.id, stop.id, name);
      case 'merge':
        await service.mergeWithNext(trip.id, stop.id);
      case 'exclude':
        await service.exclude(trip.id, stop.id);
    }
    _refresh(ref);
  }

  Future<String?> _askName(BuildContext context, String current) =>
      _askText(context, '장소 이름', current, '어떤 곳이었나요?');

  Future<String?> _askText(
    BuildContext context,
    String title,
    String current,
    String hint,
  ) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends ConsumerWidget {
  const _EmptyTimeline({required this.trip});
  final Trip trip;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (trip.isDemo) return const Text('기록된 장소가 아직 없어요.');
    final style = Theme.of(context).textTheme.bodyMedium;
    return switch (trip.stopAnalysisStatus) {
      StopAnalysisStatus.pending => Text('장소를 정리하고 있어요.', style: style),
      StopAnalysisStatus.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('장소를 정리하지 못했어요. 여행 기록은 그대로 안전해요.', style: style),
          TextButton(
            onPressed: () async {
              await ref.read(stopServiceProvider).analyze(trip.id);
              ref.invalidate(tripDetailProvider(trip.id));
              ref.invalidate(recentTripsProvider);
            },
            child: const Text('다시 분석'),
          ),
        ],
      ),
      StopAnalysisStatus.completed => Text(
        '오래 머문 장소가 없었어요.',
        style: style,
      ),
    };
  }
}

class _RestoreExcluded extends ConsumerWidget {
  const _RestoreExcluded({required this.trip, required this.onChanged});
  final Trip trip;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () async {
        final service = ref.read(stopServiceProvider);
        for (final stop in trip.excludedStops) {
          await service.restore(trip.id, stop.id);
        }
        onChanged();
      },
      child: Text('제외한 장소 ${trip.excludedStops.length}곳 되돌리기'),
    ),
  );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, size: 20, color: AppTheme.forest),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    onTap: onTap,
  );
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

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _dwellText(Duration d) {
  final hours = d.inHours, minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '$minutes분';
  return minutes == 0 ? '$hours시간' : '$hours시간 $minutes분';
}

/// Timeline entry for a real (GPS-derived or marker-derived) visit.
class _VisitStory extends StatelessWidget {
  const _VisitStory({
    required this.stop,
    required this.order,
    required this.isLast,
    required this.onMenu,
    required this.photos,
    required this.onPhotoTap,
  });
  final Stop stop;
  final int order;
  final bool isLast;
  final VoidCallback onMenu;
  final List<TripPhoto> photos;
  final void Function(TripPhoto photo) onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final dwell = stop.dwell;
    final hasStay = dwell != null && dwell > Duration.zero;
    final isMarkerOnly = stop.source == StopSource.manual;
    final name = stop.placeName.isEmpty ? '방문 장소 $order' : stop.placeName;
    final detail = hasStay
        ? '${_clock(stop.arrivalTime)} 도착 · ${_clock(stop.departureTime!)} 출발 · ${_dwellText(dwell)} 체류'
        : '${_clock(stop.arrivalTime)} 기록';
    const muted = TextStyle(fontSize: 12, color: Color(0xFF68665F));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 58, child: Text(_clock(stop.arrivalTime), style: muted)),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      InkResponse(
                        onTap: onMenu,
                        radius: 18,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: Color(0xFF68665F),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(detail, style: muted),
                  if (isMarkerOnly || stop.markerIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.bookmark_outline,
                          size: 13,
                          color: AppTheme.forest,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '직접 기억한 장소',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.forest,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    PhotoStrip(photos: photos, onTap: onPhotoTap),
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
                  if (stop.memo != null && stop.memo!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      stop.memo!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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
                PhotoStrip(photos: photos),
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
