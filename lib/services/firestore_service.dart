import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import '../models/machine.dart';
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
  final LocationStatus locationStatus;
  const ReportOutcome({
    required this.kind,
    required this.gpsVerified,
    required this.locationStatus,
  });
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

  /// Prodotti/prezzi di UN distributore, in tempo reale (schermata dettaglio).
  Stream<List<VendingItem>> itemsForMachine(String machineId) {
    return _db
        .collection('machines').doc(machineId)
        .collection('items')
        .snapshots()
        .map((snap) => snap.docs.map(VendingItem.fromDoc).toList());
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
    required double price,
    required String userId,
    required LocationService location,
    String? photoUrl,
  }) async {
    final itemId = productId; // D9: un item per prodotto/distributore

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

    final itemRef = _db
        .collection('machines').doc(machine.id)
        .collection('items').doc(itemId);

    // 4) se l'item non esiste ancora, crealo SENZA campi derivati (D8):
    //    li popolera' submitPriceReport dopo aver letto il primo report, cosi'
    //    anche l'item appena nato passa dallo stesso percorso di calcolo.
    if (existingItem == null) {
      await itemRef.set({
        'machineId': machine.id,
        'productId': productId,
        'productName': productName,
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
