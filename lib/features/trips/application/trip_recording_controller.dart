import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/location_tracking_service.dart';
import '../domain/entities/gps_point.dart';
import '../domain/entities/manual_marker.dart';
import '../domain/entities/trip.dart';
import '../domain/services/distance_calculator.dart';
import 'trip_providers.dart';

enum RecordingPhase {
  idle,
  requestingPermission,
  recording,
  stopping,
  completed,
  error,
}

class TripRecordingState {
  const TripRecordingState({
    this.phase = RecordingPhase.idle,
    this.trip,
    this.points = const [],
    this.elapsed = Duration.zero,
    this.totalDistance = 0,
    this.message,
  });
  final RecordingPhase phase;
  final Trip? trip;
  final List<GpsPoint> points;
  final Duration elapsed;
  final double totalDistance;
  final String? message;
  TripRecordingState copyWith({
    RecordingPhase? phase,
    Trip? trip,
    List<GpsPoint>? points,
    Duration? elapsed,
    double? totalDistance,
    String? message,
  }) => TripRecordingState(
    phase: phase ?? this.phase,
    trip: trip ?? this.trip,
    points: points ?? this.points,
    elapsed: elapsed ?? this.elapsed,
    totalDistance: totalDistance ?? this.totalDistance,
    message: message,
  );
}

final tripRecordingControllerProvider =
    NotifierProvider<TripRecordingController, TripRecordingState>(
      TripRecordingController.new,
    );

class TripRecordingController extends Notifier<TripRecordingState> {
  StreamSubscription<GpsPoint>? _subscription;
  Timer? _ticker;
  @override
  TripRecordingState build() {
    ref.onDispose(_dispose);
    Future.microtask(resumeIfNeeded);
    return const TripRecordingState();
  }

  Future<bool> start() async {
    state = state.copyWith(
      phase: RecordingPhase.requestingPermission,
      message: null,
    );
    final readiness = await ref
        .read(locationTrackingServiceProvider)
        .ensureReady();
    if (readiness != LocationReadiness.ready) {
      state = state.copyWith(
        phase: RecordingPhase.error,
        message: _readinessMessage(readiness),
      );
      return false;
    }
    final now = DateTime.now();
    final trip = Trip(
      id: 'trip-${now.millisecondsSinceEpoch}',
      title: '오늘의 여정',
      startTime: now,
      totalDistance: 0,
      status: 'recording',
    );
    await ref.read(tripRepositoryProvider).saveTrip(trip);
    _begin(trip, const [], 0);
    return true;
  }

  Future<void> resumeIfNeeded() async {
    final trip = await ref.read(tripRepositoryProvider).getRecordingTrip();
    if (trip != null) _begin(trip, trip.gpsPoints, trip.totalDistance);
  }

  void _begin(Trip trip, List<GpsPoint> points, double distance) {
    _subscription?.cancel();
    _ticker?.cancel();
    state = TripRecordingState(
      phase: RecordingPhase.recording,
      trip: trip,
      points: points,
      totalDistance: distance,
      elapsed: DateTime.now().difference(trip.startTime),
    );
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => state = state.copyWith(
        elapsed: DateTime.now().difference(trip.startTime),
      ),
    );
    _subscription = ref
        .read(locationTrackingServiceProvider)
        .watchPoints()
        .listen(
          _onPoint,
          onError: (_) => state = state.copyWith(
            phase: RecordingPhase.error,
            message: '위치 신호를 받을 수 없어요. GPS 설정을 확인해주세요.',
          ),
        );
  }

  Future<void> _onPoint(GpsPoint point) async {
    final previous = state.points.isEmpty ? null : state.points.last;
    if (!DistanceCalculator.isPlausible(previous, point) ||
        state.trip == null) {
      return;
    }
    final gained = previous == null
        ? 0
        : DistanceCalculator.metersBetween(previous, point);
    final points = [...state.points, point];
    final total = state.totalDistance + gained;
    final trip = state.trip!;
    await ref.read(tripRepositoryProvider).saveGpsPoint(trip.id, point);
    state = state.copyWith(points: points, totalDistance: total);
  }

  Future<void> rememberCurrentPlace() async {
    final trip = state.trip;
    final point = state.points.isEmpty ? null : state.points.last;
    if (trip == null || point == null) {
      state = state.copyWith(message: '현재 위치를 받은 뒤 장소를 기억할 수 있어요.');
      return;
    }
    await ref
        .read(tripRepositoryProvider)
        .saveManualMarker(
          ManualMarker(
            id: 'marker-${DateTime.now().microsecondsSinceEpoch}',
            tripId: trip.id,
            latitude: point.latitude,
            longitude: point.longitude,
            timestamp: DateTime.now(),
          ),
        );
    state = state.copyWith(message: '현재 장소를 기억했어요.');
  }

  Future<Trip?> finish() async {
    final trip = state.trip;
    if (trip == null) return null;
    state = state.copyWith(phase: RecordingPhase.stopping);
    await _subscription?.cancel();
    _subscription = null;
    _ticker?.cancel();
    final completed = Trip(
      id: trip.id,
      title: trip.title,
      startTime: trip.startTime,
      endTime: DateTime.now(),
      totalDistance: state.totalDistance,
      gpsPoints: state.points,
      status: 'completed',
    );
    await ref.read(tripRepositoryProvider).saveTrip(completed);
    // Stop analysis runs after the raw data is saved and never throws; if it
    // fails the trip stays intact and is re-analyzed later.
    await ref.read(stopServiceProvider).analyze(completed.id);
    ref.invalidate(recentTripsProvider);
    state = state.copyWith(phase: RecordingPhase.completed, trip: completed);
    return await ref.read(tripRepositoryProvider).getTrip(completed.id) ??
        completed;
  }

  String _readinessMessage(LocationReadiness value) => switch (value) {
    LocationReadiness.serviceDisabled => 'GPS가 꺼져 있어요. 위치 서비스를 켜주세요.',
    LocationReadiness.deniedForever =>
      '여행을 기록하려면 위치 권한이 필요합니다. 설정에서 권한을 허용해주세요.',
    _ => '여행을 기록하려면 위치 권한이 필요합니다.',
  };
  void _dispose() {
    _subscription?.cancel();
    _ticker?.cancel();
  }
}
