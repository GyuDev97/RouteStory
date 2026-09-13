class TripPhoto {
  const TripPhoto({
    required this.id,
    required this.localPath,
    this.latitude,
    this.longitude,
    required this.takenAt,
    this.stopId,
  });
  final String id, localPath;
  final double? latitude, longitude;
  final DateTime takenAt;
  final String? stopId;
}
