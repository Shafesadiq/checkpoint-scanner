import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'models.dart';

class ScannerService {
  // BLE cooldown tracking
  static final Map<String, DateTime> _bleCooldowns = {};
  static StreamSubscription? _bleScanSub;
  static bool _bleScanning = false;

  static bool get isBleScanning => _bleScanning;

  // ─── BLE Beacon Scanning ───

  static Future<void> startBleScan(Function(CheckpointScan) onScanned) async {
    if (_bleScanning) return;
    _bleScanning = true;

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.rssi < -70) continue; // too far away

        final id = r.device.remoteId.str; // MAC address
        final name = r.advertisementData.advName;

        // Cooldown: skip if scanned within last 30 seconds
        final lastSeen = _bleCooldowns[id];
        if (lastSeen != null &&
            DateTime.now().difference(lastSeen).inSeconds < 30) {
          continue;
        }
        _bleCooldowns[id] = DateTime.now();

        final checkpointId = name.isNotEmpty ? name : id;
        onScanned(CheckpointScan(
          checkpointId: checkpointId,
          checkpointName: CheckpointRegistry.nameFor(checkpointId),
          method: ScanMethod.ble,
          timestamp: DateTime.now(),
        ));
      }
    });

    // Auto-stop after scan timeout
    Future.delayed(const Duration(seconds: 15), () {
      stopBleScan();
    });
  }

  static void stopBleScan() {
    _bleScanning = false;
    FlutterBluePlus.stopScan();
    _bleScanSub?.cancel();
    _bleScanSub = null;
  }

  // ─── NFC Tag Scanning ───

  static Future<void> startNfcScan(
    Function(CheckpointScan) onScanned, {
    Function(String)? onError,
    Function(String)? onLog,
  }) async {
    void log(String msg) {
      onLog?.call(msg);
    }

    log('NFC: Checking availability...');
    bool isAvailable = await NfcManager.instance.isAvailable();
    log('NFC: isAvailable = $isAvailable');
    if (!isAvailable) throw Exception('NFC not available on this device');

    log('NFC: Starting session with ISO 14443 polling (NTAG213)...');
    NfcManager.instance.startSession(
      alertMessage: 'Hold the top of your iPhone near the NFC tag',
      pollingOptions: {
        NfcPollingOption.iso14443,
      },
      onDiscovered: (NfcTag tag) async {
        try {
          log('NFC: Tag discovered!');
          log('NFC: Tag data keys: ${tag.data.keys.toList()}');

          // Dump all tag data for debugging
          for (final key in tag.data.keys) {
            final value = tag.data[key];
            if (value is Map) {
              log('NFC: [$key] keys: ${value.keys.toList()}');
              for (final subKey in value.keys) {
                log('NFC: [$key][$subKey] = ${value[subKey]}');
              }
            } else {
              log('NFC: [$key] = $value');
            }
          }

          String checkpointId = '';

          // 1. Try NDEF payload
          final ndef = Ndef.from(tag);
          log('NFC: NDEF object: ${ndef != null ? "found" : "null"}');
          if (ndef != null) {
            log('NFC: NDEF isWritable: ${ndef.isWritable}, maxSize: ${ndef.maxSize}');
            log('NFC: cachedMessage: ${ndef.cachedMessage != null ? "found" : "null"}');
          }

          if (ndef != null && ndef.cachedMessage != null) {
            log('NFC: NDEF records count: ${ndef.cachedMessage!.records.length}');
            for (int i = 0; i < ndef.cachedMessage!.records.length; i++) {
              final record = ndef.cachedMessage!.records[i];
              final typeStr = String.fromCharCodes(record.type);
              log('NFC: Record[$i] TNF: ${record.typeNameFormat}, type: "$typeStr"');
              log('NFC: Record[$i] payload (${record.payload.length} bytes): ${record.payload}');
              if (record.payload.isNotEmpty) {
                try {
                  log('NFC: Record[$i] payload as string: "${String.fromCharCodes(record.payload)}"');
                } catch (e) {
                  log('NFC: Record[$i] payload not valid string: $e');
                }
              }

              // Text record (type 'T')
              if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
                  typeStr == 'T') {
                final langCodeLength = record.payload.first;
                checkpointId = String.fromCharCodes(
                  record.payload.sublist(1 + langCodeLength),
                );
                log('NFC: Extracted text record: "$checkpointId"');
                break;
              }
              // URI record (type 'U')
              if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown &&
                  typeStr == 'U') {
                checkpointId =
                    String.fromCharCodes(record.payload.sublist(1));
                log('NFC: Extracted URI record: "$checkpointId"');
                break;
              }
              // Any other record — try raw payload
              if (checkpointId.isEmpty && record.payload.isNotEmpty) {
                try {
                  checkpointId = String.fromCharCodes(record.payload);
                  log('NFC: Used raw payload as ID: "$checkpointId"');
                } catch (_) {}
              }
            }
          } else {
            log('NFC: No NDEF data on this tag (blank or not NDEF formatted)');
          }

          // 2. Fallback: tag UID (NTAG213 = ISO 14443 Type A = mifare on iOS, nfca on Android)
          if (checkpointId.isEmpty) {
            log('NFC: No NDEF ID found, trying hardware UID...');
            final tagData = tag.data;
            List<int>? uid;

            if (tagData.containsKey('mifare')) {
              uid = (tagData['mifare']?['identifier'] as List?)?.cast<int>();
              log('NFC: Got MiFare identifier: $uid');
            } else if (tagData.containsKey('nfca')) {
              uid = (tagData['nfca']?['identifier'] as List?)?.cast<int>();
              log('NFC: Got NfcA identifier: $uid');
            }

            if (uid != null && uid.isNotEmpty) {
              checkpointId = uid
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(':');
              log('NFC: UID as hex: $checkpointId');
            } else {
              log('NFC: No UID found in tag data');
            }
          }

          if (checkpointId.isEmpty) {
            checkpointId = 'unknown-tag';
            log('NFC: Could not extract any ID, using "unknown-tag"');
          }

          // Strip "ID:" prefix if present
          final idMatch = RegExp(r'ID[:\s]*(\w+)').firstMatch(checkpointId);
          if (idMatch != null) {
            checkpointId = idMatch.group(1)!;
            log('NFC: Stripped ID prefix, final: "$checkpointId"');
          }

          log('NFC: Final checkpoint ID: "$checkpointId"');

          onScanned(CheckpointScan(
            checkpointId: checkpointId,
            checkpointName: CheckpointRegistry.nameFor(checkpointId),
            method: ScanMethod.nfc,
            timestamp: DateTime.now(),
          ));

          NfcManager.instance.stopSession(alertMessage: 'Tag scanned: $checkpointId');
        } catch (e, stack) {
          log('NFC: Exception in onDiscovered: $e');
          log('NFC: Stack: $stack');
          onError?.call('Read error: $e');
          NfcManager.instance
              .stopSession(errorMessage: 'Failed: $e');
        }
      },
      onError: (error) async {
        final errorType = error.runtimeType.toString();
        final errorMsg = error.toString();
        final details = error is Exception ? errorMsg : 'type=$errorType msg=$errorMsg';
        log('NFC: Session onError: $details');
        log('NFC: Error runtimeType: $errorType');
        // NFCError typically means user cancelled or session timed out
        if (errorMsg.contains('Session') || errorMsg.contains('invalidat')) {
          onError?.call('NFC session ended: $details');
        } else {
          onError?.call('NFC error ($errorType): $details');
        }
      },
    );
    log('NFC: Session started, waiting for tag...');
  }

  static void stopNfcScan() {
    try {
      NfcManager.instance.stopSession();
    } catch (_) {}
  }
}
