import 'package:flutter/material.dart';
import '../../features/trips/domain/entities/gps_point.dart';
import '../theme/app_theme.dart';

/// SDK-independent route surface. Swap this adapter for Google/Naver/Kakao maps later.
class MapPreview extends StatelessWidget {
  const MapPreview({
    super.key,
    this.compact = false,
    this.points = const [],
    this.currentPoint,
  });
  final bool compact;
  final List<GpsPoint> points;
  final GpsPoint? currentPoint;
  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 136 : 210,
    decoration: BoxDecoration(
      color: AppTheme.sand,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _RoutePainter(points, currentPoint)),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: _MapTag(hasRoute: points.isNotEmpty),
        ),
        if (currentPoint != null)
          const Positioned(
            bottom: 17,
            right: 17,
            child: Icon(Icons.near_me_rounded, color: AppTheme.forest),
          ),
      ],
    ),
  );
}

class _MapTag extends StatelessWidget {
  const _MapTag({required this.hasRoute});
  final bool hasRoute;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.paper,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Text(
        hasRoute ? 'RECORDED ROUTE' : 'ROUTE PREVIEW',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AppTheme.forest,
        ),
      ),
    ),
  );
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.points, this.currentPoint);
  final List<GpsPoint> points;
  final GpsPoint? currentPoint;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFD8D2C5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var y = 22.0; y < size.height; y += 38) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 12), grid);
    }
    if (points.length < 2) return;
    final minLat = points
        .map((point) => point.latitude)
        .reduce((a, b) => a < b ? a : b);
    final maxLat = points
        .map((point) => point.latitude)
        .reduce((a, b) => a > b ? a : b);
    final minLng = points
        .map((point) => point.longitude)
        .reduce((a, b) => a < b ? a : b);
    final maxLng = points
        .map((point) => point.longitude)
        .reduce((a, b) => a > b ? a : b);
    Offset project(GpsPoint point) {
      const pad = 20.0;
      final width = size.width - pad * 2;
      final height = size.height - pad * 2;
      final x = maxLng == minLng
          ? width / 2
          : (point.longitude - minLng) / (maxLng - minLng) * width;
      final y = maxLat == minLat
          ? height / 2
          : (maxLat - point.latitude) / (maxLat - minLat) * height;
      return Offset(x + pad, y + pad);
    }

    final path = Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final point in points.skip(1)) {
      final offset = project(point);
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final start = project(points.first);
    canvas.drawCircle(start, 5, Paint()..color = AppTheme.paper);
    canvas.drawCircle(start, 3, Paint()..color = AppTheme.forest);
    final end = project(currentPoint ?? points.last);
    canvas.drawCircle(end, 7, Paint()..color = const Color(0xFFCE7053));
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.currentPoint != currentPoint;
}
