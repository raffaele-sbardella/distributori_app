import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/machine.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/marker_clusterer.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ss_header_button.dart';
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
        // L'ombra e' un SECONDO pin scuro, disegnato sotto e spostato di 2px.
        // NB: niente `shadows:` sull'Icon — le ombre dei glifi finiscono su
        // un layer separato e, con le trasformazioni dei marker della mappa,
        // venivano dipinte staccate dai pin (i "marker neri fantasma").
        child: Stack(
          children: [
            Transform.translate(
              offset: const Offset(0, 2),
              child: const Icon(Icons.location_on,
                  size: 40, color: Colors.black26),
            ),
            const Icon(Icons.location_on, size: 40, color: SsColors.marker),
          ],
        ),
      ),
    );
  }

  /// Il marker "cerchio col numero": N distributori sovrapposti a questo zoom.
  Marker _buildClusterMarker(List<Machine> group) {
    // Il cluster sta al BARICENTRO geografico dei membri (media di lat/lng:
    // a queste distanze la sfericita' della Terra non si vede).
    var lat = 0.0, lng = 0.0;
    for (final m in group) {
      lat += m.geopoint.latitude;
      lng += m.geopoint.longitude;
    }
    final center = LatLng(lat / group.length, lng / group.length);

    return Marker(
      point: center,
      width: 46,
      height: 46,
      rotate: true,
      child: GestureDetector(
        onTap: () => _openCluster(group),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SsColors.marker,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(blurRadius: 6, color: Colors.black38),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${group.length}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// Tap su un cluster: zooma finche' i membri si separano. Se lo zoom non
  /// li separerebbe (distributori nello stesso palazzo, punti quasi
  /// coincidenti), zoomare e' inutile: si apre la lista e si sceglie da li'.
  void _openCluster(List<Machine> group) {
    final bounds = LatLngBounds.fromPoints([
      for (final m in group)
        LatLng(m.geopoint.latitude, m.geopoint.longitude),
    ]);
    final fit = CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.all(72),
      maxZoom: 17.5, // oltre, le tile OSM non aggiungono dettaglio utile
    );
    final camera = _mapController.camera;
    // fit.fit(camera) calcola la camera che INQUADREREBBE i bounds, senza
    // muovere nulla: se lo zoom guadagnato e' briciole, meglio la lista.
    if (fit.fit(camera).zoom - camera.zoom < 0.5) {
      _showClusterSheet(group);
    } else {
      _mapController.fitCamera(fit);
    }
  }

  /// La lista dei distributori di un cluster non separabile con lo zoom.
  void _showClusterSheet(List<Machine> group) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true, // alto quanto il contenuto, non mezzo schermo
          children: [
            for (final m in group)
              ListTile(
                leading:
                    const Icon(Icons.location_on, color: SsColors.marker),
                title: Text(
                  m.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: m.address.isEmpty ? null : Text(m.address),
                onTap: () {
                  Navigator.of(context).pop(); // chiudi il foglio...
                  _openDetail(m);              // ...e apri il dettaglio
                },
              ),
          ],
        ),
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
          color: SsColors.userDot,
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
        // Titolo su due righe (nome + claim): serve piu' spazio del default.
        toolbarHeight: 76,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SnackSpot',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Prezzi veri, distributore per distributore',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SsHeaderButton(
              icon: Icons.help_outline,
              tooltip: 'Come funziona',
              // Riaperto da qui, il tutorial ha onFinish null: "Fine" fa solo
              // pop e si torna alla mappa (vedi TutorialScreen).
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TutorialScreen()),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              color: SsColors.warnBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: SsColors.warnInk,
                ),
              ),
            ),
          Expanded(
            // Stack = strati sovrapposti: la mappa sotto, la pillola-
            // suggerimento sopra. Positioned la ancora ai bordi dello Stack.
            child: Stack(
              children: [
                FlutterMap(
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
                          final machines =
                              snapshot.data ?? const <Machine>[];
                          // MapCamera.of(context) fa DUE cose: ci da' la
                          // camera corrente E registra questo builder come
                          // suo "dipendente" (meccanismo InheritedWidget,
                          // lo stesso di Theme.of): a ogni zoom/pan
                          // flutter_map lo ridisegna, e i cluster si
                          // ricalcolano sulla geometria nuova. Senza questa
                          // riga il builder girerebbe solo quando arrivano
                          // dati da Firestore.
                          final camera = MapCamera.of(context);
                          // Cluster in spazio SCHERMO: getOffsetFromOrigin
                          // proietta lat/lng in pixel alla camera corrente.
                          // 32 px: la TESTA visibile del pin e' ~24 px, non
                          // i 44 del riquadro. NB: con l'ancora fissa due
                          // membri possono distare fino a 2x il raggio, quindi
                          // il raggio va tenuto stretto o si fondono marker
                          // che a occhio sono ancora ben separati.
                          final clusters = clusterByPixelDistance(
                            machines,
                            positionOf: (m) => camera.getOffsetFromOrigin(
                              LatLng(m.geopoint.latitude,
                                  m.geopoint.longitude),
                            ),
                            radiusPx: 32,
                          );
                          return MarkerLayer(
                            markers: [
                              for (final group in clusters)
                                group.length == 1
                                    ? _buildMarker(group.first)
                                    : _buildClusterMarker(group),
                            ],
                          );
                        },
                      ),
                  ],
                ),
                // Il suggerimento per il long-press, sempre visibile in basso.
                // IgnorePointer: la pillola e' solo da guardare, i tocchi
                // devono ATTRAVERSARLA e arrivare alla mappa sottostante.
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 9),
                        decoration: BoxDecoration(
                          color: SsColors.snackBg,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(
                              offset: Offset(0, 4),
                              blurRadius: 14,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                        child: const Text(
                          'Tieni premuto sulla mappa per aggiungere un distributore',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SsColors.snackInk,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
