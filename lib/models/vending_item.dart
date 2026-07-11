import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Il prodotto X venduto DA QUESTO distributore a QUEL prezzo.
/// currentPrice / confidenceBase / lastConfirmedAt sono DERIVATI: si leggono,
/// non si scrivono mai a mano dal client (D8).
class VendingItem {
  final String id;
  final String machineId;
  final String productId;
  final String productName;
  final double currentPrice;    // DERIVATO
  final String currency;
  final double confidenceBase;  // DERIVATO: evidence x agreement (parte strutturale)
  final DateTime? lastConfirmedAt;
  final int reportCount;
  final String status;          // available | soldout

  VendingItem({
    required this.id,
    required this.machineId,
    required this.productId,
    required this.productName,
    required this.currentPrice,
    required this.currency,
    required this.confidenceBase,
    this.lastConfirmedAt,
    required this.reportCount,
    required this.status,
  });

  factory VendingItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return VendingItem(
      id: doc.id,
      machineId: d['machineId'] as String? ?? '',
      productId: d['productId'] as String? ?? '',
      productName: d['productName'] as String? ?? '',
      currentPrice: (d['currentPrice'] as num?)?.toDouble() ?? 0,
      currency: d['currency'] as String? ?? 'EUR',
      confidenceBase: (d['confidenceBase'] as num?)?.toDouble() ?? 0,
      lastConfirmedAt: (d['lastConfirmedAt'] as Timestamp?)?.toDate(),
      reportCount: (d['reportCount'] as num?)?.toInt() ?? 0,
      status: d['status'] as String? ?? 'available',
    );
  }

  /// Confidence "viva" (D5): la parte temporale (freshness) si calcola sul
  /// client, cosi' invecchia da sola senza riscrivere il documento.
  double confidence(DateTime now, {double confHalfLifeDays = 21}) {
    if (lastConfirmedAt == null) return 0;
    final ageDays = now.difference(lastConfirmedAt!).inMinutes / (60 * 24);
    final freshness = math.pow(0.5, ageDays / confHalfLifeDays).toDouble();
    return (confidenceBase * freshness).clamp(0.0, 1.0);
  }
}
