import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import '../models/machine.dart';
import '../models/product.dart';
import '../models/vending_item.dart';
import '../models/price_report.dart';
import 'location_service.dart';
import 'price_calculator.dart';

/// Decide che TIPO di report e', dato lo stato attuale dell'item.
/// Funzione PURA: niente Firestore -> testabile in isolamento.
///   null / nessun report   -> new     (primo prezzo in assoluto)
///   stesso prezzo mostrato -> confirm (il tap-a-conferma frictionless, D7)
///   prezzo diverso         -> change  (l'utente dichiara che e' cambiato)
ReportKind decideReportKind({
  required VendingItem? existing,
  required double newPrice,
}) {
  if (existing == null || existing.reportCount == 0) {
    return ReportKind.newPrice;
  }
  // Confronto in centesimi interi, come nel calculator: mai double vs double.
  final samePrice =
      (existing.currentPrice * 100).round() == (newPrice * 100).round();
  return samePrice ? ReportKind.confirm : ReportKind.change;
}

/// Cosa restituisce l'invio di un report, cosi' la UI sa che messaggio mostrare.
class ReportOutcome {
  final ReportKind kind;
  final bool gpsVerified;

  /// null quando l'invio e' stato bloccato PRIMA del controllo GPS
  /// (per ora succede solo col cooldown D19).
  final LocationStatus? locationStatus;

  /// Valorizzato SOLO se il report e' stato respinto dal cooldown (D19):
  /// dice quando l'utente potra' rifare una segnalazione su questo item.
  final DateTime? nextAllowedAt;

  const ReportOutcome({
    required this.kind,
    required this.gpsVerified,
    this.locationStatus,
    this.nextAllowedAt,
  });

  /// true = NESSUNA scrittura e' avvenuta: l'utente aveva gia' segnalato
  /// questo prodotto nelle ultime 24 ore.
  bool get rateLimited => nextAllowedAt != null;

  /// Messaggio pronto per la UI: un solo posto per tutte le schermate che
  /// inviano report (machine_detail, add_report).
  String get userMessage {
    if (rateLimited) {
      // inHours tronca (90 min -> 1): il +1 arrotonda "per eccesso umano",
      // meglio promettere un'ora in piu' che una in meno.
      final hoursLeft = nextAllowedAt!.difference(DateTime.now()).inHours + 1;
      final quando =
          hoursLeft <= 1 ? "tra meno di un'ora" : 'tra circa $hoursLeft ore';
      return 'Hai già segnalato questo prodotto nelle ultime 24 ore. '
          'Riprova $quando.';
    }
    var msg = switch (kind) {
      ReportKind.confirm => 'Grazie! Prezzo confermato.',
      ReportKind.change => 'Grazie! Cambio di prezzo registrato.',
      ReportKind.newPrice => 'Grazie! Primo prezzo registrato.',
    };
    if (!gpsVerified) {
      msg += ' (posizione non verificata: peserà meno)';
    }
    return msg;
  }
}

class FirestoreService {
  final FirebaseFirestore _db;
  FirestoreService(this._db);

  // ============ STREAM per la UI ============

  /// Distributori entro [radiusKm] dal punto dato, in TEMPO REALE.
  Stream<List<Machine>> nearbyMachines({
    required double lat,
    required double lng,
    double radiusKm = 2,
  }) {
    final geoRef = GeoCollectionReference<Map<String, dynamic>>(
      _db.collection('machines'),
    );
    final center = GeoFirePoint(GeoPoint(lat, lng));

    // subscribeWithin fa piu' query su range di geohash e le fonde in UN solo
    // stream, poi filtra per distanza reale.
    // ATTENZIONE: il nome esatto del metodo e' cambiato tra le versioni della
    // libreria (subscribeWithin / fetchWithin / within). VERIFICARE sulla
    // versione installata: e' il primo punto in cui questo file puo' non
    // compilare.
    return geoRef
        .subscribeWithin(
          center: center,
          radiusInKm: radiusKm,
          field: 'geo',
          geopointFrom: (data) =>
              (data['geo'] as Map<String, dynamic>)['geopoint'] as GeoPoint,
        )
        .map((docs) => docs
            .map(Machine.fromDoc)
            .where((m) => m.status != 'removed') // i "fantasmi" fuori dalla mappa
            .toList());
  }

  /// Crea un nuovo distributore. Le rules ricontrollano che status/goneVotes
  /// abbiano i valori forzati da Machine.createMap (D8) e che geo.geopoint
  /// sia un latlng vero.
  Future<void> createMachine({
    required double lat,
    required double lng,
    required String label,
    required String type,
    String? operator,
    required String address,
    required String userId,
  }) {
    return _db.collection('machines').add(Machine.createMap(
          lat: lat,
          lng: lng,
          label: label,
          type: type,
          operator: operator,
          address: address,
          createdBy: userId,
        ));
  }

  /// Prodotti/prezzi di UN distributore, in tempo reale (schermata dettaglio).
  Stream<List<VendingItem>> itemsForMachine(String machineId) {
    return _db
        .collection('machines').doc(machineId)
        .collection('items')
        .snapshots()
        .map((snap) => snap.docs.map(VendingItem.fromDoc).toList());
  }

  // ============ CATALOGO PRODOTTI (D3) ============

  /// Tutto il catalogo canonico, in ordine alfabetico. Nell'MVP il catalogo
  /// e' piccolo: una lettura una-tantum basta per l'autocomplete (il filtro
  /// si fa in memoria, lettera per lettera, senza query).
  Future<List<Product>> fetchProducts() async {
    final snap = await _db.collection('products').orderBy('name').get();
    return snap.docs.map(Product.fromDoc).toList();
  }

  /// Crea un prodotto canonico NUOVO. Da usare solo quando l'autocomplete
  /// non trova niente: ogni duplicato ("coca cola" vs "Coca-Cola") rompe il
  /// confronto prezzi tra distributori.
  Future<Product> createProduct({
    required String name,
    String? brand,
    required String size,
    required String category,
    required String userId,
  }) async {
    final ref = await _db.collection('products').add(Product.createMap(
          name: name,
          brand: brand,
          size: size,
          category: category,
          createdBy: userId,
        ));
    return Product(
      id: ref.id,
      name: name,
      brand: brand,
      size: size,
      category: category,
      verified: false,
      createdBy: userId,
    );
  }

  // ============ INVIO REPORT (il loop completo) ============

  /// Orchestrazione: verifica posizione -> decide il kind -> crea l'item se
  /// serve -> invia il report -> ricalcola i derivati.
  /// Un solo punto d'ingresso per la UI.
  Future<ReportOutcome> submitReport({
    required Machine machine,
    required VendingItem? existingItem,
    required String productId,
    required String productName,
    required String productCategory,
    required double price,
    required String userId,
    required LocationService location,
    String? photoUrl,
  }) async {
    final itemId = productId; // D9: un item per prodotto/distributore

    final itemRef = _db
        .collection('machines').doc(machine.id)
        .collection('items').doc(itemId);

    // 0) COOLDOWN (D19): una segnalazione per utente per item ogni 24 ore,
    //    controllata PRIMA di scrivere qualsiasi cosa.
    //    La query filtra solo per uguaglianza su userId: basta l'indice
    //    automatico. Aggiungere orderBy(timestamp) chiederebbe un indice
    //    composito (trappola n.6) senza guadagno: il "piu' recente" si trova
    //    in memoria, e i report di UN utente su UN item restano pochi per
    //    costruzione — e' proprio il cooldown a tenerli pochi.
    final mineSnap = await itemRef
        .collection('priceReports')
        .where('userId', isEqualTo: userId)
        .get();
    final nextAt = nextAllowedReportTime(
      mineSnap.docs.map(PriceReport.fromDoc).toList(),
      userId: userId,
      now: DateTime.now(),
    );
    if (nextAt != null) {
      return ReportOutcome(
        kind: decideReportKind(existing: existingItem, newPrice: price),
        gpsVerified: false,
        nextAllowedAt: nextAt,
      );
    }

    // 1) sei abbastanza vicino? (gpsVerified + distanceMeters)
    final prox = await location.checkProximity(
      machineLat: machine.geopoint.latitude,
      machineLng: machine.geopoint.longitude,
    );

    // 2) che tipo di report e'?
    final kind = decideReportKind(existing: existingItem, newPrice: price);

    // 3) dati del report (timestamp = serverTimestamp dentro createMap)
    final reportData = PriceReport.createMap(
      price: price,
      userId: userId,
      photoUrl: photoUrl,
      gpsVerified: prox.gpsVerified,
      distanceMeters: prox.distanceMeters,
      kind: kind,
    );

    // 4) se l'item non esiste ancora, crealo SENZA campi derivati (D8):
    //    li popolera' submitPriceReport dopo aver letto il primo report, cosi'
    //    anche l'item appena nato passa dallo stesso percorso di calcolo.
    if (existingItem == null) {
      await itemRef.set({
        'machineId': machine.id,
        'productId': productId,
        'productName': productName,
        'category': productCategory, // denormalizzata dal prodotto (filtro UI)
        'currency': 'EUR',
        'status': 'available',
        'reportCount': 0,
        'geohash': machine.geohash, // denormalizzato: query cross-distributore
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 5) invia il report + ricalcola currentPrice/confidenceBase/lastConfirmedAt
    await submitPriceReport(
      db: _db,
      machineId: machine.id,
      itemId: itemId,
      reportData: reportData,
    );

    return ReportOutcome(
      kind: kind,
      gpsVerified: prox.gpsVerified,
      locationStatus: prox.status,
    );
  }
}
