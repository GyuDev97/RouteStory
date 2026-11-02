import 'dart:typed_data';

import '../../features/trips/domain/entities/photo_metadata.dart';

/// How much of the user's photo library the app may read.
enum PhotoAccess {
  /// Whole library (Android: READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE).
  full,

  /// Only photos the user picked for the app (Android 14+ partial access).
  limited,
  denied,
}

/// Read-only access to the user's photos. Implementations never modify,
/// delete or upload a photo.
abstract interface class PhotoLibraryService {
  /// Current access without showing any permission dialog.
  Future<PhotoAccess> currentAccess();

  /// Shows the system permission dialog if needed.
  Future<PhotoAccess> requestAccess();

  /// Metadata of photos created in [from]..[to]. Only that time window is
  /// queried; the library is never scanned as a whole.
  Future<List<PhotoMetadata>> findPhotos(DateTime from, DateTime to);

  /// Small preview, or null if the photo no longer exists or is not readable.
  Future<Uint8List?> thumbnail(String assetId, {int size = 600});

  /// Lets the user choose more photos when access is limited.
  Future<void> manageLimitedSelection();

  Future<void> openSettings();

  /// Fallback without any permission: the system photo picker.
  Future<List<PhotoMetadata>> pickPhotos();
}
