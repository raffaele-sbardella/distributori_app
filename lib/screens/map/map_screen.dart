import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/machine.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../add_machine/add_machine_screen.dart';
import '../machine_detail/machine_detail_screen.dart';
import '../tutorial/tutorial_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _location = LocationService();
  final _mapController = MapController();
  late final FirestoreService _service;

  LatLng? _center;                        // null finche' non so dove partire
  Stream<List<Machine>>? _machinesStream; // segue l'AREA INQUADRATA, non l'utente
  String? _statusMessage;                 // avviso se la posizione non c'e'
  StreamSubscription<bool>? _gpsStatusSub; // ascolta accensione/spegnimento GPS
  LatLng? _userPos;                        // pallino blu "tu sei qui"
  StreamSubscription<({double lat, double lng})>? _posSub;
  bool _centeredOnFallback = false;        // partiti su Battipaglia, utente mai localizzato
  Timer? _moveDebounce;                    // anti-raffica sugli spostamenti della mappa

  @override
  void initState() {
    super.initState();
    _service = FirestoreService(FirebaseFirestore.instance);
    _initLocation();

    // Il GPS puo' essere acceso/spento MENTRE la schermata e' aperta: qui
    // REAGIAMO all'evento invece di fotografare lo stato solo all'avvio.
    // NB: .listen() (imperativo, per side-effect) e non StreamBuilder
    // (dichiarativo, per costruire UI): qui non disegniamo niente, rilanciamo
    // una procedura.
    _gpsStatusSub = _location.serviceStatusStream().listen((enabled) {
      if (enabled) {
        _initLocation(); // riprova da capo: posizione + stream se mancante
      } else {
        setState(() {
          _statusMessage = _messageFor(LocationStatus.serviceDisabled);
        });
      }
    });
  }

  @override
  void dispose() {
    // Le subscription manuali vanno SEMPRE cancellate quando la schermata
    // muore, o il listener resta vivo e lavora nel vuoto (memory leak).
    // StreamBuilder lo fa da solo; .listen() no.
    _gpsStatusSub?.cancel();
    _posSub?.cancel();
    _moveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final loc = await _location.getCurrentPosition();
    if (!mounted) return; // la schermata potrebbe essere gia' stata chiusa

    if (loc.isOk) {
      final here = LatLng(loc.position!.latitude, loc.position!.longitude);
      // ??= : parte solo la prima volta, non si duplica ai re-init.
      // onError vuoto: se il GPS sparisce lo stream erra, ma ci pensa gia'
      // il listener di serviceStatusStream a gestire la cosa.
      _posSub ??= _location.positionStream().listen(
        (p) {
          if (mounted) setState(() => _userPos = LatLng(p.lat, p.lng));
        },
        onError: (_) {},
      );
      final wasOnFallback = _centeredOnFallback;
      setState(() {
        _center = here;
        _userPos = here;       // subito visibile, senza aspettare il primo evento
        _statusMessage = null; // il GPS e' tornato: via l'avviso
        _centeredOnFallback = false;
      });
      // Se stavamo mostrando il fallback, la mappa e' gia' sullo schermo:
      // portala sull'utente. (Non al primo avvio: li' ci pensa initialCenter,
      // e il controller non e' ancora "attaccato" a una mappa.)
      // NB: qui NON tocchiamo lo stream dei distributori: move() sposta la
      // camera, e ci pensa onPositionChanged a ri-sottoscrivere sull'area.
      if (wasOnFallback) _mapController.move(here, 15);
    } else {
      // Fallback: Battipaglia. La CONSULTAZIONE non richiede GPS: mappa,
      // distributori e prezzi si vedono comunque. La posizione serve solo per
      // il pallino blu, per la conferma a un tocco e per il peso dei report.
      const fallback = LatLng(40.6100, 14.9800); // Battipaglia, circa
      setState(() {
        _center = fallback;
        _statusMessage = _messageFor(loc.status);
        // Ricorda che l'utente non e' mai stato localizzato: se il GPS
        // arriva DOPO, la mappa va portata su di lui (ramo qui sopra).
        if (_userPos == null) _centeredOnFallback = true;
      });
    }
  }

  /// (Ri)crea lo stream dei distributori sull'area attualmente INQUADRATA.
  /// I marker seguono la mappa, non la posizione dell'utente: anche da
  /// Napoli puoi consultare i distributori di Battipaglia.
  void _subscribeToVisibleArea() {
    final camera = _mapController.camera;
    // Raggio = distanza centro -> angolo visibile: il cerchio piu' piccolo
    // che copre tutto il rettangolo sullo schermo. Il clamp mette un tetto
    // quando si e' molto zoomati fuori: senza, geoflutterfire interrogherebbe
    // troppe celle geohash e scaricherebbe mezzo mondo di documenti.
    final radiusKm = const Distance().as(
      LengthUnit.Kilometer,
      camera.center,
      camera.visibleBounds.northEast,
    );
    setState(() {
      _machinesStream = _service.nearbyMachines(
        lat: camera.center.latitude,
        lng: camera.center.longitude,
        radiusKm: radiusKm.clamp(0.5, 60),
      );
    });
  }

  /// Chiamata da flutter_map A OGNI micro-spostamento della camera (decine
  /// di volte in un singolo gesto). Rifare la query Firestore ogni volta
  /// sarebbe uno spreco: il Timer fa da "debounce" — riparte da zero a ogni
  /// evento, e scatta solo quando la mappa e' ferma da 400 ms.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _moveDebounce?.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _subscribeToVisibleArea();
    });
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

  /// Long-press sulla mappa = "qui c'e' un distributore". Il punto premuto
  /// diventa la posizione del nuovo distributore, senza digitare coordinate.
  Future<void> _openAddMachine(LatLng point) async {
    // push<bool>: la schermata form "restituisce" true se ha creato davvero
    // (stesso pattern del dialog prezzo in machine_detail).
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddMachineScreen(position: point)),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Distributore aggiunto: eccolo sulla mappa!'),
      ));
    }
  }

  Marker _buildMarker(Machine m) {
    return Marker(
      point: LatLng(m.geopoint.latitude, m.geopoint.longitude),
      width: 44,
      height: 44,
      // rotate: true = il marker si CONTRO-ruota quando la mappa viene
      // ruotata, restando sempre dritto rispetto allo schermo. Senza,
      // il pin gira insieme alla mappa e finisce storto/capovolto.
      rotate: true,
      child: GestureDetector(
        onTap: () => _openDetail(m),
        child: const Icon(Icons.location_on, size: 40, color: Colors.redAccent),
      ),
    );
  }

  /// Il pallino blu "tu sei qui", stile Google Maps.
  Marker _buildUserMarker(LatLng pos) {
    return Marker(
      point: pos,
      width: 22,
      height: 22,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blue.shade600,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
        ),
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
      appBar: AppBar(
        title: const Text('SnackSpot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Come funziona',
            // Riaperto da qui, il tutorial ha onFinish null: "Fine" fa solo
            // pop e si torna alla mappa (vedi TutorialScreen).
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TutorialScreen()),
            ),
          ),
        ],
      ),
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
                // Limite allo zoom out: contain() rifiuta ogni movimento o
                // zoom che porterebbe i BORDI dell'inquadratura fuori dai
                // bounds -> mai il "grigio" oltre i confini della mappa.
                // Il livello minimo di zoom ne discende da solo, in base
                // alle dimensioni dello schermo.
                cameraConstraint: CameraConstraint.contain(
                  // Limiti della proiezione Web Mercator (le tile OSM):
                  // oltre la latitudine ~85 la mappa non esiste proprio.
                  bounds: LatLngBounds(
                    const LatLng(-85.05112878, -180),
                    const LatLng(85.05112878, 180),
                  ),
                ),
                // Prima sottoscrizione sull'area visibile: solo ORA la
                // camera esiste (_mapController.camera prima di questo
                // momento lancerebbe un errore).
                onMapReady: _subscribeToVisibleArea,
                onPositionChanged: _onPositionChanged,
                // flutter_map passa sia la posizione del dito sullo schermo
                // (tapPosition) sia le coordinate GEOGRAFICHE (point): a noi
                // serve solo la seconda.
                onLongPress: (tapPosition, point) => _openAddMachine(point),
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
                // Il pallino utente sta SOTTO i marker dei distributori
                // (l'ordine dei children = ordine di disegno): cosi' un pin
                // vicino resta sempre tappabile.
                if (_userPos != null)
                  MarkerLayer(markers: [_buildUserMarker(_userPos!)]),
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
