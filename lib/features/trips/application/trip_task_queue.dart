import 'dart:async';

/// Runs work on one trip one task at a time, so analyses and user edits can
/// never overwrite each other. Different trips run independently.
class TripTaskQueue {
  final _queues = <String, Future<void>>{};

  Future<T> run<T>(String tripId, Future<T> Function() action) {
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
