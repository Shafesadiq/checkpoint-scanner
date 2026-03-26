import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'beacon_service.dart';

class PatrolScreen extends StatefulWidget {
  const PatrolScreen({super.key});

  @override
  State<PatrolScreen> createState() => _PatrolScreenState();
}

class _PatrolScreenState extends State<PatrolScreen> {
  final _svc = BeaconService();
  int _tabIndex = 0; // 0=patrol, 1=history, 2=beacons

  @override
  void initState() {
    super.initState();
    _svc.addListener(_update);
    _svc.loadBeacons();
    _svc.loadPatrolLog();
  }

  @override
  void dispose() {
    _svc.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrol'),
        actions: [
          if (_tabIndex == 1 && _svc.patrolLog.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Export patrol log',
              onPressed: _exportLog,
            ),
        ],
      ),
      body: Column(
        children: [
          // Patrol toggle
          _buildPatrolToggle(),
          const Divider(height: 1),
          // Tab bar
          _buildTabBar(),
          const Divider(height: 1),
          // Tab content
          Expanded(child: _buildTabContent()),
        ],
      ),
    );
  }

  Widget _buildPatrolToggle() {
    return Container(
      width: double.infinity,
      color: _svc.isPatrolling ? Colors.green.shade50 : Colors.grey.shade50,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _svc.isPatrolling ? 'Patrol Active' : 'Patrol Inactive',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _svc.isPatrolling ? Colors.green : Colors.grey,
                  ),
                ),
                Text(
                  '${_svc.configuredBeacons.length} beacon(s) configured  •  '
                  '${_svc.patrolLog.length} log entries',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _togglePatrol,
            icon: Icon(
                _svc.isPatrolling ? Icons.stop : Icons.play_arrow),
            label: Text(_svc.isPatrolling ? 'Stop' : 'Start'),
            style: _svc.isPatrolling
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        _tab(0, Icons.radar, 'Live'),
        _tab(1, Icons.history, 'History'),
        _tab(2, Icons.settings_bluetooth, 'Beacons'),
      ],
    );
  }

  Widget _tab(int index, IconData icon, String label) {
    final selected = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? Theme.of(context).primaryColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Theme.of(context).primaryColor : Colors.grey),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Theme.of(context).primaryColor : Colors.grey,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tabIndex) {
      case 0:
        return _buildLiveTab();
      case 1:
        return _buildHistoryTab();
      case 2:
        return _buildBeaconsTab();
      default:
        return const SizedBox();
    }
  }

  // ── Live patrol tab ──
  Widget _buildLiveTab() {
    if (!_svc.isPatrolling) {
      return const Center(
        child: Text('Tap Start to begin patrol scanning.',
            textAlign: TextAlign.center),
      );
    }

    // Show recent patrol hits (last 20)
    final recent = _svc.patrolLog.take(20).toList();
    if (recent.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 12),
            Text('Scanning for configured beacons...'),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: recent.length,
      itemBuilder: (_, i) {
        final e = recent[i];
        final time = DateFormat('HH:mm:ss').format(e.timestamp);
        final isRecent =
            DateTime.now().difference(e.timestamp).inSeconds < 10;
        return ListTile(
          leading: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecent ? Colors.green : Colors.green.shade100,
            ),
            child: Icon(Icons.check,
                color: isRecent ? Colors.white : Colors.green),
          ),
          title: Text(e.checkpointName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('$time  •  RSSI: ${e.rssi} dBm  •  ${e.mac}'),
        );
      },
    );
  }

  // ── History tab ──
  Widget _buildHistoryTab() {
    if (_svc.patrolLog.isEmpty) {
      return const Center(child: Text('No patrol log entries yet.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text('${_svc.patrolLog.length} entries',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Clear Log?'),
                      content: const Text(
                          'This will permanently delete all patrol log entries.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _svc.clearPatrolLog();
                  }
                },
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _svc.patrolLog.length,
            itemBuilder: (_, i) {
              final e = _svc.patrolLog[i];
              final time =
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(e.timestamp);
              return ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline, size: 20),
                title: Text(e.checkpointName),
                subtitle:
                    Text('$time  •  RSSI: ${e.rssi}  •  ${e.mac}',
                        style: const TextStyle(fontSize: 11)),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Beacons tab ──
  Widget _buildBeaconsTab() {
    if (_svc.configuredBeacons.isEmpty) {
      return const Center(
        child: Text(
          'No beacons configured yet.\n'
          'Use Config screen to set up a beacon.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      itemCount: _svc.configuredBeacons.length,
      itemBuilder: (_, i) {
        final b = _svc.configuredBeacons[i];
        final addedStr =
            DateFormat('yyyy-MM-dd HH:mm').format(b.addedAt);
        return Dismissible(
          key: ValueKey(b.mac),
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
                title: const Text('Delete Beacon?'),
                content: Text('Remove "${b.checkpointName}" from saved beacons?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) => _svc.deleteBeacon(b.mac),
          child: ListTile(
            leading: const Icon(Icons.settings_bluetooth),
            title: Text(b.checkpointName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'MAC: ${b.mac}\n'
              'NS: ${b.namespace}  ID: ${b.instanceId}\n'
              'Added: $addedStr',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  // ── Actions ──

  Future<void> _togglePatrol() async {
    if (_svc.isPatrolling) {
      _svc.stopPatrolScan();
    } else {
      if (_svc.configuredBeacons.isEmpty) {
        _showSnack('No beacons configured. Configure a beacon first.');
        return;
      }
      await _svc.startPatrolScan();
    }
  }

  void _exportLog() {
    final text = _svc.exportPatrolLog();
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('Patrol log copied to clipboard (${_svc.patrolLog.length} entries).');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
