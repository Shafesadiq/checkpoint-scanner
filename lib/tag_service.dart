import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Checkpoint Types ───

enum CheckpointType { ble, nfc, qr, geofence }

// ─── Models ───

class Checkpoint {
  final String id; // "00001" - "99999"
  final String name; // "Front Entrance"
  final CheckpointType type;
  final String? bleId; // BLE MAC / CoreBluetooth UUID
  final String? bleName; // BLE advertised name
  final String? nfcUid; // NFC tag UID hex
  final double? latitude; // geofence
  final double? longitude; // geofence
  final double? radiusMeters; // geofence
  final DateTime createdAt;

  Checkpoint({
    required this.id,
    required this.name,
    required this.type,
    this.bleId,
    this.bleName,
    this.nfcUid,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    required this.createdAt,
  });

  /// QR code content — just the checkpoint ID
  String get qrData => 'CP:$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'bleId': bleId,
        'bleName': bleName,
        'nfcUid': nfcUid,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Checkpoint.fromJson(Map<String, dynamic> j) => Checkpoint(
        id: j['id'],
        name: j['name'],
        type: CheckpointType.values.firstWhere((t) => t.name == j['type']),
        bleId: j['bleId'],
        bleName: j['bleName'],
        nfcUid: j['nfcUid'],
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        radiusMeters: (j['radiusMeters'] as num?)?.toDouble(),
        createdAt: DateTime.parse(j['createdAt']),
      );
}

class Patrol {
  final String id;
  final String name;
  final List<String> checkpointIds;
  final DateTime createdAt;

  Patrol({
    required this.id,
    required this.name,
    required this.checkpointIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'checkpointIds': checkpointIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Patrol.fromJson(Map<String, dynamic> j) => Patrol(
        id: j['id'],
        name: j['name'],
        checkpointIds: List<String>.from(j['checkpointIds']),
        createdAt: DateTime.parse(j['createdAt']),
      );
}

class PatrolRun {
  final String patrolId;
  final String patrolName;
  final DateTime startedAt;
  DateTime? completedAt;
  final List<PatrolScan> scans;

  PatrolRun({
    required this.patrolId,
    required this.patrolName,
    required this.startedAt,
    this.completedAt,
    List<PatrolScan>? scans,
  }) : scans = scans ?? [];

  Map<String, dynamic> toJson() => {
        'patrolId': patrolId,
        'patrolName': patrolName,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'scans': scans.map((s) => s.toJson()).toList(),
      };

  factory PatrolRun.fromJson(Map<String, dynamic> j) => PatrolRun(
        patrolId: j['patrolId'],
        patrolName: j['patrolName'],
        startedAt: DateTime.parse(j['startedAt']),
        completedAt:
            j['completedAt'] != null ? DateTime.parse(j['completedAt']) : null,
        scans: (j['scans'] as List).map((s) => PatrolScan.fromJson(s)).toList(),
      );
}

class PatrolScan {
  final String checkpointId;
  final String checkpointName;
  final CheckpointType type;
  final DateTime scannedAt;
  final int rssi;

  PatrolScan({
    required this.checkpointId,
    required this.checkpointName,
    required this.type,
    required this.scannedAt,
    this.rssi = 0,
  });

  Map<String, dynamic> toJson() => {
        'checkpointId': checkpointId,
        'checkpointName': checkpointName,
        'type': type.name,
        'scannedAt': scannedAt.toIso8601String(),
        'rssi': rssi,
      };

  factory PatrolScan.fromJson(Map<String, dynamic> j) => PatrolScan(
        checkpointId: j['checkpointId'],
        checkpointName: j['checkpointName'],
        type: CheckpointType.values.firstWhere((t) => t.name == j['type']),
        scannedAt: DateTime.parse(j['scannedAt']),
        rssi: j['rssi'] ?? 0,
      );
}

// ─── Service ───

class TagService extends ChangeNotifier {
  static final TagService _i = TagService._();
  factory TagService() => _i;
  TagService._();

  /// Safe notify — schedule on next frame to avoid calling during tree lock.
  void _notify() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notify();
    });
  }

  List<Checkpoint> checkpoints = [];
  List<Patrol> patrols = [];
  List<PatrolRun> history = [];

  // BLE scan state
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  StreamSubscription? _scanSub;

  // Active patrol run
  PatrolRun? activeRun;
  // ignore: unused_field
  Patrol? _activePatrol;

  // ═══════════════ STORAGE ═══════════════

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final cpJson = prefs.getString('checkpoints');
    if (cpJson != null) {
      checkpoints = (jsonDecode(cpJson) as List)
          .map((e) => Checkpoint.fromJson(e))
          .toList();
    }
    final pJson = prefs.getString('patrols');
    if (pJson != null) {
      patrols =
          (jsonDecode(pJson) as List).map((e) => Patrol.fromJson(e)).toList();
    }
    final hJson = prefs.getString('patrol_history');
    if (hJson != null) {
      history = (jsonDecode(hJson) as List)
          .map((e) => PatrolRun.fromJson(e))
          .toList();
    }
    _notify();
  }

  Future<void> _saveCheckpoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'checkpoints', jsonEncode(checkpoints.map((c) => c.toJson()).toList()));
  }

  Future<void> _savePatrols() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'patrols', jsonEncode(patrols.map((p) => p.toJson()).toList()));
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'patrol_history', jsonEncode(history.map((h) => h.toJson()).toList()));
  }

  // ═══════════════ CHECKPOINTS ═══════════════

  String get nextId {
    int max = 0;
    for (final c in checkpoints) {
      final n = int.tryParse(c.id) ?? 0;
      if (n > max) max = n;
    }
    return (max + 1).toString().padLeft(5, '0');
  }

  Checkpoint? byId(String id) {
    for (final c in checkpoints) {
      if (c.id == id) return c;
    }
    return null;
  }

  Checkpoint? byBleId(String bleId) {
    final norm = bleId.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    for (final c in checkpoints) {
      if (c.bleId == null) continue;
      final cNorm =
          c.bleId!.replaceAll(':', '').replaceAll('-', '').toUpperCase();
      if (cNorm == norm) return c;
    }
    return null;
  }

  Checkpoint? byNfcUid(String uid) {
    final norm = uid.replaceAll(':', '').toUpperCase();
    for (final c in checkpoints) {
      if (c.nfcUid == null) continue;
      if (c.nfcUid!.replaceAll(':', '').toUpperCase() == norm) return c;
    }
    return null;
  }

  Checkpoint? byQrData(String data) {
    // QR content is "CP:00001"
    final match = RegExp(r'CP:(\d+)').firstMatch(data);
    if (match != null) return byId(match.group(1)!);
    // Fallback: try raw as ID
    return byId(data);
  }

  Future<Checkpoint> addCheckpoint(Checkpoint cp) async {
    checkpoints.add(cp);
    await _saveCheckpoints();
    _notify();
    return cp;
  }

  Future<void> deleteCheckpoint(String id) async {
    checkpoints.removeWhere((c) => c.id == id);
    for (final p in patrols) {
      p.checkpointIds.remove(id);
    }
    await _saveCheckpoints();
    await _savePatrols();
    _notify();
  }

  List<Checkpoint> get bleCheckpoints =>
      checkpoints.where((c) => c.type == CheckpointType.ble).toList();
  List<Checkpoint> get nfcCheckpoints =>
      checkpoints.where((c) => c.type == CheckpointType.nfc).toList();
  List<Checkpoint> get qrCheckpoints =>
      checkpoints.where((c) => c.type == CheckpointType.qr).toList();
  List<Checkpoint> get geofenceCheckpoints =>
      checkpoints.where((c) => c.type == CheckpointType.geofence).toList();

  // ═══════════════ PATROLS ═══════════════

  Future<Patrol> createPatrol({
    required String name,
    required List<String> checkpointIds,
  }) async {
    final patrol = Patrol(
      id: 'P${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      checkpointIds: checkpointIds,
      createdAt: DateTime.now(),
    );
    patrols.add(patrol);
    await _savePatrols();
    _notify();
    return patrol;
  }

  Future<void> deletePatrol(String id) async {
    patrols.removeWhere((p) => p.id == id);
    await _savePatrols();
    _notify();
  }

  // ═══════════════ BLE SCAN ═══════════════

  Future<void> startScan() async {
    if (isScanning) return;
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return;
    }
    isScanning = true;
    scanResults.clear();
    _notify();

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      scanResults.clear();
      for (final r in results) {
        if (r.advertisementData.advName.isNotEmpty) {
          scanResults.add(r);
        }
      }
      scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
      _notify();
    });

    await Future.delayed(const Duration(seconds: 10));
    isScanning = false;
    _notify();
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    isScanning = false;
    _notify();
  }

  // ═══════════════ NFC SCAN (one-shot for registration) ═══════════════

  Future<String?> scanNfcTag() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) return null;

    final completer = Completer<String?>();

    NfcManager.instance.startSession(
      alertMessage: 'Hold your phone near the NFC tag',
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        // Extract UID
        List<int>? uid;
        final data = tag.data;
        if (data.containsKey('mifare')) {
          uid = (data['mifare']?['identifier'] as List?)?.cast<int>();
        } else if (data.containsKey('nfca')) {
          uid = (data['nfca']?['identifier'] as List?)?.cast<int>();
        }

        String? uidHex;
        if (uid != null && uid.isNotEmpty) {
          uidHex = uid
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':');
        }

        NfcManager.instance
            .stopSession(alertMessage: 'Tag read: ${uidHex ?? "unknown"}');
        if (!completer.isCompleted) completer.complete(uidHex);
      },
      onError: (error) async {
        NfcManager.instance.stopSession(errorMessage: 'Error: $error');
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    return completer.future;
  }

  // ═══════════════ DO PATROL ═══════════════

  void recordScan(PatrolScan scan) {
    if (activeRun == null) return;
    activeRun!.scans.add(scan);
    _notify();
  }

  Future<void> startPatrolRun(Patrol patrol) async {
    if (activeRun != null) return;
    activeRun = PatrolRun(
      patrolId: patrol.id,
      patrolName: patrol.name,
      startedAt: DateTime.now(),
    );
    _activePatrol = patrol;
    _notify();
  }

  Future<void> finishPatrolRun() async {
    if (activeRun == null) return;
    activeRun!.completedAt = DateTime.now();
    history.insert(0, activeRun!);
    await _saveHistory();
    activeRun = null;
    _activePatrol = null;
    _notify();
  }

  Future<void> cancelPatrolRun() async {
    activeRun = null;
    _activePatrol = null;
    _notify();
  }

  Future<void> clearHistory() async {
    history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('patrol_history');
    _notify();
  }
}
