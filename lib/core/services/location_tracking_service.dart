import '../../features/trips/domain/entities/gps_point.dart';

enum LocationReadiness { ready, serviceDisabled, denied, deniedForever }

abstract interface class LocationTrackingService {
  Future<LocationReadiness> ensureReady();
  Future<void> openAppSettings();
  Stream<GpsPoint> watchPoints();
  Future<void> start();
  Future<void> stop();
}
