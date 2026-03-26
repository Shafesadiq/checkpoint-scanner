import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'tag_service.dart';
import 'geofence_setup_screen.dart';
import 'beacon_config_screen.dart';

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
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

  IconData _iconFor(CheckpointType t) {
    switch (t) {
      case CheckpointType.ble:
        return Icons.bluetooth;
      case CheckpointType.nfc:
        return Icons.nfc;
      case CheckpointType.qr:
        return Icons.qr_code;
      case CheckpointType.geofence:
        return Icons.location_on;
    }
  }

  Color _colorFor(CheckpointType t) {
    switch (t) {
      case CheckpointType.ble:
        return Colors.blue;
      case CheckpointType.nfc:
        return Colors.purple;
      case CheckpointType.qr:
        return Colors.teal;
      case CheckpointType.geofence:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Checkpoints (${_svc.checkpoints.length})'),
      ),
      body: _svc.checkpoints.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag_outlined, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('No checkpoints yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('Tap the + button to add one',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _svc.checkpoints.length,
              itemBuilder: (_, i) {
                final cp = _svc.checkpoints[i];
                return Dismissible(
                  key: ValueKey(cp.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Delete?'),
                            content: Text('Remove "${cp.name}" (#${cp.id})?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete',
                                      style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  onDismissed: (_) => _svc.deleteCheckpoint(cp.id),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _colorFor(cp.type),
                        child: Icon(_iconFor(cp.type), color: Colors.white, size: 20),
                      ),
                      title: Text(cp.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '#${cp.id}  •  ${cp.type.name.toUpperCase()}'
                        '${cp.bleName != null ? "  •  ${cp.bleName}" : ""}'
                        '${cp.nfcUid != null ? "  •  ${cp.nfcUid}" : ""}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: cp.type == CheckpointType.ble
                          ? IconButton(
                              icon: const Icon(Icons.settings, size: 20),
                              tooltip: 'Configure beacon',
                              onPressed: () => _openBleConfig(cp),
                            )
                          : null,
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Add Checkpoint'),
      ),
    );
  }

  void _openBleConfig(Checkpoint cp) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BeaconConfigScreen(targetMac: cp.bleId),
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('What type of checkpoint?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              _addTile(ctx, Icons.bluetooth, Colors.blue, 'BLE Beacon',
                  'Scan for a nearby Bluetooth beacon', _addBle),
              _addTile(ctx, Icons.nfc, Colors.purple, 'NFC Tag',
                  'Tap an NFC tag to register it', _addNfc),
              _addTile(ctx, Icons.qr_code, Colors.teal, 'QR Code',
                  'Create a printable QR checkpoint', _addQr),
              _addTile(ctx, Icons.location_on, Colors.orange, 'Geofence',
                  'Set a location on the map', _addGeofence),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addTile(BuildContext ctx, IconData icon, Color color, String title,
      String sub, VoidCallback onTap) {
    return ListTile(
      leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  void _addBle() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _BleScanScreen()),
    );
  }

  Future<void> _addNfc() async {
    _showSnack('Hold phone near NFC tag...');
    final uid = await _svc.scanNfcTag();
    if (uid == null) {
      _showSnack('NFC scan cancelled or failed.');
      return;
    }
    final existing = _svc.byNfcUid(uid);
    if (existing != null) {
      _showSnack('Already registered as #${existing.id} "${existing.name}"');
      return;
    }
    if (!mounted) return;
    final name = await _askName('NFC Tag', 'UID: $uid');
    if (name == null) return;
    final cp = Checkpoint(
      id: _svc.nextId,
      name: name,
      type: CheckpointType.nfc,
      nfcUid: uid,
      createdAt: DateTime.now(),
    );
    await _svc.addCheckpoint(cp);
    _showSnack('Created #${cp.id} "${cp.name}"');
  }

  Future<void> _addQr() async {
    final name = await _askName('QR Checkpoint', null);
    if (name == null) return;
    final cp = Checkpoint(
      id: _svc.nextId,
      name: name,
      type: CheckpointType.qr,
      createdAt: DateTime.now(),
    );
    await _svc.addCheckpoint(cp);
    _showSnack('Created #${cp.id} — print it from "Print QR Codes"');
  }

  void _addGeofence() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GeofenceSetupScreen()),
    );
  }

  Future<String?> _askName(String type, String? detail) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Name this $type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(detail,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            Text('Will be checkpoint #${_svc.nextId}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Front Entrance',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
              },
              child: const Text('Create')),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ═══════════════════════════════════════════════════════
// BLE Scan Screen — dummy friendly
// ═══════════════════════════════════════════════════════

class _BleScanScreen extends StatefulWidget {
  const _BleScanScreen();
  @override
  State<_BleScanScreen> createState() => _BleScanScreenState();
}

class _BleScanScreenState extends State<_BleScanScreen> {
  final _svc = TagService();

  @override
  void initState() {
    super.initState();
    _svc.addListener(_update);
    _svc.startScan();
  }

  @override
  void dispose() {
    _svc.removeListener(_update);
    _svc.stopScan();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  // Signal strength label
  String _signalLabel(int rssi) {
    if (rssi > -50) return 'Very close';
    if (rssi > -65) return 'Close';
    if (rssi > -80) return 'Medium';
    return 'Far away';
  }

  Color _signalColor(int rssi) {
    if (rssi > -50) return Colors.green;
    if (rssi > -65) return Colors.lightGreen;
    if (rssi > -80) return Colors.orange;
    return Colors.red;
  }

  int _signalBars(int rssi) {
    if (rssi > -50) return 4;
    if (rssi > -65) return 3;
    if (rssi > -80) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find BLE Beacon')),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(14),
            child: const Text(
              'Make sure your beacon is powered on.\n'
              'Tap the beacon you want to register.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          // Scan button
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _svc.isScanning ? null : () => _svc.startScan(),
                icon: _svc.isScanning
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_svc.isScanning ? 'Scanning...' : 'Scan Again',
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(
            child: _svc.scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_svc.isScanning) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Looking for beacons...', style: TextStyle(fontSize: 16)),
                        ] else ...[
                          Icon(Icons.bluetooth_disabled, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          const Text('No beacons found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          const Text('Make sure it\'s turned on and nearby',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _svc.scanResults.length,
                    itemBuilder: (_, i) {
                      final r = _svc.scanResults[i];
                      final bleId = r.device.remoteId.str;
                      final name = r.advertisementData.advName;
                      final rssi = r.rssi;
                      final existing = _svc.byBleId(bleId);
                      final bars = _signalBars(rssi);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: existing != null ? Colors.green.shade50 : null,
                        child: InkWell(
                          onTap: existing != null ? null : () => _register(r),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                // Signal indicator
                                Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: List.generate(4, (bi) {
                                        final active = bi < bars;
                                        return Container(
                                          width: 6,
                                          height: 8.0 + bi * 5,
                                          margin: const EdgeInsets.only(right: 2),
                                          decoration: BoxDecoration(
                                            color: active ? _signalColor(rssi) : Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        );
                                      }),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(_signalLabel(rssi),
                                        style: TextStyle(fontSize: 9, color: _signalColor(rssi))),
                                  ],
                                ),
                                const SizedBox(width: 14),
                                // Name + ID
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(bleId,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'monospace',
                                              color: Colors.grey.shade600)),
                                      if (existing != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.check_circle, size: 14, color: Colors.green),
                                              const SizedBox(width: 4),
                                              Text('Already registered: #${existing.id} "${existing.name}"',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Colors.green,
                                                      fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                // Add button
                                if (existing == null)
                                  FilledButton(
                                    onPressed: () => _register(r),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    ),
                                    child: const Text('ADD', style: TextStyle(fontSize: 16)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _register(ScanResult r) async {
    final bleId = r.device.remoteId.str;
    final deviceName = r.advertisementData.advName;
    final nameCtrl = TextEditingController();
    final nextId = _svc.nextId;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.bluetooth, color: Colors.blue),
            const SizedBox(width: 8),
            Text('New Checkpoint #$nextId'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Beacon info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(deviceName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(bleId,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Name field
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                labelText: 'Give it a name',
                hintText: 'e.g. Front Entrance',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton.icon(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, nameCtrl.text.trim());
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Save')),
        ],
      ),
    );

    if (result != null) {
      final cp = Checkpoint(
        id: nextId,
        name: result,
        type: CheckpointType.ble,
        bleId: bleId,
        bleName: deviceName,
        createdAt: DateTime.now(),
      );
      await _svc.addCheckpoint(cp);
      if (mounted) {
        // Big success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Checkpoint #${cp.id} "${cp.name}" saved!',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
