import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// KKM KBPro beacon GATT structure (confirmed from device logs):
///
/// Service 0x180A — Standard Device Information
///   2A29 (R) = "KKM", 2A24 (R) = "K4_NRF52XX", 2A27 (R) = "V2.1",
///   2A26 (R) = "V6.43", 2A23 (R) = System ID
///
/// Service 0xFEA0 — Beacon Config Service (contains FEA1/FEA2/FEA3)
///   FEA1 (WNR)  — Unlock / write config
///   FEA2 (R, N) — Read config data
///   FEA3 (I)    — Indicate
///
/// Service 0xFE59 — Eddystone GATT service (DFU / slot control)
///   0003 (W, I) — Eddystone slot write / indicate
class EddystoneUuids {
  // Beacon Config Service — contains FEA1, FEA2, FEA3
  static final Guid configService =
      Guid('0000fea0-0000-1000-8000-00805f9b34fb');
  static final Guid charFea1 =
      Guid('0000fea1-0000-1000-8000-00805f9b34fb');
  static final Guid charFea2 =
      Guid('0000fea2-0000-1000-8000-00805f9b34fb');
  static final Guid charFea3 =
      Guid('0000fea3-0000-1000-8000-00805f9b34fb');

  // Eddystone GATT Service (0xFE59) — slot/DFU control
  static final Guid eddystoneService =
      Guid('0000fe59-0000-1000-8000-00805f9b34fb');
  static final Guid charSlotWrite =
      Guid('00000003-0000-1000-8000-00805f9b34fb');

  // Standard Device Information Service
  static final Guid deviceInfoService =
      Guid('0000180a-0000-1000-8000-00805f9b34fb');
}

class EddystoneFrameType {
  static const int uid = 0x00;
  static const int url = 0x10;
  static const int tlm = 0x20;
  static const int eid = 0x30;
}

/// Known beacon hardware.
const String kTargetMac = 'DD:34:02:C6:C4:45';
const String kTargetBleId = 'DA149432-A1AE-BC07-A392-BE4E366BBB42';

// ─── Storage keys ───
const String _kBeaconsKey = 'configured_beacons';
const String _kPatrolLogsKey = 'patrol_logs';

enum ConnectionStatus { disconnected, connecting, connected, error }

class BeaconService extends ChangeNotifier {
  // ── Singleton ──
  static final BeaconService _instance = BeaconService._();
  factory BeaconService() => _instance;
  BeaconService._();

  // ── Scan state ──
  bool isScanning = false;
  List<ScanResult> scanResults = [];
  StreamSubscription? _scanSub;

  // ── Connection state ──
  BluetoothDevice? connectedDevice;
  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  bool isUnlocked = false;

  // ── GATT handles (all under service 0xFE59) ──
  BluetoothCharacteristic? _fea1;
  BluetoothCharacteristic? _fea2;
  BluetoothCharacteristic? _fea3;
  StreamSubscription? _fea1Sub;
  StreamSubscription? _fea2Sub;
  List<BluetoothService> allServices = [];

  // ── Config read from beacon ──
  EddystoneConfig? currentConfig;

  // ── Patrol state ──
  bool isPatrolling = false;
  StreamSubscription? _patrolScanSub;
  final Map<String, DateTime> _patrolCooldowns = {};

  // ── Storage ──
  List<ConfiguredBeacon> configuredBeacons = [];
  List<PatrolLogEntry> patrolLog = [];

  // ── Log ──
  final List<String> log = [];

  void addLog(String msg) {
    debugPrint('[BeaconService] $msg');
    log.insert(0, msg);
    if (log.length > 300) log.removeLast();
    notifyListeners();
  }

  // ═══════════════════════ ADAPTER ═══════════════════════

  /// Wait for Bluetooth adapter to be ON. Returns false on timeout or if off.
  Future<bool> ensureAdapterReady() async {
    addLog('Checking Bluetooth adapter...');
    try {
      final state = await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 5));
      addLog('Adapter ready: $state');
      return true;
    } on TimeoutException {
      addLog('ERROR: Bluetooth adapter not ready (5s timeout). Is BLE on?');
      return false;
    } catch (e) {
      addLog('ERROR: Adapter check failed: $e');
      return false;
    }
  }

  // ═══════════════════════ SCANNING ═══════════════════════

  Future<void> startScan() async {
    if (isScanning) return;

    if (!await ensureAdapterReady()) return;

    isScanning = true;
    scanResults.clear();
    notifyListeners();

    addLog('Starting BLE scan (10s)...');

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        scanResults.clear();
        for (final r in results) {
          final mac = r.device.remoteId.str.toUpperCase();
          final name = r.advertisementData.advName;
          if (name.isNotEmpty || _matchesTarget(mac)) {
            scanResults.add(r);
          }
        }
        scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
        notifyListeners();
      });

      await Future.delayed(const Duration(seconds: 10));
    } catch (e) {
      addLog('Scan error: $e');
    }

    isScanning = false;
    notifyListeners();
    addLog('Scan complete. ${scanResults.length} device(s) found.');
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
    isScanning = false;
    notifyListeners();
  }

  bool _matchesTarget(String mac) {
    final norm = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    final target = kTargetMac.replaceAll(':', '').toUpperCase();
    return norm == target;
  }

  /// Check if a MAC or BLE ID matches a known configured beacon.
  bool matchesKnownBeacon(String identifier) {
    final norm = identifier.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    for (final b in configuredBeacons) {
      final macNorm = b.mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
      if (macNorm == norm) return true;
      if (b.bleId != null &&
          b.bleId!.replaceAll('-', '').toUpperCase() == norm) {
        return true;
      }
    }
    return false;
  }

  // ═══════════════════════ CONNECT ═══════════════════════

  /// Full connection flow with stabilization delay and state checks.
  Future<bool> connectToDevice(BluetoothDevice device) async {
    connectionStatus = ConnectionStatus.connecting;
    connectedDevice = device;
    isUnlocked = false;
    currentConfig = null;
    allServices = [];
    _fea1 = null;
    _fea2 = null;
    _fea3 = null;
    notifyListeners();

    addLog('Connecting to ${device.remoteId}...');

    try {
      // Step 5: Connect with timeout
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      // Step 6: Stabilization delay
      addLog('Connected. Stabilizing (400ms)...');
      await Future.delayed(const Duration(milliseconds: 400));

      // Step 7: Verify still connected
      if (!device.isConnected) {
        addLog('ERROR: Device disconnected during stabilization.');
        connectionStatus = ConnectionStatus.error;
        notifyListeners();
        return false;
      }

      // Step 8: Discover services
      addLog('Discovering services...');
      final services = await device.discoverServices();
      allServices = services;
      addLog('Found ${services.length} service(s).');

      // Log all services
      for (final s in services) {
        addLog('Service: ${shortUuid(s.uuid)} (${s.uuid})');
        for (final c in s.characteristics) {
          addLog('  Char: ${shortUuid(c.uuid)}  props: ${charProps(c)}');
        }
      }

      // Step 9: Find config service 0xFEA0 (contains FEA1/FEA2/FEA3)
      BluetoothService? configSvc;
      for (final s in services) {
        if (s.uuid == EddystoneUuids.configService) {
          configSvc = s;
          break;
        }
      }

      if (configSvc == null) {
        addLog('ERROR: Config service (fea0) NOT found on device.');
        connectionStatus = ConnectionStatus.error;
        notifyListeners();
        return false;
      }

      addLog('Found config service (fea0).');

      // Step 10: Find characteristics FEA1, FEA2, FEA3 under FEA0
      for (final c in configSvc.characteristics) {
        if (c.uuid == EddystoneUuids.charFea1) _fea1 = c;
        if (c.uuid == EddystoneUuids.charFea2) _fea2 = c;
        if (c.uuid == EddystoneUuids.charFea3) _fea3 = c;
      }

      addLog('fea1: ${_fea1 != null ? "OK" : "MISSING"}  '
          'fea2: ${_fea2 != null ? "OK" : "MISSING"}  '
          'fea3: ${_fea3 != null ? "OK" : "MISSING"}');

      // Subscribe to notifications
      if (_fea1 != null && _fea1!.properties.notify) {
        await _fea1!.setNotifyValue(true);
        _fea1Sub = _fea1!.onValueReceived.listen((data) {
          addLog('fea1 notify: [${bytesToHex(data)}] (${data.length}B)');
        });
      }
      if (_fea2 != null && _fea2!.properties.notify) {
        await _fea2!.setNotifyValue(true);
        _fea2Sub = _fea2!.onValueReceived.listen((data) {
          addLog('fea2 notify: [${bytesToHex(data)}] (${data.length}B)');
        });
      }

      // Read device info from 0x180A
      _readDeviceInfo(services);

      connectionStatus = ConnectionStatus.connected;
      notifyListeners();
      addLog('Connected and ready. Unlock to configure.');
      return true;
    } catch (e) {
      addLog('Connection error: $e');
      connectionStatus = ConnectionStatus.error;
      notifyListeners();
      return false;
    }
  }

  Future<void> _readDeviceInfo(List<BluetoothService> services) async {
    for (final s in services) {
      if (s.uuid == EddystoneUuids.deviceInfoService) {
        addLog('── Device Info (180a) ──');
        for (final c in s.characteristics) {
          if (!c.properties.read) continue;
          if (!_isConnected()) return;
          try {
            final val = await c.read();
            addLog('  ${shortUuid(c.uuid)}: ${formatBytes(val)}');
          } catch (e) {
            addLog('  ${shortUuid(c.uuid)}: ERROR $e');
          }
        }
        break;
      }
    }
  }

  Future<void> disconnect() async {
    _fea1Sub?.cancel();
    _fea1Sub = null;
    _fea2Sub?.cancel();
    _fea2Sub = null;
    try {
      await connectedDevice?.disconnect();
    } catch (_) {}
    connectedDevice = null;
    _fea1 = null;
    _fea2 = null;
    _fea3 = null;
    isUnlocked = false;
    currentConfig = null;
    allServices = [];
    connectionStatus = ConnectionStatus.disconnected;
    notifyListeners();
    addLog('Disconnected.');
  }

  bool _isConnected() => connectedDevice?.isConnected ?? false;

  // ═══════════════════════ EDDYSTONE PROTOCOL ═══════════════════════

  /// Step 11: Unlock beacon by writing 16-byte key to FEA1 under FE59.
  Future<bool> unlock({List<int>? key}) async {
    if (_fea1 == null) {
      addLog('ERROR: fea1 characteristic not available.');
      return false;
    }
    if (!_isConnected()) {
      addLog('ERROR: Device disconnected.');
      return false;
    }

    final unlockKey = key ?? List.filled(16, 0);
    if (unlockKey.length != 16) {
      addLog('ERROR: Unlock key must be exactly 16 bytes.');
      return false;
    }

    addLog('Unlocking with key: [${bytesToHex(unlockKey)}]');

    try {
      await _writeCharacteristic(_fea1!, unlockKey);
      addLog('Unlock key written.');

      // Step 12: Stabilization delay
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 13: Check connection
      if (!_isConnected()) {
        addLog('ERROR: Device disconnected after unlock write.');
        return false;
      }

      // Try reading lock state to verify
      if (_fea1!.properties.read) {
        final lockData = await _fea1!.read();
        addLog('Lock state after unlock: [${bytesToHex(lockData)}]');
        if (lockData.isNotEmpty && lockData[0] == 0x00) {
          isUnlocked = true;
          notifyListeners();
          addLog('Beacon UNLOCKED.');
          return true;
        }
      }

      // Some beacons don't report lock state — assume unlocked if no error
      isUnlocked = true;
      notifyListeners();
      addLog('Unlock sent (no lock state confirmation available).');
      return true;
    } catch (e) {
      addLog('Unlock error: $e');
      return false;
    }
  }

  /// Step 14: Read config from FEA2 under FE59.
  Future<EddystoneConfig?> readConfig() async {
    if (_fea2 == null || !_fea2!.properties.read) {
      addLog('ERROR: fea2 not available for reading.');
      return null;
    }
    if (!_isConnected()) {
      addLog('ERROR: Device disconnected.');
      return null;
    }

    addLog('Reading config from fea2...');
    try {
      final data = await _fea2!.read();
      addLog('fea2 raw: [${bytesToHex(data)}] (${data.length}B)');
      currentConfig = _parseConfigData(data);
      notifyListeners();
      return currentConfig;
    } catch (e) {
      addLog('Read config error: $e');
      return null;
    }
  }

  EddystoneConfig? _parseConfigData(List<int> data) {
    if (data.isEmpty) {
      addLog('Config data is empty.');
      return null;
    }

    addLog('Parsing ${data.length} bytes...');

    // Detect frame type offset
    int offset = 0;
    final firstByte = data[0];

    if (firstByte == EddystoneFrameType.uid ||
        firstByte == EddystoneFrameType.url ||
        firstByte == EddystoneFrameType.tlm ||
        firstByte == EddystoneFrameType.eid) {
      offset = 0;
    } else if (data.length > 1 &&
        (data[1] == EddystoneFrameType.uid ||
         data[1] == EddystoneFrameType.url)) {
      addLog('Slot byte detected: 0x${firstByte.toRadixString(16)}');
      offset = 1;
    }

    if (offset >= data.length) return null;

    final frameType = data[offset];
    addLog('Frame type: 0x${frameType.toRadixString(16)}');

    if (frameType == EddystoneFrameType.uid && data.length >= offset + 18) {
      final txPower = data[offset + 1].toSigned(8);
      final namespace = data.sublist(offset + 2, offset + 12);
      final instance = data.sublist(offset + 12, offset + 18);

      int? intervalMs;
      if (data.length >= offset + 20) {
        final intervalBytes = data.sublist(offset + 18, offset + 20);
        intervalMs = ByteData.sublistView(Uint8List.fromList(intervalBytes))
            .getUint16(0, Endian.little);
      }

      addLog('Namespace: ${bytesToHex(namespace)}');
      addLog('Instance:  ${bytesToHex(instance)}');
      addLog('TX Power:  $txPower dBm');
      if (intervalMs != null) addLog('Interval:  ${intervalMs}ms');

      return EddystoneConfig(
        frameType: frameType,
        txPower: txPower,
        namespace: namespace,
        instance: instance,
        intervalMs: intervalMs,
      );
    }

    addLog('Unrecognized frame or insufficient data for UID parse.');
    return EddystoneConfig(
      frameType: frameType,
      txPower: 0,
      namespace: List.filled(10, 0),
      instance: List.filled(6, 0),
    );
  }

  /// Write Eddystone UID config to beacon via FEA1 under FE59.
  Future<bool> writeConfig(EddystoneConfig config) async {
    if (_fea1 == null) {
      addLog('ERROR: fea1 not available.');
      return false;
    }
    if (!_isConnected()) {
      addLog('ERROR: Device disconnected.');
      return false;
    }
    if (!isUnlocked) {
      addLog('ERROR: Beacon locked. Unlock first.');
      return false;
    }

    if (config.namespace.length != 10) {
      addLog('ERROR: Namespace must be 10 bytes.');
      return false;
    }
    if (config.instance.length != 6) {
      addLog('ERROR: Instance must be 6 bytes.');
      return false;
    }

    final txByte = config.txPower < 0 ? (256 + config.txPower) : config.txPower;

    final payload = <int>[
      EddystoneFrameType.uid,
      txByte & 0xFF,
      ...config.namespace,
      ...config.instance,
    ];

    if (config.intervalMs != null && config.intervalMs! > 0) {
      final bd = ByteData(2);
      bd.setUint16(0, config.intervalMs!, Endian.little);
      payload.add(bd.getUint8(0));
      payload.add(bd.getUint8(1));
    }

    addLog('Writing config: [${bytesToHex(payload)}] (${payload.length}B)');

    try {
      await _writeCharacteristic(_fea1!, payload);
      addLog('Config written.');

      await Future.delayed(const Duration(milliseconds: 300));
      if (!_isConnected()) {
        addLog('ERROR: Disconnected after write.');
        return false;
      }

      // Re-read to verify
      await readConfig();
      addLog('Config saved and verified.');
      return true;
    } catch (e) {
      addLog('Write error: $e');
      return false;
    }
  }

  Future<void> _writeCharacteristic(
      BluetoothCharacteristic ch, List<int> data) async {
    if (ch.properties.writeWithoutResponse) {
      await ch.write(data, withoutResponse: true);
    } else if (ch.properties.write) {
      await ch.write(data);
    } else {
      throw Exception('Characteristic not writable: ${ch.uuid}');
    }
  }

  /// Read all readable characteristics (debug).
  Future<void> readAllCharacteristics() async {
    addLog('═══ Reading all characteristics ═══');
    for (final s in allServices) {
      addLog('── Service ${shortUuid(s.uuid)} ──');
      for (final c in s.characteristics) {
        if (!c.properties.read) {
          addLog('  ${shortUuid(c.uuid)}: [${charProps(c)}] (not readable)');
          continue;
        }
        if (!_isConnected()) {
          addLog('ABORTED — device disconnected.');
          return;
        }
        try {
          final val = await c.read();
          addLog('  ${shortUuid(c.uuid)}: ${formatBytes(val)}');
        } catch (e) {
          addLog('  ${shortUuid(c.uuid)}: ERROR $e');
        }
      }
    }
  }

  // ═══════════════════════ PATROL SCANNING ═══════════════════════

  Future<void> startPatrolScan() async {
    if (isPatrolling) return;
    if (!await ensureAdapterReady()) return;

    isPatrolling = true;
    _patrolCooldowns.clear();
    notifyListeners();
    addLog('Patrol scan started.');

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(hours: 8),
        continuousUpdates: true,
      );

      _patrolScanSub?.cancel();
      _patrolScanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          _checkPatrolHit(r);
        }
      });
    } catch (e) {
      addLog('Patrol scan error: $e');
      isPatrolling = false;
      notifyListeners();
    }
  }

  void stopPatrolScan() {
    FlutterBluePlus.stopScan();
    _patrolScanSub?.cancel();
    _patrolScanSub = null;
    isPatrolling = false;
    notifyListeners();
    addLog('Patrol scan stopped.');
  }

  void _checkPatrolHit(ScanResult r) {
    final mac = r.device.remoteId.str.toUpperCase();
    final bleId = r.device.remoteId.str.toUpperCase();

    // Find matching configured beacon
    ConfiguredBeacon? match;
    for (final b in configuredBeacons) {
      final bMac = b.mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
      final rMac = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
      if (bMac == rMac) {
        match = b;
        break;
      }
      if (b.bleId != null) {
        final bBleId = b.bleId!.replaceAll('-', '').toUpperCase();
        final rBleId = bleId.replaceAll('-', '').toUpperCase();
        if (bBleId == rBleId) {
          match = b;
          break;
        }
      }
    }

    if (match == null) return;

    // 5-minute cooldown per beacon
    final lastHit = _patrolCooldowns[match.mac];
    if (lastHit != null &&
        DateTime.now().difference(lastHit).inMinutes < 5) {
      return;
    }
    _patrolCooldowns[match.mac] = DateTime.now();

    final entry = PatrolLogEntry(
      checkpointName: match.checkpointName,
      mac: match.mac,
      timestamp: DateTime.now(),
      rssi: r.rssi,
    );

    patrolLog.insert(0, entry);
    _savePatrolLog();
    notifyListeners();
    addLog('PATROL HIT: ${match.checkpointName} (RSSI: ${r.rssi})');
  }

  // ═══════════════════════ LOCAL STORAGE ═══════════════════════

  Future<void> loadBeacons() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kBeaconsKey);
    if (json != null) {
      final list = jsonDecode(json) as List;
      configuredBeacons =
          list.map((e) => ConfiguredBeacon.fromJson(e)).toList();
      notifyListeners();
    }
  }

  Future<void> saveBeacon(ConfiguredBeacon beacon) async {
    // Replace existing or add
    configuredBeacons.removeWhere((b) =>
        b.mac.replaceAll(':', '').toUpperCase() ==
        beacon.mac.replaceAll(':', '').toUpperCase());
    configuredBeacons.add(beacon);
    await _persistBeacons();
    notifyListeners();
  }

  Future<void> deleteBeacon(String mac) async {
    configuredBeacons.removeWhere((b) =>
        b.mac.replaceAll(':', '').toUpperCase() ==
        mac.replaceAll(':', '').toUpperCase());
    await _persistBeacons();
    notifyListeners();
  }

  Future<void> _persistBeacons() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(configuredBeacons.map((b) => b.toJson()).toList());
    await prefs.setString(_kBeaconsKey, json);
  }

  Future<void> loadPatrolLog() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kPatrolLogsKey);
    if (json != null) {
      final list = jsonDecode(json) as List;
      patrolLog = list.map((e) => PatrolLogEntry.fromJson(e)).toList();
      notifyListeners();
    }
  }

  Future<void> _savePatrolLog() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(patrolLog.map((e) => e.toJson()).toList());
    await prefs.setString(_kPatrolLogsKey, json);
  }

  Future<void> clearPatrolLog() async {
    patrolLog.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPatrolLogsKey);
    notifyListeners();
  }

  String exportPatrolLog() {
    final buf = StringBuffer();
    buf.writeln('Patrol Log Export — ${DateTime.now().toIso8601String()}');
    buf.writeln('=' * 50);
    for (final e in patrolLog) {
      buf.writeln(
          '${e.timestamp.toIso8601String()}  ${e.checkpointName}  '
          'MAC: ${e.mac}  RSSI: ${e.rssi}');
    }
    buf.writeln('=' * 50);
    buf.writeln('Total: ${patrolLog.length} entries');
    return buf.toString();
  }

  // ═══════════════════════ HELPERS ═══════════════════════

  static String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');

  /// Format bytes for logging: hex dump + ascii only if all bytes are printable.
  static String formatBytes(List<int> bytes) {
    final hex = bytesToHex(bytes);
    final isPrintable = bytes.every((b) => b >= 0x20 && b < 0x7F);
    if (isPrintable && bytes.isNotEmpty) {
      return '[$hex] "${String.fromCharCodes(bytes)}"';
    }
    return '[$hex] (${bytes.length}B)';
  }

  static List<int> hexToBytes(String hex) {
    hex = hex.replaceAll(RegExp(r'[\s:-]'), '');
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  static String shortUuid(Guid guid) {
    final full = guid.toString().replaceAll('-', '').toLowerCase();
    if (full.length >= 8) return full.substring(4, 8);
    return full;
  }

  static String charProps(BluetoothCharacteristic c) {
    final p = <String>[];
    if (c.properties.read) p.add('R');
    if (c.properties.write) p.add('W');
    if (c.properties.writeWithoutResponse) p.add('WNR');
    if (c.properties.notify) p.add('N');
    if (c.properties.indicate) p.add('I');
    return p.join(',');
  }
}
