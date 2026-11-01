class StopCandidate {
  const StopCandidate({
    required this.latitude,
    required this.longitude,
    required this.arrivalTime,
    required this.departureTime,
    required this.pointCount,
  });
  final double latitude, longitude;
  final DateTime arrivalTime, departureTime;
  final int pointCount;
  Duration get dwell => departureTime.difference(arrivalTime);
}
