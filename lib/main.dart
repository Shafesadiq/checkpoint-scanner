import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'scanner_service.dart';
import 'geofence_service.dart';
import 'qr_scanner_screen.dart';

void main() {
  runApp(const CheckpointApp());
}

class CheckpointApp extends StatelessWidget {
  const CheckpointApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Checkpoint Scanner',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<CheckpointScan> _scanHistory = [];
  final List<String> _nfcLogs = [];
  bool _bleScanning = false;
  bool _nfcScanning = false;
  bool _geofenceMonitoring = false;
  bool _showLogs = false;

  void _addLog(String msg) {
    final time = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    setState(() {
      _nfcLogs.insert(0, '[$time] $msg');
      if (_nfcLogs.length > 100) _nfcLogs.removeLast();
    });
  }

  void _onCheckpointScanned(CheckpointScan scan) {
    setState(() {
      _scanHistory.insert(0, scan);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${scan.method.name.toUpperCase()} scanned: ${scan.checkpointName ?? scan.checkpointId}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(onScanned: _onCheckpointScanned),
      ),
    );
  }

  void _toggleBleScan() async {
    if (_bleScanning) {
      ScannerService.stopBleScan();
      setState(() => _bleScanning = false);
    } else {
      setState(() => _bleScanning = true);
      try {
        await ScannerService.startBleScan(_onCheckpointScanned);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('BLE error: $e')),
          );
        }
      }
      Future.delayed(const Duration(seconds: 16), () {
        if (mounted) setState(() => _bleScanning = false);
      });
    }
  }

  void _startNfcScan() async {
    setState(() {
      _nfcScanning = true;
      _showLogs = true;
    });
    _addLog('Starting NFC scan...');
    try {
      await ScannerService.startNfcScan(
        (scan) {
          _addLog('SUCCESS: Got checkpoint ${scan.checkpointId}');
          _onCheckpointScanned(scan);
          if (mounted) setState(() => _nfcScanning = false);
        },
        onError: (error) {
          _addLog('ERROR: $error');
          if (mounted) {
            setState(() => _nfcScanning = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('NFC: $error'),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
        onLog: _addLog,
      );
    } catch (e) {
      _addLog('EXCEPTION: $e');
      if (mounted) {
        setState(() => _nfcScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NFC error: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _toggleGeofence() async {
    if (_geofenceMonitoring) {
      GeofenceService.stopMonitoring();
      setState(() => _geofenceMonitoring = false);
    } else {
      setState(() => _geofenceMonitoring = true);
      try {
        await GeofenceService.startMonitoring(_onCheckpointScanned);
      } catch (e) {
        if (mounted) {
          setState(() => _geofenceMonitoring = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Geofence error: $e')),
          );
        }
      }
    }
  }

  IconData _iconForMethod(ScanMethod method) {
    switch (method) {
      case ScanMethod.qr:
        return Icons.qr_code_scanner;
      case ScanMethod.ble:
        return Icons.bluetooth;
      case ScanMethod.nfc:
        return Icons.nfc;
      case ScanMethod.geofence:
        return Icons.location_on;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkpoint Scanner'),
        actions: [
          IconButton(
            icon: Icon(_showLogs ? Icons.list : Icons.bug_report),
            tooltip: _showLogs ? 'Show scans' : 'Show NFC logs',
            onPressed: () => setState(() => _showLogs = !_showLogs),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('QR'),
                ),
                FilledButton.icon(
                  onPressed: _toggleBleScan,
                  icon: Icon(
                      _bleScanning ? Icons.bluetooth_searching : Icons.bluetooth),
                  label: Text(_bleScanning ? 'Stop BLE' : 'BLE'),
                  style: _bleScanning
                      ? FilledButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                ),
                FilledButton.icon(
                  onPressed: _nfcScanning ? null : _startNfcScan,
                  icon: const Icon(Icons.nfc),
                  label: Text(_nfcScanning ? 'Waiting...' : 'NFC'),
                ),
                FilledButton.icon(
                  onPressed: _toggleGeofence,
                  icon: Icon(_geofenceMonitoring
                      ? Icons.location_off
                      : Icons.location_on),
                  label: Text(_geofenceMonitoring ? 'Stop Geo' : 'Geofence'),
                  style: _geofenceMonitoring
                      ? FilledButton.styleFrom(backgroundColor: Colors.green)
                      : null,
                ),
              ],
            ),
          ),
          if (_bleScanning)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Scanning for BLE beacons...'),
                ],
              ),
            ),
          const Divider(),
          if (_showLogs) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Text('NFC Debug Log (${_nfcLogs.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_nfcLogs.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _nfcLogs.clear()),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _nfcLogs.isEmpty
                  ? const Center(child: Text('No logs yet. Tap NFC to start.'))
                  : ListView.builder(
                      itemCount: _nfcLogs.length,
                      itemBuilder: (context, index) {
                        final log = _nfcLogs[index];
                        final isError = log.contains('ERROR') ||
                            log.contains('EXCEPTION');
                        final isSuccess = log.contains('SUCCESS');
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 2.0),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: isError
                                  ? Colors.red
                                  : isSuccess
                                      ? Colors.green
                                      : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Text('Scan History (${_scanHistory.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  if (_scanHistory.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _scanHistory.clear()),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _scanHistory.isEmpty
                  ? const Center(
                      child: Text('No scans yet.\nTap a button above to start.',
                          textAlign: TextAlign.center))
                  : ListView.builder(
                      itemCount: _scanHistory.length,
                      itemBuilder: (context, index) {
                        final scan = _scanHistory[index];
                        final timeStr =
                            DateFormat('HH:mm:ss').format(scan.timestamp);
                        return ListTile(
                          leading:
                              Icon(_iconForMethod(scan.method), size: 32),
                          title: Text(
                              scan.checkpointName ?? scan.checkpointId),
                          subtitle: Text(
                              '${scan.method.name.toUpperCase()} • ${scan.checkpointId} • $timeStr'),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
