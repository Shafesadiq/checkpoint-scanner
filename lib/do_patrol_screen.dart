import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'tag_service.dart';

class DoPatrolScreen extends StatefulWidget {
  final Patrol patrol;
  const DoPatrolScreen({super.key, required this.patrol});

  @override
  State<DoPatrolScreen> createState() => _DoPatrolScreenState();
}

class _DoPatrolScreenState extends State<DoPatrolScreen> {
  final _svc = TagService();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_update);
  }

  @override
  void dispose() {
    _svc.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await _svc.startPatrolRun(widget.patrol);
  }

  void _openScanner() async {
    final result = await Navigator.of(context).push<_ScanResult>(
      MaterialPageRoute(builder: (_) => _PatrolScannerScreen(patrol: widget.patrol, svc: _svc)),
    );

    if (result != null && _svc.activeRun != null) {
      // Record the scan
      final cp = _svc.byId(result.checkpointId);
      if (cp != null) {
        final already = _svc.activeRun!.scans.any((s) => s.checkpointId == cp.id);
        if (!already) {
          _svc.recordScan(PatrolScan(
            checkpointId: cp.id,
            checkpointName: cp.name,
            type: result.type,
            scannedAt: DateTime.now(),
            rssi: result.rssi,
          ));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${cp.name} scanned!'),
                backgroundColor: Colors.green,
              ),
            );
          }

          // Check if all done
          if (_svc.activeRun!.scans.length >= widget.patrol.checkpointIds.length) {
            await _svc.finishPatrolRun();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Patrol complete!'), backgroundColor: Colors.green),
              );
              Navigator.of(context).pop();
            }
          }
        }
      }
    }
  }

  Future<void> _finish() async {
    await _svc.finishPatrolRun();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Patrol?'),
        content: const Text('This run will not be saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continue')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _svc.cancelPatrolRun();
      if (mounted) Navigator.of(context).pop();
    }
  }

  IconData _iconFor(CheckpointType t) {
    switch (t) {
      case CheckpointType.ble: return Icons.bluetooth;
      case CheckpointType.nfc: return Icons.nfc;
      case CheckpointType.qr: return Icons.qr_code;
      case CheckpointType.geofence: return Icons.location_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _svc.activeRun;
    final scannedIds = run?.scans.map((s) => s.checkpointId).toSet() ?? {};
    final total = widget.patrol.checkpointIds.length;
    final done = scannedIds.length;

    return PopScope(
      canPop: run == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.patrol.name),
          actions: [
            if (run != null)
              TextButton(
                onPressed: _finish,
                child: const Text('FINISH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        body: Column(
          children: [
            // Progress header
            Container(
              width: double.infinity,
              color: run != null
                  ? (done == total ? Colors.green.shade50 : Colors.blue.shade50)
                  : Colors.grey.shade50,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    run != null ? '$done / $total' : 'Ready',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: run != null
                          ? (done == total ? Colors.green : Colors.blue)
                          : Colors.grey,
                    ),
                  ),
                  if (run != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: total > 0 ? done / total : 0,
                        minHeight: 14,
                        backgroundColor: Colors.grey.shade200,
                        color: done == total ? Colors.green : Colors.blue,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            // Checklist
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.patrol.checkpointIds.length,
                itemBuilder: (_, i) {
                  final cpId = widget.patrol.checkpointIds[i];
                  final cp = _svc.byId(cpId);
                  final scanned = scannedIds.contains(cpId);
                  final scan = run?.scans.where((s) => s.checkpointId == cpId).firstOrNull;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    color: scanned ? Colors.green.shade50 : null,
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scanned ? Colors.green : Colors.grey.shade200,
                        ),
                        child: Icon(
                          scanned ? Icons.check : _iconFor(cp?.type ?? CheckpointType.qr),
                          color: scanned ? Colors.white : Colors.grey,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        cp?.name ?? cpId,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scanned ? Colors.green.shade700 : null,
                        ),
                      ),
                      subtitle: Text(
                        scanned
                            ? '${scan!.type.name.toUpperCase()} at ${DateFormat('HH:mm:ss').format(scan.scannedAt)}'
                            : '#$cpId  •  ${cp?.type.name.toUpperCase() ?? "?"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scanned ? Colors.green : Colors.grey,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Bottom button
            Padding(
              padding: const EdgeInsets.all(16),
              child: run == null
                  ? SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _start,
                        icon: const Icon(Icons.play_arrow, size: 28),
                        label: const Text('START PATROL', style: TextStyle(fontSize: 18)),
                      ),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _openScanner,
                            icon: const Icon(Icons.sensors, size: 28),
                            label: const Text('SCAN CHECKPOINT', style: TextStyle(fontSize: 18)),
                            style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _cancel,
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('CANCEL PATROL'),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// Scan result passed back from scanner
// ═══════════════════════════════════════════

class _ScanResult {
  final String checkpointId;
  final CheckpointType type;
  final int rssi;
  _ScanResult({required this.checkpointId, required this.type, this.rssi = 0});
}

// ═══════════════════════════════════════════
// 4-tab scanner screen
// ═══════════════════════════════════════════

class _PatrolScannerScreen extends StatefulWidget {
  final Patrol patrol;
  final TagService svc;
  const _PatrolScannerScreen({required this.patrol, required this.svc});

  @override
  State<_PatrolScannerScreen> createState() => _PatrolScannerScreenState();
}

class _PatrolScannerScreenState extends State<_PatrolScannerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Set<String> get _alreadyScanned =>
      widget.svc.activeRun?.scans.map((s) => s.checkpointId).toSet() ?? {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Checkpoint'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'BLE'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR'),
            Tab(icon: Icon(Icons.nfc), text: 'NFC'),
            Tab(icon: Icon(Icons.location_on), text: 'Geo'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _BleTab(svc: widget.svc, patrol: widget.patrol, alreadyScanned: _alreadyScanned,
              onSelect: _selectCheckpoint),
          _QrTab(svc: widget.svc, patrol: widget.patrol, alreadyScanned: _alreadyScanned, onSelect: _selectCheckpoint),
          _NfcTab(svc: widget.svc, patrol: widget.patrol, alreadyScanned: _alreadyScanned, onSelect: _selectCheckpoint),
          _GeoTab(svc: widget.svc, patrol: widget.patrol, alreadyScanned: _alreadyScanned,
              onSelect: _selectCheckpoint),
        ],
      ),
    );
  }

  void _selectCheckpoint(String cpId, CheckpointType type, {int rssi = 0}) {
    Navigator.of(context).pop(_ScanResult(checkpointId: cpId, type: type, rssi: rssi));
  }
}

// ─── BLE Tab ───

class _BleTab extends StatefulWidget {
  final TagService svc;
  final Patrol patrol;
  final Set<String> alreadyScanned;
  final void Function(String, CheckpointType, {int rssi}) onSelect;

  const _BleTab({required this.svc, required this.patrol, required this.alreadyScanned, required this.onSelect});

  @override
  State<_BleTab> createState() => _BleTabState();
}

class _BleTabState extends State<_BleTab> {
  bool _scanning = false;
  List<ScanResult> _results = [];
  StreamSubscription? _sub;

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() { _scanning = true; _results = []; });
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      setState(() => _scanning = false);
      return;
    }

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    _sub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        _results = results.where((r) => r.advertisementData.advName.isNotEmpty).toList();
        _results.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    await Future.delayed(const Duration(seconds: 8));
    if (mounted) setState(() => _scanning = false);
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _sub?.cancel();
    _sub = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _startScan,
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? 'Scanning...' : 'Scan for BLE Beacons',
                  style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
        Expanded(
          child: _results.isEmpty
              ? Center(child: Text(_scanning ? 'Searching...' : 'Tap the button above to scan'))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final r = _results[i];
                    final bleId = r.device.remoteId.str;
                    final name = r.advertisementData.advName;
                    final cp = widget.svc.byBleId(bleId);
                    final inPatrol = cp != null && widget.patrol.checkpointIds.contains(cp.id);
                    final done = cp != null && widget.alreadyScanned.contains(cp.id);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      color: done ? Colors.grey.shade100 : inPatrol ? Colors.blue.shade50 : null,
                      child: ListTile(
                        leading: Icon(
                          inPatrol ? Icons.flag : Icons.bluetooth,
                          color: done ? Colors.grey : inPatrol ? Colors.blue : Colors.grey,
                        ),
                        title: Text(
                          inPatrol ? '#${cp.id} — ${cp.name}' : name,
                          style: TextStyle(
                            fontWeight: inPatrol ? FontWeight.bold : FontWeight.normal,
                            color: done ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          done
                              ? 'Already scanned'
                              : inPatrol
                                  ? '$name  •  RSSI: ${r.rssi}'
                                  : '$bleId  •  Not in this patrol',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: inPatrol && !done
                            ? FilledButton(
                                onPressed: () => widget.onSelect(cp.id, CheckpointType.ble, rssi: r.rssi),
                                child: const Text('SELECT'),
                              )
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── QR Tab ───

class _QrTab extends StatefulWidget {
  final TagService svc;
  final Patrol patrol;
  final Set<String> alreadyScanned;
  final void Function(String, CheckpointType, {int rssi}) onSelect;
  const _QrTab({required this.svc, required this.patrol, required this.alreadyScanned, required this.onSelect});

  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  bool _active = false;
  bool _handled = false;
  MobileScannerController? _ctrl;
  String? _errorMsg;

  void _startCamera() {
    _ctrl = MobileScannerController();
    setState(() { _active = true; _handled = false; _errorMsg = null; });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMsg != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_errorMsg!, textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orange.shade800)),
              ),
            FilledButton.icon(
              onPressed: _startCamera,
              icon: const Icon(Icons.camera_alt, size: 28),
              label: const Text('Open Camera', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
            ),
          ],
        ),
      );
    }

    return MobileScanner(
      controller: _ctrl!,
      onDetect: (capture) {
        if (_handled) return;
        final raw = capture.barcodes.first.rawValue;
        if (raw == null) return;
        _handled = true;

        final cp = widget.svc.byQrData(raw);
        if (cp == null) {
          _ctrl?.stop();
          setState(() { _active = false; _errorMsg = 'Unknown QR code.\nNot a registered checkpoint.\n\nScanned: $raw'; });
        } else if (!widget.patrol.checkpointIds.contains(cp.id)) {
          _ctrl?.stop();
          setState(() { _active = false; _errorMsg = '#${cp.id} "${cp.name}" is registered but not part of this patrol.'; });
        } else if (widget.alreadyScanned.contains(cp.id)) {
          _ctrl?.stop();
          setState(() { _active = false; _errorMsg = '#${cp.id} "${cp.name}" was already scanned.'; });
        } else {
          widget.onSelect(cp.id, CheckpointType.qr);
        }
      },
    );
  }
}

// ─── NFC Tab ───

enum _NfcResult { none, success, notInPatrol, alreadyScanned, unknown, error }

class _NfcTab extends StatefulWidget {
  final TagService svc;
  final Patrol patrol;
  final Set<String> alreadyScanned;
  final void Function(String, CheckpointType, {int rssi}) onSelect;
  const _NfcTab({required this.svc, required this.patrol, required this.alreadyScanned, required this.onSelect});

  @override
  State<_NfcTab> createState() => _NfcTabState();
}

class _NfcTabState extends State<_NfcTab> {
  bool _listening = false;
  _NfcResult _result = _NfcResult.none;
  String _resultText = '';
  Checkpoint? _foundCp;

  Future<void> _startNfc() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      setState(() { _result = _NfcResult.error; _resultText = 'NFC not available on this device'; });
      return;
    }

    setState(() { _listening = true; _result = _NfcResult.none; _resultText = ''; _foundCp = null; });

    NfcManager.instance.startSession(
      alertMessage: 'Hold near NFC checkpoint',
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        List<int>? uid;
        final data = tag.data;
        if (data.containsKey('mifare')) {
          uid = (data['mifare']?['identifier'] as List?)?.cast<int>();
        } else if (data.containsKey('nfca')) {
          uid = (data['nfca']?['identifier'] as List?)?.cast<int>();
        }

        if (uid != null && uid.isNotEmpty) {
          final uidHex = uid.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
          final cp = widget.svc.byNfcUid(uidHex);

          if (cp != null && widget.patrol.checkpointIds.contains(cp.id)) {
            if (widget.alreadyScanned.contains(cp.id)) {
              NfcManager.instance.stopSession(alertMessage: '${cp.name} - already scanned');
              if (mounted) {
                setState(() {
                  _listening = false; _result = _NfcResult.alreadyScanned;
                  _foundCp = cp; _resultText = 'Already scanned in this patrol';
                });
              }
            } else {
              NfcManager.instance.stopSession(alertMessage: '${cp.name} scanned!');
              if (mounted) {
                setState(() {
                  _listening = false; _result = _NfcResult.success;
                  _foundCp = cp; _resultText = 'Checkpoint found!';
                });
              }
            }
          } else if (cp != null) {
            NfcManager.instance.stopSession(alertMessage: '${cp.name} - not in this patrol');
            if (mounted) {
              setState(() {
                _listening = false; _result = _NfcResult.notInPatrol;
                _foundCp = cp; _resultText = 'This tag is registered but not part of this patrol';
              });
            }
          } else {
            NfcManager.instance.stopSession(alertMessage: 'Unknown tag');
            if (mounted) {
              setState(() {
                _listening = false; _result = _NfcResult.unknown;
                _resultText = 'Unknown NFC tag\nUID: $uidHex\n\nThis tag is not registered as a checkpoint.';
              });
            }
          }
        } else {
          NfcManager.instance.stopSession(alertMessage: 'Could not read tag');
          if (mounted) {
            setState(() {
              _listening = false; _result = _NfcResult.error;
              _resultText = 'Could not read tag UID';
            });
          }
        }
      },
      onError: (e) async {
        if (mounted) {
          setState(() { _listening = false; });
        }
      },
    );
  }

  @override
  void dispose() {
    if (_listening) {
      try { NfcManager.instance.stopSession(); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Result visual
          if (_result != _NfcResult.none) ...[
            _buildResultCard(),
            const SizedBox(height: 24),
          ],

          // Icon
          if (_result == _NfcResult.none)
            Icon(Icons.nfc, size: 80,
                color: _listening ? Colors.purple : Colors.grey.shade300),
          if (_result == _NfcResult.none && _listening)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Hold phone near NFC tag...',
                  style: TextStyle(fontSize: 16, color: Colors.purple)),
            ),
          if (_result == _NfcResult.none) const SizedBox(height: 24),

          // Buttons
          if (_result == _NfcResult.success && _foundCp != null)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: () => widget.onSelect(_foundCp!.id, CheckpointType.nfc),
                icon: const Icon(Icons.check),
                label: Text('Confirm: ${_foundCp!.name}', style: const TextStyle(fontSize: 16)),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
          if (_result == _NfcResult.success) const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: _result == _NfcResult.none
                ? FilledButton.icon(
                    onPressed: _listening ? null : _startNfc,
                    icon: _listening
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.nfc, size: 28),
                    label: Text(_listening ? 'Scanning...' : 'Tap NFC Tag',
                        style: const TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(backgroundColor: Colors.purple),
                  )
                : OutlinedButton.icon(
                    onPressed: () {
                      setState(() { _result = _NfcResult.none; _resultText = ''; _foundCp = null; });
                      _startNfc();
                    },
                    icon: const Icon(Icons.nfc),
                    label: const Text('Scan Another Tag', style: TextStyle(fontSize: 16)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    Color bgColor;
    Color iconColor;
    IconData icon;

    switch (_result) {
      case _NfcResult.success:
        bgColor = Colors.green.shade50;
        iconColor = Colors.green;
        icon = Icons.check_circle;
      case _NfcResult.alreadyScanned:
        bgColor = Colors.blue.shade50;
        iconColor = Colors.blue;
        icon = Icons.info;
      case _NfcResult.notInPatrol:
        bgColor = Colors.orange.shade50;
        iconColor = Colors.orange;
        icon = Icons.warning;
      case _NfcResult.unknown:
        bgColor = Colors.red.shade50;
        iconColor = Colors.red;
        icon = Icons.help_outline;
      case _NfcResult.error:
        bgColor = Colors.red.shade50;
        iconColor = Colors.red;
        icon = Icons.error;
      case _NfcResult.none:
        return const SizedBox();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: 8),
          if (_foundCp != null) ...[
            Text('#${_foundCp!.id}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: iconColor)),
            Text(_foundCp!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
          ],
          Text(_resultText, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: iconColor)),
        ],
      ),
    );
  }
}

// ─── Geofence Tab ───

class _GeoTab extends StatefulWidget {
  final TagService svc;
  final Patrol patrol;
  final Set<String> alreadyScanned;
  final void Function(String, CheckpointType, {int rssi}) onSelect;
  const _GeoTab({required this.svc, required this.patrol, required this.alreadyScanned, required this.onSelect});

  @override
  State<_GeoTab> createState() => _GeoTabState();
}

class _GeoTabState extends State<_GeoTab> {
  bool _checking = false;
  String _status = '';
  Position? _pos;

  Future<void> _checkLocation() async {
    setState(() { _checking = true; _status = 'Getting location...'; });

    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      _pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _status = 'Location: ${_pos!.latitude.toStringAsFixed(5)}, ${_pos!.longitude.toStringAsFixed(5)}');
    } catch (e) {
      setState(() => _status = 'Location error: $e');
    }
    setState(() => _checking = false);
  }

  double _distanceTo(Checkpoint cp) {
    if (_pos == null || cp.latitude == null || cp.longitude == null) return double.infinity;
    const r = 6371000.0;
    final dLat = (cp.latitude! - _pos!.latitude) * math.pi / 180;
    final dLon = (cp.longitude! - _pos!.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_pos!.latitude * math.pi / 180) *
            math.cos(cp.latitude! * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  Widget build(BuildContext context) {
    // Get geofence checkpoints in this patrol
    final geoCps = widget.patrol.checkpointIds
        .map((id) => widget.svc.byId(id))
        .where((cp) => cp != null && cp.type == CheckpointType.geofence)
        .cast<Checkpoint>()
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _checking ? null : _checkLocation,
              icon: _checking
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location),
              label: Text(_checking ? 'Checking...' : 'Check My Location',
                  style: const TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ),
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        if (geoCps.isEmpty)
          const Expanded(child: Center(child: Text('No geofence checkpoints in this patrol.')))
        else
          Expanded(
            child: ListView.builder(
              itemCount: geoCps.length,
              itemBuilder: (_, i) {
                final cp = geoCps[i];
                final done = widget.alreadyScanned.contains(cp.id);
                final dist = _pos != null ? _distanceTo(cp) : null;
                final inRange = dist != null && dist <= (cp.radiusMeters ?? 50);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  color: done ? Colors.grey.shade100 : inRange ? Colors.green.shade50 : null,
                  child: ListTile(
                    leading: Icon(
                      done ? Icons.check_circle : inRange ? Icons.location_on : Icons.location_off,
                      color: done ? Colors.grey : inRange ? Colors.green : Colors.orange,
                    ),
                    title: Text('#${cp.id} — ${cp.name}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: done ? Colors.grey : null,
                        )),
                    subtitle: Text(
                      done
                          ? 'Already scanned'
                          : dist != null
                              ? '${dist.toInt()}m away  •  radius: ${cp.radiusMeters?.toInt()}m'
                              : 'Tap "Check My Location" first',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: inRange && !done
                        ? FilledButton(
                            onPressed: () => widget.onSelect(cp.id, CheckpointType.geofence),
                            child: const Text('SELECT'),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
