import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/trip_image.dart';
import '../application/trip_providers.dart';
import '../domain/entities/trip.dart';
import '../domain/entities/trip_photo.dart';
import '../domain/services/trip_timeline_builder.dart';

/// Shows one trip photo. A missing, deleted or unreadable photo shows a quiet
/// placeholder instead of failing. Library photos are loaded as thumbnails of
/// [size] px, never as originals.
class TripPhotoImage extends ConsumerWidget {
  const TripPhotoImage({
    super.key,
    required this.photo,
    this.fit = BoxFit.cover,
    this.size = 600,
  });
  final TripPhoto photo;
  final BoxFit fit;
  final int size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetId = photo.assetId;
    if (assetId != null) {
      return ref
          .watch(photoThumbnailProvider((assetId, size)))
          .when(
            data: (bytes) => bytes == null
                ? const _MissingPhoto()
                : Image.memory(
                    bytes,
                    fit: fit,
                    width: double.infinity,
                    height: double.infinity,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const _MissingPhoto(),
                  ),
            loading: () => const TripImage(path: null),
            error: (_, _) => const _MissingPhoto(),
          );
    }
    if (photo.localPath.isEmpty) return const TripImage(path: null);
    if (photo.localPath.startsWith('assets/')) {
      return TripImage(path: photo.localPath, fit: fit);
    }
    return Image.file(
      File(photo.localPath),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: size,
      errorBuilder: (_, _, _) => const _MissingPhoto(),
    );
  }
}

class _MissingPhoto extends StatelessWidget {
  const _MissingPhoto();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppTheme.sand,
    child: Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 20,
        color: Color(0xFF68665F),
      ),
    ),
  );
}

/// The trip's cover photo (chosen by the user, else picked automatically), or
/// the plain placeholder.
class TripCoverImage extends StatelessWidget {
  const TripCoverImage({super.key, required this.trip, this.size = 900});
  final Trip trip;
  final int size;
  @override
  Widget build(BuildContext context) {
    final photo = TripCoverSelector.select(trip);
    return photo == null
        ? const TripImage(path: null)
        : TripPhotoImage(photo: photo, size: size);
  }
}

/// Photos of one stop: a single wide photo, or a cover with previews. With
/// more than four photos the rest is behind "show all".
class PhotoStrip extends StatefulWidget {
  const PhotoStrip({super.key, required this.photos, this.onTap});
  final List<TripPhoto> photos;
  final void Function(TripPhoto photo)? onTap;

  @override
  State<PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<PhotoStrip> {
  static const _previews = 3;
  var _expanded = false;

  Widget _tile(TripPhoto photo, {int size = 300, Widget? overlay}) =>
      GestureDetector(
        onTap: widget.onTap == null ? null : () => widget.onTap!(photo),
        child: Stack(
          fit: StackFit.expand,
          children: [TripPhotoImage(photo: photo, size: size), ?overlay],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    if (photos.isEmpty) return const SizedBox.shrink();
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: photos.length == 1 ? 16 / 8 : 16 / 9,
        child: _tile(photos.first, size: 800),
      ),
    );
    if (photos.length == 1) return cover;
    final rest = photos.skip(1).toList();
    final shown = rest.take(_previews).toList();
    final hidden = rest.skip(_previews).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cover,
        const SizedBox(height: 6),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final entry in shown.indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: entry.$1 == 2 ? 0 : 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _tile(entry.$2),
                    ),
                  ),
                ),
              for (var i = shown.length; i < _previews; i++) const Spacer(),
            ],
          ),
        ),
        if (hidden.isNotEmpty && !_expanded)
          TextButton(
            onPressed: () => setState(() => _expanded = true),
            child: Text('사진 ${hidden.length}장 더 보기'),
          ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          // Not a lazy grid: the stop story sits inside an IntrinsicHeight.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final photo in hidden)
                SizedBox(
                  width: 84,
                  height: 84,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _tile(photo, size: 240),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: () => setState(() => _expanded = false),
            child: const Text('접기'),
          ),
        ],
      ],
    );
  }
}

/// A small row of photos (route photos, photos to check). Built lazily.
class PhotoThumbRow extends StatelessWidget {
  const PhotoThumbRow({super.key, required this.photos, required this.onTap});
  final List<TripPhoto> photos;
  final void Function(TripPhoto photo) onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 76,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: photos.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => onTap(photos[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 76,
            child: TripPhotoImage(photo: photos[i], size: 240),
          ),
        ),
      ),
    ),
  );
}
