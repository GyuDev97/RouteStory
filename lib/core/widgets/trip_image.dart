import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TripImage extends StatelessWidget {
  const TripImage({super.key, required this.path, this.fit = BoxFit.cover});
  final String? path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return const ColoredBox(
        color: AppTheme.sand,
        child: Center(
          child: Icon(Icons.landscape_outlined, color: AppTheme.forest),
        ),
      );
    }
    return Image.asset(
      path!,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
