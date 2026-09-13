import 'package:geolocator/geolocator.dart';
import '../../../../core/services/location_tracking_service.dart';
import '../../domain/entities/gps_point.dart';

class GeolocatorLocationTrackingService implements LocationTrackingService {
  static const distanceFilterMeters = 10;
  @override
  Future<LocationReadiness> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadiness.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationReadiness.ready,
      LocationPermission.deniedForever => LocationReadiness.deniedForever,
      _ => LocationReadiness.denied,
    };
  }

  @override
  Future<void> openAppSettings() async => Geolocator.openAppSettings();

  @override
  Stream<GpsPoint> watchPoints() =>
      Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterMeters,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'RouteStory',
            notificationText: '여행을 기록하고 있습니다.',
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).map(
        (position) => GpsPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          timestamp: position.timestamp,
          accuracy: position.accuracy,
          speed: position.speed,
          heading: position.heading,
        ),
      );
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}
