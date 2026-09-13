class ManualMarker {
  const ManualMarker({
    required this.id,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.memo,
  });
  final String id, tripId;
  final double latitude, longitude;
  final DateTime timestamp;
  final String? memo;
}
