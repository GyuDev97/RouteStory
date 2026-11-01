import 'dart:async';

import '../domain/entities/stop.dart';
import '../domain/entities/trip.dart';
import '../domain/repositories/trip_repository.dart';
import '../domain/services/stop_detection_config.dart';
import '../domain/services/stop_detection_service.dart';
import '../domain/services/stop_editing.dart';
import '../domain/services/stop_reconciler.dart';

enum StopAnalysisOutcome { completed, failed, skipped }

/// Runs stop analysis and user edits for a trip.
///
/// Work on one trip is serialized so an analysis can never overwrite an edit
/// made while it was running, and concurrent analysis requests for the same
/// trip share one run. Only the `stops` table and the analysis status are
/// written; the trip row, GPS points and markers are never modified.
class StopService {
  StopService(
    this._repository, {
    StopDetectionConfig config = const StopDetectionConfig(),
  }) : _config = config,
       _detector = StopDetectionService(config);
  final TripRepository _repository;
  final StopDetectionConfig _config;
  final StopDetectionService _detector;
  final _queues = <String, Future<void>>{};
  final _analyses = <String, Future<StopAnalysisOutcome>>{};

  Future<StopAnalysisOutcome> analyze(String tripId) =>
      _analyses[tripId] ??= _serial(tripId, () => _analyze(tripId)).whenComplete(
        () {
          _analyses.remove(tripId);
        },
      );

  /// Analyzes completed real trips that have not been analyzed successfully.
  Future<bool> analyzePending(Iterable<Trip> trips) async {
    var changed = false;
    for (final trip in trips) {
      if (trip.isDemo ||
          trip.status != 'completed' ||
          trip.stopAnalysisStatus == StopAnalysisStatus.completed) {
        continue;
      }
      await analyze(trip.id);
      changed = true;
    }
    return changed;
  }

  Future<StopAnalysisOutcome> _analyze(String tripId) async {
    try {
      final trip = await _repository.getTrip(tripId);
      if (trip == null || trip.status != 'completed') {
        return StopAnalysisOutcome.skipped;
      }
      final candidates = _detector.detect(trip.gpsPoints);
      final changes = StopReconciler.reconcile(
        tripId: tripId,
        existing: await _repository.getAllStops(tripId),
        candidates: candidates,
        markers: await _repository.getManualMarkers(tripId),
        config: _config,
      );
      await _repository.saveStopChanges(
        tripId,
        upserts: changes.upserts,
        deleteIds: changes.deleteIds,
        status: StopAnalysisStatus.completed,
      );
      return StopAnalysisOutcome.completed;
    } catch (_) {
      try {
        await _repository.setStopAnalysisStatus(
          tripId,
          StopAnalysisStatus.failed,
        );
      } catch (_) {}
      return StopAnalysisOutcome.failed;
    }
  }

  Future<void> rename(String tripId, String stopId, String name) =>
      _edit(tripId, stopId, StopEditing.rename, name);

  Future<void> exclude(String tripId, String stopId) =>
      _edit(tripId, stopId, (stop, _) => StopEditing.exclude(stop), null);

  Future<void> restore(String tripId, String stopId) =>
      _edit(tripId, stopId, (stop, _) => StopEditing.restore(stop), null);

  /// Merges [stopId] with the next visible stop in time order.
  /// Returns false when there is no next stop.
  Future<bool> mergeWithNext(String tripId, String stopId) =>
      _serial(tripId, () async {
        final visible = (await _repository.getAllStops(tripId))
            .where((s) => !s.isExcluded)
            .toList()
          ..sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
        final index = visible.indexWhere((s) => s.id == stopId);
        if (index < 0 || index + 1 >= visible.length) return false;
        final merged = StopEditing.merge(visible[index], visible[index + 1]);
        final removed = [visible[index], visible[index + 1]]
            .map((s) => s.id)
            .where((id) => id != merged.id)
            .toList();
        await _repository.saveStopChanges(
          tripId,
          upserts: [merged],
          deleteIds: removed,
        );
        return true;
      });

  Future<void> _edit(
    String tripId,
    String stopId,
    Stop Function(Stop, String) edit,
    String? argument,
  ) => _serial(tripId, () async {
    final stop = (await _repository.getAllStops(
      tripId,
    )).where((s) => s.id == stopId).firstOrNull;
    if (stop == null) return;
    await _repository.saveStopChanges(
      tripId,
      upserts: [edit(stop, argument ?? '')],
    );
  });

  Future<T> _serial<T>(String tripId, Future<T> Function() action) {
    final previous = _queues[tripId] ?? Future<void>.value();
    final completer = Completer<T>();
    final next = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    _queues[tripId] = next;
    next.whenComplete(() {
      if (identical(_queues[tripId], next)) _queues.remove(tripId);
    });
    return completer.future;
  }
}
