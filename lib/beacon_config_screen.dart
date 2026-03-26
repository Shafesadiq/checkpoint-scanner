import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'beacon_service.dart';
import 'models.dart';

class BeaconConfigScreen extends StatefulWidget {
  final String? targetMac;

  const BeaconConfigScreen({super.key, this.targetMac});

  @override
  State<BeaconConfigScreen> createState() => _BeaconConfigScreenState();
}

class _BeaconConfigScreenState extends State<BeaconConfigScreen> {
  final _svc = BeaconService();
  bool _showDebug = false;

  // ── Form controllers ──
  final _checkpointNameCtrl = TextEditingController();
  final _namespaceCtrl = TextEditingController();
  final _instanceCtrl = TextEditingController();
  final _txPowerCtrl = TextEditingController();
  final _intervalCtrl = TextEditingController();
  final _lockKeyCtrl =
      TextEditingController(text: '00000000000000000000000000000000');

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _svc.removeListener(_onServiceUpdate);
    _checkpointNameCtrl.dispose();
    _namespaceCtrl.dispose();
    _instanceCtrl.dispose();
    _txPowerCtrl.dispose();
    _intervalCtrl.dispose();
    _lockKeyCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});

    // Auto-populate editors when config is read
    final cfg = _svc.currentConfig;
    if (cfg != null) {
      _namespaceCtrl.text = BeaconService.bytesToHex(cfg.namespace);
      _instanceCtrl.text = BeaconService.bytesToHex(cfg.instance);
      _txPowerCtrl.text = cfg.txPower.toString();
      if (cfg.intervalMs != null) {
        _intervalCtrl.text = cfg.intervalMs.toString();
      }
    }
  }

  bool _isTargetMac(String mac) {
    if (widget.targetMac == null) return false;
    final a = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    final b =
        widget.targetMac!.replaceAll(':', '').replaceAll('-', '').toUpperCase();
    return a == b;
  }

  // ── Actions ──

  Future<void> _scan() => _svc.startScan();

  Future<void> _connect(BluetoothDevice device) async {
    _svc.stopScan();
    await _svc.connectToDevice(device);
  }

  Future<void> _unlock() async {
    final keyHex = _lockKeyCtrl.text.trim();
    final keyBytes = BeaconService.hexToBytes(keyHex);
    if (keyBytes.length != 16) {
      _showError('Lock key must be 32 hex chars (16 bytes).');
      return;
    }
    final ok = await _svc.unlock(key: keyBytes);
    if (ok) {
      await _svc.readConfig();
    }
  }

  Future<void> _readConfig() => _svc.readConfig();

  Future<void> _writeConfig() async {
    // Validate
    final nsHex = _namespaceCtrl.text.trim();
    final instHex = _instanceCtrl.text.trim();
    final nsBytes = BeaconService.hexToBytes(nsHex);
    final instBytes = BeaconService.hexToBytes(instHex);

    if (nsBytes.length != 10) {
      _showError('Namespace must be exactly 20 hex chars (10 bytes).');
      return;
    }
    if (instBytes.length != 6) {
      _showError('Instance must be exactly 12 hex chars (6 bytes).');
      return;
    }

    final txPower = int.tryParse(_txPowerCtrl.text.trim());
    if (txPower == null || txPower < -128 || txPower > 127) {
      _showError('TX Power must be -128 to 127.');
      return;
    }

    final interval = int.tryParse(_intervalCtrl.text.trim());
    if (interval != null && (interval < 100 || interval > 10000)) {
      _showError('Interval must be 100-10000 ms.');
      return;
    }

    final config = EddystoneConfig(
      frameType: 0x00,
      txPower: txPower,
      namespace: nsBytes,
      instance: instBytes,
      intervalMs: interval,
    );

    final ok = await _svc.writeConfig(config);
    if (ok) {
      _showSnack('Config saved to beacon.');
      // Save to local storage
      final beacon = ConfiguredBeacon(
        mac: _svc.connectedDevice?.remoteId.str ?? widget.targetMac ?? '',
        bleId: _svc.connectedDevice?.remoteId.str,
        checkpointName: _checkpointNameCtrl.text.trim().isNotEmpty
            ? _checkpointNameCtrl.text.trim()
            : 'Unnamed Checkpoint',
        namespace: nsHex,
        instanceId: instHex,
        addedAt: DateTime.now(),
      );
      await _svc.saveBeacon(beacon);
      _showSnack('Beacon saved to local storage.');
    } else {
      _showError('Write failed. Check log for details.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon Config'),
        actions: [
          if (_svc.connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Disconnect',
              onPressed: _svc.disconnect,
            ),
          IconButton(
            icon: Icon(_showDebug ? Icons.list : Icons.bug_report),
            tooltip: _showDebug ? 'Config view' : 'Debug view',
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
        ],
      ),
      body: _svc.connectionStatus == ConnectionStatus.disconnected
          ? _buildScanView()
          : _buildConfigView(),
    );
  }

  Widget _buildScanView() {
    return Column(
      children: [
        if (widget.targetMac != null)
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('Target: ${widget.targetMac}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _svc.isScanning ? null : _scan,
              icon: _svc.isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bluetooth_searching),
              label:
                  Text(_svc.isScanning ? 'Scanning...' : 'Scan for Beacons'),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _svc.scanResults.isEmpty
              ? Center(
                  child: Text(
                    _svc.isScanning
                        ? 'Searching...'
                        : 'No devices found.\nTap Scan to start.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: _svc.scanResults.length,
                  itemBuilder: (context, index) {
                    final r = _svc.scanResults[index];
                    final mac = r.device.remoteId.str;
                    final name = r.advertisementData.advName;
                    final isTarget = _isTargetMac(mac);
                    return ListTile(
                      leading: Icon(Icons.bluetooth,
                          color: isTarget ? Colors.green : Colors.blue),
                      title: Text(
                        name.isNotEmpty ? name : '(unnamed)',
                        style: TextStyle(
                            fontWeight: isTarget
                                ? FontWeight.bold
                                : FontWeight.normal),
                      ),
                      subtitle: Text('$mac  •  RSSI: ${r.rssi} dBm'),
                      trailing: isTarget
                          ? const Chip(
                              label: Text('TARGET',
                                  style: TextStyle(fontSize: 10)),
                              backgroundColor: Colors.greenAccent)
                          : null,
                      onTap: _svc.connectionStatus ==
                              ConnectionStatus.connecting
                          ? null
                          : () => _connect(r.device),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConfigView() {
    if (_showDebug) return _buildDebugView();

    final isConnecting =
        _svc.connectionStatus == ConnectionStatus.connecting;
    final hasError = _svc.connectionStatus == ConnectionStatus.error;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _svc.isUnlocked
                  ? Colors.green.shade50
                  : hasError
                      ? Colors.red.shade50
                      : isConnecting
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_svc.connectedDevice != null)
                  Text('Device: ${_svc.connectedDevice!.remoteId}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (isConnecting)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2)),
                    if (!isConnecting)
                      Icon(
                        _svc.isUnlocked
                            ? Icons.lock_open
                            : hasError
                                ? Icons.error
                                : Icons.lock,
                        size: 16,
                        color: _svc.isUnlocked
                            ? Colors.green
                            : hasError
                                ? Colors.red
                                : Colors.orange,
                      ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _svc.log.isNotEmpty ? _svc.log.first : '',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Unlock section ──
          if (!_svc.isUnlocked &&
              _svc.connectionStatus == ConnectionStatus.connected) ...[
            const Text('Unlock Beacon',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Default Eddystone lock key: 16 zero bytes (32 hex zeros).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lockKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'Lock Key (32 hex chars)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style:
                  const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _svc.readAllCharacteristics,
                  child: const Text('Read Raw'),
                ),
              ],
            ),
          ],

          // ── Config form (after unlock) ──
          if (_svc.isUnlocked) ...[
            const Text('Eddystone UID Configuration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _field(_checkpointNameCtrl, 'Checkpoint Name (local only)',
                hint: 'e.g. Front Entrance'),
            _field(_namespaceCtrl, 'Namespace (10 bytes / 20 hex)',
                hint: 'e.g. edd1ebeac04e5defa017'),
            _field(_instanceCtrl, 'Instance ID (6 bytes / 12 hex)',
                hint: 'e.g. 0b0102030405'),
            _field(_txPowerCtrl, 'TX Power (dBm)',
                hint: '-20 to +4', numeric: true),
            _field(_intervalCtrl, 'Broadcast Interval (ms)',
                hint: '100-10000', numeric: true),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _writeConfig,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Config'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _readConfig,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Re-read'),
                ),
              ],
            ),
          ],

          // ── Log ──
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Communication Log',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_svc.log.isNotEmpty)
                TextButton(
                  onPressed: () {
                    _svc.log.clear();
                    setState(() {});
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            height: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: _svc.log.length,
              itemBuilder: (_, i) {
                final line = _svc.log[i];
                Color? color;
                if (line.startsWith('fea1') || line.contains('Writing')) {
                  color = Colors.blue;
                }
                if (line.startsWith('fea2') || line.contains('Parsing')) {
                  color = Colors.green.shade700;
                }
                if (line.contains('ERROR') || line.contains('MISSING')) {
                  color = Colors.red;
                }
                if (line.contains('UNLOCKED') || line.contains('saved')) {
                  color = Colors.green;
                }
                return Text(line,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: color));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label,
      {String? hint, bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(signed: true)
            : TextInputType.text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDebugView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.grey.shade200,
          padding: const EdgeInsets.all(12),
          child: Text(
            'Device: ${_svc.connectedDevice?.remoteId ?? "none"}\n'
            '${_svc.allServices.length} services discovered.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton(
            onPressed: _svc.readAllCharacteristics,
            child: const Text('Read All Readable Characteristics'),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final s in _svc.allServices) ...[
                Container(
                  color: s.uuid == EddystoneUuids.configService
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Text(
                    'Service: ${BeaconService.shortUuid(s.uuid)} (${s.uuid})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                for (final c in s.characteristics)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${BeaconService.shortUuid(c.uuid)} (${c.uuid})',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                    subtitle: Text(
                        'Props: ${BeaconService.charProps(c)}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: c.properties.read
                        ? IconButton(
                            icon: const Icon(Icons.download, size: 18),
                            onPressed: () async {
                              try {
                                final val = await c.read();
                                _svc.addLog(
                                    'Read ${BeaconService.shortUuid(c.uuid)}: ${BeaconService.formatBytes(val)}');
                              } catch (e) {
                                _svc.addLog(
                                    'Read ${BeaconService.shortUuid(c.uuid)} error: $e');
                              }
                            },
                          )
                        : null,
                  ),
              ],
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Log',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _svc.log.length,
                  itemBuilder: (_, i) => Text(_svc.log[i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
