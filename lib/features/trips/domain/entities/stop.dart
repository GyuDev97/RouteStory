class Stop {
  const Stop({
    required this.id,
    required this.placeName,
    required this.latitude,
    required this.longitude,
    required this.arrivalTime,
    this.departureTime,
    this.memo,
    this.photoIds = const [],
  });
  final String id, placeName;
  final double latitude, longitude;
  final DateTime arrivalTime;
  final DateTime? departureTime;
  final String? memo;
  final List<String> photoIds;
}
