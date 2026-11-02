/// What the photo library tells us about one photo. No pixels.
class PhotoMetadata {
  const PhotoMetadata({
    this.assetId,
    this.localPath,
    this.takenAt,
    this.latitude,
    this.longitude,
    this.width,
    this.height,
  });

  /// Stable OS photo library id, when the photo came from the library.
  final String? assetId;

  /// File path for photos chosen with the picker fallback (may not persist).
  final String? localPath;

  /// Null when the capture time is unknown or unreliable.
  final DateTime? takenAt;
  final double? latitude, longitude;
  final int? width, height;

  bool get hasLocation => latitude != null && longitude != null;

  /// Identity used to recognise the same photo across re-matching runs.
  String get key => assetId != null ? 'a:$assetId' : 'p:$localPath';
}
