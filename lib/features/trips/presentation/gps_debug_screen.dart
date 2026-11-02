import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/entities/trip.dart';
import '../domain/services/distance_formatter.dart';
import '../domain/services/gps_debug_stats.dart';

/// Development-only GPS check. Reachable only in debug builds (the entry point
/// in the result screen is guarded by `kDebugMode`). Read-only.
class GpsDebugScreen extends StatelessWidget {
  const GpsDebugScreen({super.key, required this.trip});
  final Trip trip;

  String _time(DateTime? t) => t == null
      ? '-'
      : '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
  String _span(Duration? d) {
    if (d == null) return '-';
    if (d.inMinutes >= 1) return '${d.inMinutes}분 ${d.inSeconds.remainder(60)}초';
    return '${d.inSeconds}초';
  }

  @override
  Widget build(BuildContext context) {
    final stats = GpsDebugStats.fromPoints(
      trip.gpsPoints,
      stopCount: trip.stops.length,
    );
    final rows = <(String, String)>[
      ('GPS 포인트 수', '${stats.pointCount}'),
      ('최초 기록', _time(stats.firstTime)),
      ('마지막 기록', _time(stats.lastTime)),
      ('최대 기록 간격', _span(stats.maxGap)),
      ('평균 기록 간격', _span(stats.averageInterval)),
      (
        '평균 accuracy',
        stats.averageAccuracy == null
            ? '-'
            : '${stats.averageAccuracy!.toStringAsFixed(1)} m',
      ),
      ('accuracy 50m 초과 포인트', '${stats.overAccuracyCount}'),
      ('추출된 Stop', '${stats.stopCount}'),
      ('저장된 이동거리', formatKilometers(trip.totalDistance)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS 점검 (debug)'),
        backgroundColor: AppTheme.paper,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(trip.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Expanded(child: Text(row.$1)),
                  Text(
                    row.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            '기록 시점에 정확도 50m 초과 포인트는 이미 걸러지므로 저장된 데이터에서는 보통 0입니다. 원본 GPS 데이터는 수정하지 않습니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
