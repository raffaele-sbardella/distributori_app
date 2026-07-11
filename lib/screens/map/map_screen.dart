import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/machine.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
// TODO: da creare -> prossimo pezzo di codice
import '../machine_detail/machine_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _location = LocationService();
  final _mapController = MapController();
  late final FirestoreService _service;

  LatLng? _center;                        // null finche' non ho la posizione
  Stream<List<Machine>>? _machinesStream; // creato UNA volta, quando ho il centro
  String? _statusMessage;                 // avviso se la posizione non c'e'

  @override
  void initState() {
    super.initState();
    _service = FirestoreService(FirebaseFirestore.instance);
    _initLocation();
  }

  Future<void> _initLocation() async {
    final loc = await _location.getCurrentPosition();
    if (!mounted) return; // la schermata potrebbe essere gia' stata chiusa

    if (loc.isOk) {
      final here = LatLng(loc.position!.latitude, loc.position!.longitude);
      setState(() {
        _center = here;
        // Lo stream si crea UNA volta, MAI dentro build(): altrimenti verrebbe
        // ri-sottoscritto a ogni ridisegno.
        _machinesStream = _service.nearbyMachines(
          lat: here.latitude,
          lng: here.longitude,
          radiusKm: 2,
        );
      });
    } else {
      // Fallback: centro su Battipaglia, senza lo stream "vicino a me".
      setState(() {
        _center = const LatLng(40.6100, 14.9800); // Battipaglia, circa
        _statusMessage = _messageFor(loc.status);
      });
    }
  }

  String _messageFor(LocationStatus s) => switch (s) {
        LocationStatus.serviceDisabled =>
          'GPS spento: attivalo per vedere i distributori vicino a te.',
        LocationStatus.permissionDeniedForever =>
          'Permesso negato: abilitalo dalle impostazioni del telefono.',
        LocationStatus.permissionDenied =>
          'Serve il permesso di posizione per la ricerca "vicino a te".',
        _ => 'Posizione non disponibile al momento.',
      };

  void _openDetail(Machine m) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MachineDetailScreen(machine: m)),
    );
  }

  Marker _buildMarker(Machine m) {
    return Marker(
      point: LatLng(m.geopoint.latitude, m.geopoint.longitude),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _openDetail(m),
        child: const Icon(Icons.location_on, size: 40, color: Colors.redAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_center == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Distributori vicino a te')),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(10),
              child: Text(_statusMessage!),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center!,
                initialZoom: 15,
              ),
              children: [
                // Lo sfondo: le "tile" di OpenStreetMap.
                // NB: la usage policy di OSM vieta il traffico da app in scala.
                // Se l'app cresce -> cambiare urlTemplate (MapTiler, ecc). D18.
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.distributori_app',
                ),
                // I marker: uno StreamBuilder che si ridisegna in tempo reale.
                if (_machinesStream != null)
                  StreamBuilder<List<Machine>>(
                    stream: _machinesStream,
                    builder: (context, snapshot) {
                      final machines = snapshot.data ?? const <Machine>[];
                      return MarkerLayer(
                        markers: machines.map(_buildMarker).toList(),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
