import '../entities/trip.dart';

enum ProgressState { waiting, running, done, skipped, failed }

class ProgressStep {
  const ProgressStep(this.label, this.state, {this.note});
  final String label;
  final ProgressState state;
  final String? note;
}

/// Progress of the automatic result creation, read from the statuses that the
/// analysis steps themselves store on the trip. Nothing here is a timer: a
/// step is "running" only because it has not stored a result yet.
class TripProgress {
  const TripProgress(this.steps);
  final List<ProgressStep> steps;

  bool get isRunning =>
      steps.any((s) => s.state == ProgressState.running || s.state == ProgressState.waiting);
  bool get hasFailure => steps.any((s) => s.state == ProgressState.failed);

  /// Nothing left to wait for and nothing failed.
  bool get isComplete => !isRunning && !hasFailure;

  static TripProgress of(Trip trip) {
    final recorded = trip.status == 'completed';
    final stops = switch (trip.stopAnalysisStatus) {
      StopAnalysisStatus.pending => ProgressState.running,
      StopAnalysisStatus.completed => ProgressState.done,
      StopAnalysisStatus.failed => ProgressState.failed,
    };
    final photos = switch (trip.photoMatchStatus) {
      PhotoMatchStatus.pending =>
        stops == ProgressState.running ? ProgressState.waiting : ProgressState.running,
      PhotoMatchStatus.completed || PhotoMatchStatus.limited => ProgressState.done,
      PhotoMatchStatus.noAccess => ProgressState.skipped,
      PhotoMatchStatus.failed => ProgressState.failed,
    };
    bool finished(ProgressState s) => s == ProgressState.done || s == ProgressState.skipped;
    final compose = finished(stops) && finished(photos)
        ? ProgressState.done
        : (stops == ProgressState.failed || photos == ProgressState.failed)
        ? ProgressState.failed
        : ProgressState.waiting;
    return TripProgress([
      ProgressStep('GPS 기록 정리', recorded ? ProgressState.done : ProgressState.running),
      ProgressStep(
        '방문 장소 분석',
        stops,
        note: stops == ProgressState.failed ? '다시 시도할 수 있어요' : null,
      ),
      ProgressStep(
        '사진 연결',
        photos,
        note: switch (trip.photoMatchStatus) {
          PhotoMatchStatus.noAccess => '사진 접근이 필요해요',
          PhotoMatchStatus.limited => '선택한 사진만 사용했어요',
          PhotoMatchStatus.failed => '다시 시도할 수 있어요',
          _ => null,
        },
      ),
      ProgressStep(
        '여행 결과 구성',
        compose,
        note: compose == ProgressState.failed ? '가능한 결과만 보여드려요' : null,
      ),
    ]);
  }
}
