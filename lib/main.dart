import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'tag_service.dart';
import 'tags_screen.dart';
import 'patrols_screen.dart';
import 'do_patrol_screen.dart';
import 'geofence_setup_screen.dart';
import 'qr_print_screen.dart';
import 'beacon_config_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  TagService().load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkpoint Scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stats
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Checkpoints', _svc.checkpoints.length, Icons.flag),
                    _stat('Patrols', _svc.patrols.length, Icons.route),
                    _stat('Runs', _svc.history.length, Icons.history),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Main actions
            _btn(Icons.flag, 'Checkpoints', 'BLE, NFC, QR, Geofence',
                Colors.blue, const TagsScreen()),
            const SizedBox(height: 10),
            _btn(Icons.route, 'Patrols', 'Create routes & run them',
                Colors.teal, const PatrolsScreen()),
            const SizedBox(height: 10),
            _btn(Icons.add_location_alt, 'Geofence Zones',
                'DAWA address + Google Maps', Colors.orange,
                const GeofenceSetupScreen()),
            const SizedBox(height: 10),
            _btn(Icons.qr_code, 'Print QR Codes', 'View & export PDF',
                Colors.purple, const QrPrintScreen()),
            const SizedBox(height: 10),
            _btn(Icons.settings_bluetooth, 'Beacon Config',
                'Connect & configure KKM/Eddystone beacon',
                Colors.deepPurple,
                const BeaconConfigScreen(targetMac: 'DD:34:02:C6:C4:45')),
            const SizedBox(height: 20),

            // Quick start patrol
            if (_svc.patrols.isNotEmpty) ...[
              const Text('Quick Start',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._svc.patrols.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: () =>
                            _push(DoPatrolScreen(patrol: p)),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                            '${p.name} (${p.checkpointIds.length} checkpoints)'),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green),
                      ),
                    ),
                  )),
            ],

            // History
            if (_svc.history.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Recent Runs',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                      onPressed: _svc.clearHistory,
                      child: const Text('Clear')),
                ],
              ),
              ..._svc.history.take(5).map((run) {
                final time =
                    DateFormat('MM/dd HH:mm').format(run.startedAt);
                final ok = run.completedAt != null;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      ok ? Icons.check_circle : Icons.cancel,
                      color: ok ? Colors.green : Colors.orange,
                      size: 20),
                  title: Text(run.patrolName,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      '$time  •  ${run.scans.length} scanned',
                      style: const TextStyle(fontSize: 11)),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.blue),
        const SizedBox(height: 4),
        Text('$count',
            style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _btn(IconData icon, String label, String sub, Color color,
      Widget screen) {
    return SizedBox(
      height: 60,
      child: FilledButton(
        onPressed: () => _push(screen),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white70)),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => setState(() {}));
  }
}
