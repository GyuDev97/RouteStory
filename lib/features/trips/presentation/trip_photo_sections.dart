import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../application/trip_providers.dart';
import '../domain/entities/stop.dart';
import '../domain/entities/trip.dart';
import '../domain/entities/trip_photo.dart';
import '../domain/entities/trip_timeline.dart';
import '../domain/services/trip_progress.dart';
import 'trip_photo_widgets.dart';

void _refresh(WidgetRef ref, String tripId) {
  ref.invalidate(tripDetailProvider(tripId));
  ref.invalidate(recentTripsProvider);
}

String _stopLabel(Stop stop, int index) {
  final time =
      '${stop.arrivalTime.hour.toString().padLeft(2, '0')}:${stop.arrivalTime.minute.toString().padLeft(2, '0')}';
  return '${stop.placeName.isEmpty ? '방문 장소 ${index + 1}' : stop.placeName} · $time';
}

/// Photo actions: set cover, move, detach, exclude. Original files are never
/// changed; only the app's own record of the photo is edited.
Future<void> showPhotoActions(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
  TripPhoto photo,
) async {
  final stopIds = trip.stops.map((s) => s.id).toSet();
  final onStop = photo.stopId != null && stopIds.contains(photo.stopId);
  final stop = onStop
      ? trip.stops.firstWhere((s) => s.id == photo.stopId)
      : null;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppTheme.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onStop && stop!.coverPhotoId != photo.id)
              _Action(Icons.star_outline, '대표 사진으로', () => Navigator.pop(sheet, 'cover')),
            if (trip.stops.isNotEmpty)
              _Action(
                Icons.swap_horiz,
                onStop ? '다른 장소로 이동' : '장소에 연결',
                () => Navigator.pop(sheet, 'move'),
              ),
            if (onStop)
              _Action(Icons.link_off, '장소에서 분리', () => Navigator.pop(sheet, 'detach')),
            _Action(
              Icons.photo_outlined,
              '여행 대표 사진으로',
              () => Navigator.pop(sheet, 'tripCover'),
            ),
            _Action(
              Icons.visibility_off_outlined,
              '이 사진 제외',
              () => Navigator.pop(sheet, 'exclude'),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final service = ref.read(photoMatchingServiceProvider);
  switch (action) {
    case 'cover':
      await service.setCover(trip.id, stop!.id, photo.id);
    case 'tripCover':
      await ref.read(tripServiceProvider).setCoverPhoto(trip.id, photo.id);
    case 'detach':
      await service.detach(trip.id, photo.id);
    case 'exclude':
      await service.exclude(trip.id, photo.id);
    case 'move':
      final target = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppTheme.paper,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
            children: [
              for (final entry in trip.stops.indexed)
                if (entry.$2.id != photo.stopId)
                  _Action(
                    Icons.place_outlined,
                    _stopLabel(entry.$2, entry.$1),
                    () => Navigator.pop(sheet, entry.$2.id),
                  ),
            ],
          ),
        ),
      );
      if (target == null) return;
      await service.moveToStop(trip.id, photo.id, target);
  }
  _refresh(ref, trip.id);
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap);
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

/// Photos that are not on a stop (route photos, photos to check), photo
/// access status and re-run actions.
class PhotoSections extends ConsumerWidget {
  const PhotoSections({super.key, required this.trip, required this.timeline});
  final Trip trip;
  final TripTimeline timeline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = timeline.routePhotos;
    final toCheck = timeline.unclassifiedPhotos;
    final excluded = timeline.excludedPhotos;
    void open(TripPhoto p) => showPhotoActions(context, ref, trip, p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (route.isNotEmpty) ...[
          const SizedBox(height: 30),
          const _Heading('이동 중 찍은 사진'),
          const SizedBox(height: 10),
          PhotoThumbRow(photos: route, onTap: open),
        ],
        if (toCheck.isNotEmpty) ...[
          const SizedBox(height: 30),
          const _Heading('확인이 필요한 사진'),
          const SizedBox(height: 4),
          Text(
            '어느 장소인지 확실하지 않아 두었어요. 눌러서 장소에 연결할 수 있어요.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          PhotoThumbRow(photos: toCheck, onTap: open),
        ],
        if (excluded.isNotEmpty)
          TextButton(
            onPressed: () async {
              final service = ref.read(photoMatchingServiceProvider);
              for (final p in excluded) {
                await service.restore(trip.id, p.id);
              }
              _refresh(ref, trip.id);
            },
            child: Text('제외한 사진 ${excluded.length}장 되돌리기'),
          ),
        const SizedBox(height: 18),
        _PhotoStatus(trip: trip, hasPhotos: timeline.activePhotoCount > 0),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
}

class _PhotoStatus extends ConsumerWidget {
  const _PhotoStatus({required this.trip, required this.hasPhotos});
  final Trip trip;
  final bool hasPhotos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(photoMatchingServiceProvider);
    final style = Theme.of(context).textTheme.bodyMedium;
    Future<void> run(Future<Object?> Function() action) async {
      await action();
      _refresh(ref, trip.id);
    }

    Widget button(String label, Future<Object?> Function() action) =>
        TextButton(onPressed: () => run(action), child: Text(label));

    final pick = button('사진 직접 선택', () => service.addPickedPhotos(trip.id));
    switch (trip.photoMatchStatus) {
      case PhotoMatchStatus.pending:
        return Text('여행 사진을 찾고 있어요.', style: style);
      case PhotoMatchStatus.noAccess:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '사진 접근이 허용되지 않아 여행 중 찍은 사진을 자동으로 찾지 못했어요. 허용하면 시간대에 맞는 사진만 확인합니다.',
              style: style,
            ),
            Wrap(
              children: [
                button(
                  '사진 접근 허용',
                  () => service.match(trip.id, requestPermission: true),
                ),
                pick,
                button('설정 열기', service.openSettings),
              ],
            ),
          ],
        );
      case PhotoMatchStatus.limited:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('선택한 사진에서만 찾았어요. 더 넣고 싶은 사진이 있나요?', style: style),
            Wrap(
              children: [
                button('사진 더 선택', () async {
                  await service.manageLimitedSelection();
                  return service.match(trip.id);
                }),
                button('다시 찾기', () => service.match(trip.id)),
              ],
            ),
          ],
        );
      case PhotoMatchStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('사진을 정리하지 못했어요. 여행 기록은 그대로 안전해요.', style: style),
            Wrap(
              children: [
                button('다시 시도', () => service.match(trip.id, requestPermission: true)),
                pick,
              ],
            ),
          ],
        );
      case PhotoMatchStatus.completed:
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!hasPhotos) Text('이 시간대에 찍은 사진을 찾지 못했어요.', style: style),
            button('사진 다시 찾기', () => service.match(trip.id)),
            pick,
          ],
        );
    }
  }
}

/// Live progress of the automatic result creation. Each step shows the state
/// the analysis step itself stored; failures offer a retry. Hidden once
/// everything has finished without failure.
class ProgressBanner extends ConsumerWidget {
  const ProgressBanner({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = TripProgress.of(trip);
    if (progress.isComplete) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.sand,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            progress.hasFailure ? '일부 단계를 마치지 못했어요' : '여행을 정리하고 있어요',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (final step in progress.steps) _StepRow(step: step),
          if (progress.hasFailure)
            TextButton(
              onPressed: () async {
                await ref.read(stopServiceProvider).analyze(trip.id);
                await ref
                    .read(photoMatchingServiceProvider)
                    .match(trip.id, requestPermission: true);
                _refresh(ref, trip.id);
              },
              child: const Text('다시 시도'),
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});
  final ProgressStep step;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.state) {
      ProgressState.done => (Icons.check_circle_outline, AppTheme.forest),
      ProgressState.failed => (Icons.error_outline, Colors.red.shade700),
      ProgressState.skipped => (Icons.remove_circle_outline, const Color(0xFF68665F)),
      _ => (Icons.radio_button_unchecked, const Color(0xFF68665F)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (step.state == ProgressState.running)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Text(step.label, style: const TextStyle(fontSize: 13)),
          if (step.note != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                step.note!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF68665F)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lets the user choose the trip cover from the trip's own photos.
Future<void> showCoverPicker(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
) async {
  final photos = trip.activePhotos;
  if (photos.isEmpty) return;
  final choice = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(sheet).size.height * .6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 6),
              child: Text(
                '여행 대표 사진',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            if (trip.coverPhotoId != null)
              TextButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: const Text('자동으로 고르기'),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => Navigator.pop(sheet, photos[i].id),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: TripPhotoImage(photo: photos[i], size: 240),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return;
  final service = ref.read(tripServiceProvider);
  if (choice is String) {
    await service.setCoverPhoto(trip.id, choice);
  } else {
    await service.clearCoverPhoto(trip.id);
  }
  _refresh(ref, trip.id);
}