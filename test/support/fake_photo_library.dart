import 'dart:typed_data';

import 'package:route_story/core/services/photo_library_service.dart';
import 'package:route_story/features/trips/domain/entities/photo_metadata.dart';

/// 1x1 transparent PNG.
final Uint8List tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakePhotoLibrary implements PhotoLibraryService {
  FakePhotoLibrary({
    this.access = PhotoAccess.full,
    this.afterRequest,
    List<PhotoMetadata>? photos,
  }) : photos = photos ?? [];

  PhotoAccess access;

  /// Access after the user answers a permission dialog.
  PhotoAccess? afterRequest;
  List<PhotoMetadata> photos;
  List<PhotoMetadata> picked = [];
  bool failOnFind = false;
  var findCalls = 0;
  var requestCalls = 0;
  DateTime? lastFrom, lastTo;
  final deleted = <String>{};

  @override
  Future<PhotoAccess> currentAccess() async => access;

  @override
  Future<PhotoAccess> requestAccess() async {
    requestCalls++;
    if (afterRequest != null) access = afterRequest!;
    return access;
  }

  @override
  Future<List<PhotoMetadata>> findPhotos(DateTime from, DateTime to) async {
    findCalls++;
    lastFrom = from;
    lastTo = to;
    if (failOnFind) throw StateError('MediaStore unavailable');
    return [
      for (final p in photos)
        if (!deleted.contains(p.assetId) &&
            (p.takenAt == null ||
                (!p.takenAt!.isBefore(from) && !p.takenAt!.isAfter(to))))
          p,
    ];
  }

  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 600}) async =>
      deleted.contains(assetId) ? null : tinyPng;

  @override
  Future<void> manageLimitedSelection() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<PhotoMetadata>> pickPhotos() async => picked;
}
