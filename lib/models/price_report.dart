import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportKind {
  newPrice, // 'new'
  confirm,  // 'confirm'
  change;   // 'change'

  String get wire => switch (this) {
    ReportKind.newPrice => 'new',
    ReportKind.confirm => 'confirm',
    ReportKind.change => 'change',
  };
}

/// L'OSSERVAZIONE grezza (D2). Append-only: non si modifica ne' si cancella.
class PriceReport {
  final String id;
  final double price;
  final String userId;
  final DateTime? timestamp;
  final String? photoUrl;
  final bool gpsVerified;
  final double? distanceMeters;
  final ReportKind kind;
  final bool validated;

  PriceReport({
    required this.id,
    required this.price,
    required this.userId,
    this.timestamp,
    this.photoUrl,
    required this.gpsVerified,
    this.distanceMeters,
    required this.kind,
    required this.validated,
  });

  factory PriceReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return PriceReport(
      id: doc.id,
      price: (d['price'] as num?)?.toDouble() ?? 0,
      userId: d['userId'] as String? ?? '',
      timestamp: (d['timestamp'] as Timestamp?)?.toDate(),
      photoUrl: d['photoUrl'] as String?,
      gpsVerified: d['gpsVerified'] as bool? ?? false,
      distanceMeters: (d['distanceMeters'] as num?)?.toDouble(),
      kind: switch (d['kind'] as String?) {
        'confirm' => ReportKind.confirm,
        'change' => ReportKind.change,
        _ => ReportKind.newPrice,
      },
      validated: d['validated'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> createMap({
    required double price,
    required String userId,
    String? photoUrl,
    required bool gpsVerified,
    double? distanceMeters,
    required ReportKind kind,
  }) => {
    'price': price,
    'userId': userId,
    'timestamp': FieldValue.serverTimestamp(), // supera la rule timestamp == request.time
    'photoUrl': photoUrl,
    'gpsVerified': gpsVerified,
    'distanceMeters': distanceMeters,
    'kind': kind.wire,
    'validated': false, // la validazione la decide il server, mai il client
  };
}
