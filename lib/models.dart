enum ScanMethod { qr, ble, nfc, geofence }

class CheckpointScan {
  final String checkpointId;
  final String? checkpointName;
  final ScanMethod method;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  CheckpointScan({
    required this.checkpointId,
    this.checkpointName,
    required this.method,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });
}

class CheckpointRegistry {
  static final Map<String, String> _registry = {
    'CP-001': 'Building A Lobby',
    'CP-002': 'Parking Garage B',
    'CP-003': 'Server Room C',
    'CP-004': 'Main Entrance',
    'CP-005': 'Rooftop Access',
  };

  static void register(String id, String name) {
    _registry[id] = name;
  }

  static String? nameFor(String id) => _registry[id];
}

class GeofenceZone {
  final String checkpointId;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const GeofenceZone({
    required this.checkpointId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 50,
  });
}
