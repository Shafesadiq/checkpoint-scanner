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

// ─── Beacon Configuration Models ───

class ConfiguredBeacon {
  final String mac;
  final String? bleId;
  final String checkpointName;
  final String namespace;
  final String instanceId;
  final DateTime addedAt;

  ConfiguredBeacon({
    required this.mac,
    this.bleId,
    required this.checkpointName,
    required this.namespace,
    required this.instanceId,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'mac': mac,
        'bleId': bleId,
        'checkpointName': checkpointName,
        'namespace': namespace,
        'instanceId': instanceId,
        'addedAt': addedAt.toIso8601String(),
      };

  factory ConfiguredBeacon.fromJson(Map<String, dynamic> json) =>
      ConfiguredBeacon(
        mac: json['mac'] as String,
        bleId: json['bleId'] as String?,
        checkpointName: json['checkpointName'] as String,
        namespace: json['namespace'] as String,
        instanceId: json['instanceId'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

class PatrolLogEntry {
  final String checkpointName;
  final String mac;
  final DateTime timestamp;
  final int rssi;

  PatrolLogEntry({
    required this.checkpointName,
    required this.mac,
    required this.timestamp,
    required this.rssi,
  });

  Map<String, dynamic> toJson() => {
        'checkpointName': checkpointName,
        'mac': mac,
        'timestamp': timestamp.toIso8601String(),
        'rssi': rssi,
      };

  factory PatrolLogEntry.fromJson(Map<String, dynamic> json) => PatrolLogEntry(
        checkpointName: json['checkpointName'] as String,
        mac: json['mac'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        rssi: json['rssi'] as int,
      );
}

class EddystoneConfig {
  final int frameType;
  final int txPower;
  final List<int> namespace; // 10 bytes
  final List<int> instance; // 6 bytes
  final int? intervalMs;

  EddystoneConfig({
    required this.frameType,
    required this.txPower,
    required this.namespace,
    required this.instance,
    this.intervalMs,
  });
}
