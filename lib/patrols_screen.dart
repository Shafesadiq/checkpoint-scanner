import 'package:flutter/material.dart';
import 'tag_service.dart';
import 'do_patrol_screen.dart';

class PatrolsScreen extends StatefulWidget {
  const PatrolsScreen({super.key});

  @override
  State<PatrolsScreen> createState() => _PatrolsScreenState();
}

class _PatrolsScreenState extends State<PatrolsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Patrols (${_svc.patrols.length})')),
      body: _svc.patrols.isEmpty
          ? const Center(
              child: Text('No patrols yet.\nTap + to create one.',
                  textAlign: TextAlign.center))
          : ListView.builder(
              itemCount: _svc.patrols.length,
              itemBuilder: (_, i) {
                final p = _svc.patrols[i];
                final names = p.checkpointIds
                    .map((id) => _svc.byId(id)?.name ?? id)
                    .join(', ');
                return Dismissible(
                  key: ValueKey(p.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async =>
                      await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Patrol?'),
                          content: Text('Remove "${p.name}"?'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                child: const Text('Delete',
                                    style:
                                        TextStyle(color: Colors.red))),
                          ],
                        ),
                      ) ??
                      false,
                  onDismissed: (_) => _svc.deletePatrol(p.id),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.route, color: Colors.white),
                    ),
                    title: Text(p.name,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '${p.checkpointIds.length} checkpoints: $names',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: FilledButton(
                      onPressed: () => _start(p),
                      child: const Text('GO'),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _svc.checkpoints.isEmpty ? _noCheckpoints : _create,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _noCheckpoints() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Create some checkpoints first!')),
    );
  }

  void _start(Patrol p) {
    if (p.checkpointIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This patrol has no checkpoints.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DoPatrolScreen(patrol: p)),
    );
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final selected = <String>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('New Patrol'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Patrol Name',
                    hintText: 'e.g. Night Route A',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Select Checkpoints:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _svc.checkpoints.map((cp) {
                      return CheckboxListTile(
                        dense: true,
                        value: selected.contains(cp.id),
                        secondary: Icon(_iconFor(cp.type), size: 18),
                        title: Text('#${cp.id} — ${cp.name}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(cp.type.name.toUpperCase(),
                            style: const TextStyle(fontSize: 10)),
                        onChanged: (v) {
                          setD(() {
                            if (v == true) {
                              selected.add(cp.id);
                            } else {
                              selected.remove(cp.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isNotEmpty &&
                      selected.isNotEmpty) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: Text('Create (${selected.length})')),
          ],
        ),
      ),
    );

    if (ok == true) {
      await _svc.createPatrol(
        name: nameCtrl.text.trim(),
        checkpointIds: selected.toList(),
      );
    }
  }
}
