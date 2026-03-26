import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'tag_service.dart';

// ─── DAWA Address Suggestion ───

class AddressSuggestion {
  final String id;
  final String text;
  final double? lat;
  final double? lng;

  AddressSuggestion({
    required this.id,
    required this.text,
    this.lat,
    this.lng,
  });

  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final adresse = json['adresse'] as Map<String, dynamic>?;
    return AddressSuggestion(
      id: adresse?['id']?.toString() ?? '',
      text: (json['tekst'] as String?) ?? '',
      // DAWA: x = longitude, y = latitude (ETRS89)
      lat: (adresse?['y'] as num?)?.toDouble(),
      lng: (adresse?['x'] as num?)?.toDouble(),
    );
  }

  bool get hasCoordinates => lat != null && lng != null;
}

// ─── Geofence Setup Screen ───

class GeofenceSetupScreen extends StatefulWidget {
  const GeofenceSetupScreen({super.key});

  @override
  State<GeofenceSetupScreen> createState() => _GeofenceSetupScreenState();
}

class _GeofenceSetupScreenState extends State<GeofenceSetupScreen> {
  // ── Map ──
  GoogleMapController? _mapController;
  final LatLng _mapCenter = const LatLng(55.6761, 12.5683); // Copenhagen default
  final Set<Marker> _markers = {};
  final Set<Circle> _circles = {};

  // ── Address search ──
  final _addressCtrl = TextEditingController();
  List<AddressSuggestion> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;
  AddressSuggestion? _selectedAddress;

  // ── Geofence form ──
  final _svc = TagService();
  final _nameCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '50');
  double? _selectedLat;
  double? _selectedLng;

  @override
  void initState() {
    super.initState();
    _loadExistingZones();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _addressCtrl.dispose();
    _nameCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  void _loadExistingZones() {
    for (final cp in _svc.checkpoints) {
      if (cp.type != CheckpointType.geofence) continue;
      if (cp.latitude == null || cp.longitude == null) continue;
      final pos = LatLng(cp.latitude!, cp.longitude!);
      _markers.add(Marker(
        markerId: MarkerId(cp.id),
        position: pos,
        infoWindow: InfoWindow(
          title: cp.name,
          snippet: '#${cp.id} • ${cp.radiusMeters?.toInt() ?? 50}m',
        ),
      ));
      _circles.add(Circle(
        circleId: CircleId(cp.id),
        center: pos,
        radius: cp.radiusMeters ?? 50,
        fillColor: Colors.blue.withAlpha(40),
        strokeColor: Colors.blue,
        strokeWidth: 1,
      ));
    }
  }

  // ─── DAWA Address Search ───

  void _onAddressChanged(String value) {
    _debounce?.cancel();
    if (value.length < 2) {
      setState(() {
        _suggestions = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(value);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final url = Uri.parse(
        'https://api.dataforsyningen.dk/adresser/autocomplete'
        '?q=${Uri.encodeComponent(query)}&per_side=8',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as List;
        setState(() {
          _suggestions =
              data.map((e) => AddressSuggestion.fromJson(e)).toList();
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSuggestion(AddressSuggestion s) {
    setState(() {
      _addressCtrl.text = s.text;
      _selectedAddress = s;
      _suggestions = [];

      if (s.hasCoordinates) {
        _selectedLat = s.lat;
        _selectedLng = s.lng;
        final pos = LatLng(s.lat!, s.lng!);

        // Move map to address
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: pos, zoom: 17),
          ),
        );

        // Show a temporary marker
        _markers.removeWhere((m) => m.markerId.value == 'selected');
        _markers.add(Marker(
          markerId: const MarkerId('selected'),
          position: pos,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: s.text),
        ));

        // Show radius circle
        final radius =
            double.tryParse(_radiusCtrl.text) ?? 50;
        _circles.removeWhere((c) => c.circleId.value == 'selected');
        _circles.add(Circle(
          circleId: const CircleId('selected'),
          center: pos,
          radius: radius,
          fillColor: Colors.red.withAlpha(40),
          strokeColor: Colors.red,
          strokeWidth: 2,
        ));
      }
    });
  }

  void _onMapTap(LatLng pos) {
    setState(() {
      _selectedLat = pos.latitude;
      _selectedLng = pos.longitude;
      _selectedAddress = null;
      _addressCtrl.text =
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';

      _markers.removeWhere((m) => m.markerId.value == 'selected');
      _markers.add(Marker(
        markerId: const MarkerId('selected'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Selected location'),
      ));

      final radius = double.tryParse(_radiusCtrl.text) ?? 50;
      _circles.removeWhere((c) => c.circleId.value == 'selected');
      _circles.add(Circle(
        circleId: const CircleId('selected'),
        center: pos,
        radius: radius,
        fillColor: Colors.red.withAlpha(40),
        strokeColor: Colors.red,
        strokeWidth: 2,
      ));
    });
  }

  // ─── Save Geofence ───

  Future<void> _saveGeofence() async {
    final name = _nameCtrl.text.trim();
    final radius = double.tryParse(_radiusCtrl.text.trim());

    if (name.isEmpty) {
      _showError('Enter a checkpoint name.');
      return;
    }
    if (_selectedLat == null || _selectedLng == null) {
      _showError('Select a location by searching an address or tapping the map.');
      return;
    }
    if (radius == null || radius < 5 || radius > 500) {
      _showError('Radius must be 5-500 meters.');
      return;
    }

    final cp = Checkpoint(
      id: _svc.nextId,
      name: name,
      type: CheckpointType.geofence,
      latitude: _selectedLat,
      longitude: _selectedLng,
      radiusMeters: radius,
      createdAt: DateTime.now(),
    );
    await _svc.addCheckpoint(cp);

    final pos = LatLng(_selectedLat!, _selectedLng!);
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'selected');
      _markers.add(Marker(
        markerId: MarkerId(cp.id),
        position: pos,
        infoWindow: InfoWindow(title: name, snippet: '#${cp.id} • ${radius.toInt()}m'),
      ));
      _circles.removeWhere((c) => c.circleId.value == 'selected');
      _circles.add(Circle(
        circleId: CircleId(cp.id),
        center: pos,
        radius: radius,
        fillColor: Colors.blue.withAlpha(40),
        strokeColor: Colors.blue,
        strokeWidth: 1,
      ));

      _nameCtrl.clear();
      _addressCtrl.clear();
      _selectedLat = null;
      _selectedLng = null;
      _selectedAddress = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geofence #${cp.id} "$name" created!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Setup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Active zones',
            onPressed: _showZonesList,
          ),
        ],
      ),
      body: Column(
        children: [
          // Map (top half)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _mapCenter,
                zoom: 12,
              ),
              onMapCreated: (controller) => _mapController = controller,
              onTap: _onMapTap,
              markers: _markers,
              circles: _circles,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapType: MapType.normal,
            ),
          ),
          // Form (bottom half, scrollable)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DAWA address search
                  const Text('Search Address (DAWA)',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _addressCtrl,
                    onChanged: _onAddressChanged,
                    decoration: InputDecoration(
                      hintText: 'Type a Danish address...',
                      prefixIcon: Icon(
                        Icons.location_on,
                        color: _selectedAddress?.hasCoordinates == true
                            ? Colors.green
                            : Colors.grey,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : _selectedAddress?.hasCoordinates == true
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green, size: 20)
                              : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  // Suggestions dropdown
                  if (_suggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(20),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _suggestions.length,
                        itemBuilder: (_, i) {
                          final s = _suggestions[i];
                          return InkWell(
                            onTap: () => _selectSuggestion(s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 18, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(s.text,
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (s.hasCoordinates)
                                    const Icon(Icons.check_circle,
                                        size: 14, color: Colors.green),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Or tap the map to select a location.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  if (_selectedLat != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Selected: ${_selectedLat!.toStringAsFixed(6)}, ${_selectedLng!.toStringAsFixed(6)}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.green),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Checkpoint name
                  Text('New Checkpoint #${_svc.nextId}',
                      style:
                          const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Checkpoint Name',
                      hintText: 'e.g. Front Entrance',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _radiusCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Radius (m)',
                            hintText: '50',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saveGeofence,
                      icon: const Icon(Icons.add_location_alt),
                      label: const Text('Add Geofence'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showZonesList() {
    final zones = _svc.checkpoints
        .where((c) => c.type == CheckpointType.geofence)
        .toList();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Geofence Checkpoints (${zones.length})',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          if (zones.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No geofence checkpoints yet.'),
            )
          else
            ...zones.map((cp) => ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.orange),
                  title: Text('#${cp.id} — ${cp.name}'),
                  subtitle: Text(
                    '${cp.latitude?.toStringAsFixed(4)}, '
                    '${cp.longitude?.toStringAsFixed(4)} • ${cp.radiusMeters?.toInt() ?? 50}m',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (cp.latitude != null && cp.longitude != null) {
                      _mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: LatLng(cp.latitude!, cp.longitude!),
                            zoom: 17,
                          ),
                        ),
                      );
                    }
                  },
                )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
