import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/price_report.dart';

/// Il risultato del calcolo: i campi derivati da scrivere sull'item.
class DerivedPrice {
  final double currentPrice;
  final double confidenceBase;   // parte STRUTTURALE: evidence x agreement
  final DateTime lastConfirmedAt;
  final int reportCount;

  const DerivedPrice({
    required this.currentPrice,
    required this.confidenceBase,
    required this.lastConfirmedAt,
    required this.reportCount,
  });
}

// Costanti di taratura (vedi docs/03-ALGORITMO-PREZZI.md).
const double _priceHalfLifeDays = 30; // H: emivita per la selezione del prezzo
const double _evidenceK = 2;          // k: saturazione dell'evidenza

/// ============ FUNZIONE PURA ============
/// Da una lista di report calcola i campi derivati. Nessun Firestore qui:
/// solo input -> output. Per questo e' banale da testare e riusabile tale e
/// quale nella futura Cloud Function (tradotta in TypeScript).
/// Restituisce null se non c'e' abbastanza per decidere.
DerivedPrice? computeDerived(
  List<PriceReport> reports, {
  required DateTime now,
}) {
  // Tieni solo i report con timestamp valorizzato (serverTimestamp gia' risolto).
  final valid = reports.where((r) => r.timestamp != null).toList();
  if (valid.isEmpty) return null;

  // Peso di un singolo report = recency x trust.
  double weightOf(PriceReport r) {
    final ageDays = now.difference(r.timestamp!).inMinutes / (60 * 24);
    final recency = math.pow(0.5, ageDays / _priceHalfLifeDays).toDouble();
    final wGps = r.gpsVerified ? 1.0 : 0.3;   // essere li' fisicamente pesa molto
    final wPhoto = (r.photoUrl != null) ? 1.4 : 1.0;
    const wRep = 1.0;                          // futuro: scala con la reputazione
    return recency * wGps * wPhoto * wRep;
  }

  // Raggruppa i pesi per prezzo, in CENTESIMI (int) per evitare i problemi di
  // uguaglianza tra double (0.1 + 0.2 != 0.3 in floating point).
  final scores = <int, double>{}; // centesimi -> punteggio totale
  for (final r in valid) {
    final cents = (r.price * 100).round();
    scores[cents] = (scores[cents] ?? 0) + weightOf(r);
  }

  // currentPrice = il prezzo col punteggio massimo (MODA PESATA, non media!).
  int bestCents = scores.keys.first;
  double bestScore = scores[bestCents]!;
  double totalScore = 0;
  scores.forEach((cents, score) {
    totalScore += score;
    if (score > bestScore) {
      bestScore = score;
      bestCents = cents;
    }
  });
  final currentPrice = bestCents / 100.0;

  // confidenceBase = evidence x agreement (la parte NON temporale).
  // La freshness la calcola il client al display: VendingItem.confidence().
  final evidence = bestScore / (bestScore + _evidenceK);
  final agreement = bestScore / totalScore;
  final confidenceBase = (evidence * agreement).clamp(0.0, 1.0);

  // lastConfirmedAt = il report piu' recente CHE CONCORDA col prezzo vincente
  // (non il piu' recente in assoluto: e' cio' che rende onesta la UI).
  DateTime? lastConfirmed;
  for (final r in valid) {
    if ((r.price * 100).round() != bestCents) continue;
    if (lastConfirmed == null || r.timestamp!.isAfter(lastConfirmed)) {
      lastConfirmed = r.timestamp;
    }
  }

  return DerivedPrice(
    currentPrice: currentPrice,
    confidenceBase: confidenceBase,
    lastConfirmedAt: lastConfirmed!,
    reportCount: valid.length,
  );
}

/// ============ FUNZIONE DI SERVIZIO ============
/// Invia un nuovo report e ricalcola i campi derivati dell'item.
///
/// NB: NON e' una transazione. L'SDK mobile di Firestore non puo' fare query su
/// una collection dentro una transazione, e qui dobbiamo leggere TUTTI i report
/// recenti. Quindi e' un "leggi-poi-scrivi" non perfettamente atomico.
/// Accettabile nell'MVP; risolto dalla Cloud Function nel target (D11).
Future<void> submitPriceReport({
  required FirebaseFirestore db,
  required String machineId,
  required String itemId,
  required Map<String, dynamic> reportData, // da PriceReport.createMap(...)
}) async {
  final itemRef = db
      .collection('machines').doc(machineId)
      .collection('items').doc(itemId);
  final reportsRef = itemRef.collection('priceReports');

  // 1) Aggiungi la nuova osservazione (append-only).
  await reportsRef.add(reportData);

  // 2) Rileggi i report recenti. Oltre ~6 mesi il peso e' ~0: inutile leggerli.
  final cutoff = DateTime.now().subtract(const Duration(days: 180));
  final snap = await reportsRef
      .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
      .get();
  final reports = snap.docs.map(PriceReport.fromDoc).toList();

  // 3) Calcola i derivati con la funzione pura.
  final derived = computeDerived(reports, now: DateTime.now());
  if (derived == null) return;

  // 4) Scrivi i derivati sull'item.
  await itemRef.update({
    'currentPrice': derived.currentPrice,
    'confidenceBase': derived.confidenceBase,
    'lastConfirmedAt': Timestamp.fromDate(derived.lastConfirmedAt),
    'reportCount': derived.reportCount,
  });
}

/// ============ ANTI "CONSENSO FABBRICATO" (D19) ============
/// Un utente puo' fare UNA segnalazione (conferma O cambio) per item ogni 24h.
/// Senza questo limite, confermare 10 volte il proprio prezzo gonfia
/// evidence e agreement come se fossero 10 persone diverse: per alzare la
/// confidence devono servire persone diverse, o giorni diversi.
const Duration reportCooldown = Duration(hours: 24);

/// Se [userId] ha gia' un report dentro la finestra di cooldown, restituisce
/// QUANDO potra' rifarne uno; null = via libera.
/// Funzione PURA come computeDerived: testabile in isolamento e pronta per
/// la futura Cloud Function (dove il controllo diventera' inaggirabile).
DateTime? nextAllowedReportTime(
  List<PriceReport> reports, {
  required String userId,
  required DateTime now,
}) {
  DateTime? latest;
  for (final r in reports) {
    if (r.userId != userId || r.timestamp == null) continue;
    if (latest == null || r.timestamp!.isAfter(latest)) latest = r.timestamp;
  }
  if (latest == null) return null;
  final next = latest.add(reportCooldown);
  return next.isAfter(now) ? next : null;
}
