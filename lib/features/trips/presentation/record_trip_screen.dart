import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_preview.dart';
import '../../../core/widgets/route_story_button.dart';
import '../application/trip_recording_controller.dart';
import 'trip_result_screen.dart';

class RecordTripScreen extends ConsumerWidget {
  const RecordTripScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripRecordingControllerProvider);
    final controller = ref.read(tripRecordingControllerProvider.notifier);
    final trip = state.trip;
    final time =
        '${state.elapsed.inHours.toString().padLeft(2, '0')}:${(state.elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(state.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
                const Spacer(),
                const Text(
                  'RECORDING',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.forest,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              '여행을 기록 중이에요',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              trip == null
                  ? '위치를 준비하고 있어요.'
                  : '${trip.startTime.month}월 ${trip.startTime.day}일 · ${trip.startTime.hour.toString().padLeft(2, '0')}:${trip.startTime.minute.toString().padLeft(2, '0')} 시작',
            ),
            const SizedBox(height: 30),
            MapPreview(
              points: state.points,
              currentPoint: state.points.isEmpty ? null : state.points.last,
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: AppTheme.sand,
              ),
              padding: const EdgeInsets.all(22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Metric(value: time, label: '경과 시간'),
                  _Metric(
                    value: (state.totalDistance / 1000).toStringAsFixed(1),
                    label: '이동 거리 km',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: state.phase == RecordingPhase.recording
                  ? () async {
                      await controller.rememberCurrentPlace();
                      if (context.mounted &&
                          ref.read(tripRecordingControllerProvider).message !=
                              null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ref
                                  .read(tripRecordingControllerProvider)
                                  .message!,
                            ),
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('지금 장소 기억하기'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: AppTheme.forest,
                side: const BorderSide(color: AppTheme.forest),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(height: 12),
            RouteStoryButton(
              label: '여행 종료',
              icon: Icons.stop_circle_outlined,
              onPressed: state.phase == RecordingPhase.recording
                  ? () => _confirmFinish(context, controller)
                  : () {},
            ),
            if (state.message != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  state.message!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF68665F),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmFinish(
    BuildContext context,
    TripRecordingController controller,
  ) async {
    final finish = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('여행 기록을 종료할까요?'),
        content: const Text('기록된 경로와 거리가 저장됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('계속 기록'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('여행 종료'),
          ),
        ],
      ),
    );
    if (finish != true || !context.mounted) {
      return;
    }
    final trip = await controller.finish();
    if (trip != null && context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripResultScreen(trip: trip)),
      );
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF68665F)),
      ),
    ],
  );
}




