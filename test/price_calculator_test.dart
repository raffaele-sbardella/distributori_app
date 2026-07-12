import 'package:flutter_test/flutter_test.dart';

import 'package:distributori_app/models/price_report.dart';
import 'package:distributori_app/models/vending_item.dart';
import 'package:distributori_app/services/price_calculator.dart';

/// Test su computeDerived(): e' una funzione PURA (niente Firestore), quindi
/// basta costruire liste di PriceReport a mano e guardare l'output.
/// Gli scenari vengono dalle "verifiche di sanita'" di docs/03-ALGORITMO-PREZZI.md.

// "now" fisso: i test devono dare SEMPRE lo stesso risultato, mai dipendere
// dall'orologio di chi li esegue.
final now = DateTime(2026, 7, 11, 12);

PriceReport report({
  required double price,
  required DateTime timestamp,
  bool gps = true,
  String? photoUrl,
  String userId = 'u',
}) =>
    PriceReport(
      id: 'r',
      price: price,
      userId: userId,
      timestamp: timestamp,
      photoUrl: photoUrl,
      gpsVerified: gps,
      distanceMeters: gps ? 10 : null,
      kind: ReportKind.confirm,
      validated: false,
    );

void main() {
  test('nessun report valido -> null', () {
    expect(computeDerived([], now: now), isNull);
  });

  test('1 report fresco con GPS+foto: confidence ~0.41, mai "certezza"', () {
    // evidence = 1.4 / (1.4 + k=2) = 0.41: un solo report, per quanto ben
    // documentato, non deve bastare per il verde.
    final d = computeDerived(
      [report(price: 1.50, timestamp: now, photoUrl: 'foto.jpg')],
      now: now,
    )!;
    expect(d.currentPrice, 1.50);
    expect(d.confidenceBase, closeTo(0.41, 0.01));
  });

  test('3 conferme fresche concordi: confidence ~0.6 (verde)', () {
    final d = computeDerived(
      [
        report(price: 1.50, timestamp: now),
        report(price: 1.50, timestamp: now.subtract(const Duration(days: 1))),
        report(price: 1.50, timestamp: now.subtract(const Duration(days: 2))),
      ],
      now: now,
    )!;
    expect(d.currentPrice, 1.50);
    // score ~= 3 (recency quasi 1) -> evidence ~ 3/5, agreement = 1.
    expect(d.confidenceBase, closeTo(0.6, 0.02));
  });

  test('le stesse 3 conferme, ma vecchie di 2 mesi: confidence a terra (grigio)',
      () {
    final old = now.subtract(const Duration(days: 60));
    final d = computeDerived(
      [
        report(price: 1.50, timestamp: old),
        report(price: 1.50, timestamp: old),
        report(price: 1.50, timestamp: old),
      ],
      now: now,
    )!;
    // La confidence COMPLETA e' base x freshness, calcolata come al display
    // (VendingItem.confidence). Deve finire ampiamente sotto la soglia
    // grigia (0.3): un dato di 2 mesi fa va DICHIARATO inaffidabile.
    final item = VendingItem(
      id: 'i',
      machineId: 'm',
      productId: 'p',
      productName: 'Test',
      currentPrice: d.currentPrice,
      currency: 'EUR',
      confidenceBase: d.confidenceBase,
      lastConfirmedAt: d.lastConfirmedAt,
      reportCount: d.reportCount,
      status: 'available',
    );
    expect(item.confidence(now), lessThan(0.1));
  });

  test('MODA PESATA: 2 report con GPS battono 3 "dal divano" (D4+D6)', () {
    final d = computeDerived(
      [
        report(price: 1.50, timestamp: now),
        report(price: 1.50, timestamp: now),
        report(price: 1.80, timestamp: now, gps: false),
        report(price: 1.80, timestamp: now, gps: false),
        report(price: 1.80, timestamp: now, gps: false),
      ],
      now: now,
    )!;
    // score(1.50) = 2.0 contro score(1.80) = 3 x 0.3 = 0.9: lo spam senza
    // GPS non riesce a spostare il prezzo. E l'agreement basso (prezzo
    // conteso) deve comunque schiacciare la confidence.
    expect(d.currentPrice, 1.50);
    expect(d.confidenceBase, lessThan(0.5));
  });

  test('lastConfirmedAt = report piu recente CHE CONCORDA, non il piu recente',
      () {
    final weekAgo = now.subtract(const Duration(days: 7));
    final d = computeDerived(
      [
        report(price: 1.50, timestamp: weekAgo),
        report(price: 1.50, timestamp: weekAgo),
        report(price: 1.50, timestamp: weekAgo),
        // Ieri qualcuno ha detto 9.99: NON deve "ringiovanire" il prezzo 1.50.
        report(price: 9.99, timestamp: now.subtract(const Duration(days: 1)),
            gps: false),
      ],
      now: now,
    )!;
    expect(d.currentPrice, 1.50);
    expect(d.lastConfirmedAt, weekAgo); // e' l'onesta' della UI (doc 03)
  });

  // ============ COOLDOWN (D19): 1 segnalazione per utente ogni 24h ============

  group('nextAllowedReportTime', () {
    test('nessun report -> via libera', () {
      expect(nextAllowedReportTime([], userId: 'u', now: now), isNull);
    });

    test('report di 2 ore fa -> bloccato fino a 24h DAL REPORT', () {
      final r =
          report(price: 1.50, timestamp: now.subtract(const Duration(hours: 2)));
      expect(
        nextAllowedReportTime([r], userId: 'u', now: now),
        now.add(const Duration(hours: 22)), // 24h dal report = fra 22h
      );
    });

    test('report di 25 ore fa -> via libera', () {
      final r = report(
          price: 1.50, timestamp: now.subtract(const Duration(hours: 25)));
      expect(nextAllowedReportTime([r], userId: 'u', now: now), isNull);
    });

    test('i report di ALTRI utenti non bloccano', () {
      final r = report(price: 1.50, timestamp: now, userId: 'qualcun-altro');
      expect(nextAllowedReportTime([r], userId: 'u', now: now), isNull);
    });

    test('conta il report PIU RECENTE, non il primo della lista', () {
      final reports = [
        report(price: 1.50, timestamp: now.subtract(const Duration(days: 10))),
        report(price: 1.50, timestamp: now.subtract(const Duration(hours: 1))),
        report(price: 1.50, timestamp: now.subtract(const Duration(days: 3))),
      ];
      expect(
        nextAllowedReportTime(reports, userId: 'u', now: now),
        now.add(const Duration(hours: 23)),
      );
    });
  });
}
