import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../../core/services/photo_library_service.dart';
import '../../domain/entities/photo_metadata.dart';

/// Android photo access.
///
/// * Android 13+: READ_MEDIA_IMAGES; Android 14+: the user may instead share
///   only selected photos (READ_MEDIA_VISUAL_USER_SELECTED) -> [PhotoAccess.limited].
/// * Android 12 and below: READ_EXTERNAL_STORAGE.
/// * ACCESS_MEDIA_LOCATION is requested so photo GPS is not redacted.
/// * Queries are restricted to the trip's time window.
class PhotoManagerLibraryService implements PhotoLibraryService {
  static const _option = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: true,
    ),
  );

  PhotoAccess _map(PermissionState state) => switch (state) {
    PermissionState.authorized => PhotoAccess.full,
    PermissionState.limited => PhotoAccess.limited,
    _ => PhotoAccess.denied,
  };

  @override
  Future<PhotoAccess> currentAccess() async =>
      _map(await PhotoManager.getPermissionState(requestOption: _option));

  @override
  Future<PhotoAccess> requestAccess() async =>
      _map(await PhotoManager.requestPermissionExtend(requestOption: _option));

  @override
  Future<List<PhotoMetadata>> findPhotos(DateTime from, DateTime to) async {
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(),
        createTimeCond: DateTimeCond(min: from, max: to),
      ),
    );
    if (paths.isEmpty) return const [];
    final all = paths.first;
    final count = await all.assetCountAsync;
    final assets = await all.getAssetListRange(start: 0, end: count);
    final result = <PhotoMetadata>[];
    for (final asset in assets) {
      double? latitude, longitude;
      try {
        final latLng = await asset.latlngAsync();
        if (latLng != null &&
            !(latLng.latitude == 0 && latLng.longitude == 0)) {
          latitude = latLng.latitude;
          longitude = latLng.longitude;
        }
      } catch (_) {
        // Location unavailable (no ACCESS_MEDIA_LOCATION): time-only photo.
      }
      result.add(
        PhotoMetadata(
          assetId: asset.id,
          takenAt: asset.createDateTime,
          latitude: latitude,
          longitude: longitude,
          width: asset.width > 0 ? asset.width : null,
          height: asset.height > 0 ? asset.height : null,
        ),
      );
    }
    return result;
  }

  @override
  Future<Uint8List?> thumbnail(String assetId, {int size = 600}) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) return null;
    return asset.thumbnailDataWithSize(ThumbnailSize.square(size));
  }

  @override
  Future<void> manageLimitedSelection() =>
      PhotoManager.presentLimited(type: RequestType.image);

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<List<PhotoMetadata>> pickPhotos() async {
    final files = await ImagePicker().pickMultiImage();
    final result = <PhotoMetadata>[];
    for (final file in files) {
      result.add(await _readExif(file.path));
    }
    return result;
  }

  /// Capture time and GPS from the EXIF block. Photo-picker copies may have
  /// the location stripped by Android, in which case only time is available.
  Future<PhotoMetadata> _readExif(String path) async {
    try {
      final tags = await readExifFromBytes(await File(path).readAsBytes());
      final taken = _parseDate(
        (tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'])?.printable,
      );
      final lat = _parseGps(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']);
      final lng = _parseGps(
        tags['GPS GPSLongitude'],
        tags['GPS GPSLongitudeRef'],
      );
      return PhotoMetadata(
        localPath: path,
        takenAt: taken,
        latitude: lat != null && lng != null ? lat : null,
        longitude: lat != null && lng != null ? lng : null,
      );
    } catch (_) {
      return PhotoMetadata(localPath: path);
    }
  }

  DateTime? _parseDate(String? text) {
    // "2026:09:01 10:20:30"
    final m = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(text ?? '');
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    if (v[0] < 1990) return null;
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  double? _parseGps(IfdTag? value, IfdTag? ref) {
    final ratios = value?.values.toList();
    if (ratios == null || ratios.length < 3) return null;
    double n(Object r) => r is Ratio ? r.toDouble() : (r as num).toDouble();
    final degrees = n(ratios[0]) + n(ratios[1]) / 60 + n(ratios[2]) / 3600;
    final sign = (ref?.printable == 'S' || ref?.printable == 'W') ? -1 : 1;
    return degrees == 0 ? null : sign * degrees;
  }
}
