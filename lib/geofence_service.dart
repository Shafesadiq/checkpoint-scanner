import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'models.dart';

class GeofenceService {
  static StreamSubscription<Position>? _positionSub;
  static bool _monitoring = false;
  static final Map<String, DateTime> _cooldowns = {};

  static bool get isMonitoring => _monitoring;

  // Default geofence zones — replace with your actual checkpoint coordinates
  static final List<GeofenceZone> _zones = [
    const GeofenceZone(
      checkpointId: 'CP-001',
      name: 'Building A Lobby',
      latitude: 37.7749,
      longitude: -122.4194,
      radiusMeters: 50,
    ),
    const GeofenceZone(
      checkpointId: 'CP-002',
      name: 'Parking Garage B',
      latitude: 37.7751,
      longitude: -122.4180,
      radiusMeters: 50,
    ),
  ];

  static List<GeofenceZone> get zones => List.unmodifiable(_zones);

  static void addZone(GeofenceZone zone) {
    _zones.add(zone);
    CheckpointRegistry.register(zone.checkpointId, zone.name);
  }

  static void clearZones() => _zones.clear();

  static Future<bool> _ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  static Future<void> startMonitoring(
      Function(CheckpointScan) onScanned) async {
    if (_monitoring) return;

    final hasPermission = await _ensurePermissions();
    if (!hasPermission) {
      throw Exception('Location permissions not granted');
    }

    _monitoring = true;

    // Get position updates every ~5 seconds
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // minimum 5m movement before update
    );

    _positionSub =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      _checkGeofences(position, onScanned);
    });
  }

  static void stopMonitoring() {
    _monitoring = false;
    _positionSub?.cancel();
    _positionSub = null;
  }

  static void _checkGeofences(
      Position position, Function(CheckpointScan) onScanned) {
    for (final zone in _zones) {
      final distance = _distanceInMeters(
        position.latitude,
        position.longitude,
        zone.latitude,
        zone.longitude,
      );

      if (distance <= zone.radiusMeters) {
        // Cooldown: don't re-trigger same zone within 60 seconds
        final lastTriggered = _cooldowns[zone.checkpointId];
        if (lastTriggered != null &&
            DateTime.now().difference(lastTriggered).inSeconds < 60) {
          continue;
        }
        _cooldowns[zone.checkpointId] = DateTime.now();

        onScanned(CheckpointScan(
          checkpointId: zone.checkpointId,
          checkpointName: zone.name,
          method: ScanMethod.geofence,
          timestamp: DateTime.now(),
          latitude: position.latitude,
          longitude: position.longitude,
        ));
      }
    }
  }

  // Haversine formula for distance between two GPS points
  static double _distanceInMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  // Utility: get current position once (useful for tagging other scans)
  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await _ensurePermissions();
    if (!hasPermission) return null;
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }
}
