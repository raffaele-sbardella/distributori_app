import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

class Machine {
  final String id;
  final GeoPoint geopoint;
  final String geohash;
  final String label;
  final String type;        // snack | drink | coffee | combo
  final String? operator;
  final String address;
  final String? photoUrl;
  final String status;      // active | empty | removed
  final int goneVotes;
  final String createdBy;
  final DateTime? createdAt;

  Machine({
    required this.id,
    required this.geopoint,
    required this.geohash,
    required this.label,
    required this.type,
    this.operator,
    required this.address,
    this.photoUrl,
    required this.status,
    required this.goneVotes,
    required this.createdBy,
    this.createdAt,
  });

  factory Machine.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final geo = d['geo'] as Map<String, dynamic>?;
    return Machine(
      id: doc.id,
      geopoint: (geo?['geopoint'] as GeoPoint?) ?? const GeoPoint(0, 0),
      geohash: (geo?['geohash'] as String?) ?? '',
      label: d['label'] as String? ?? '',
      type: d['type'] as String? ?? 'combo',
      operator: d['operator'] as String?,
      address: d['address'] as String? ?? '',
      photoUrl: d['photoUrl'] as String?,
      status: d['status'] as String? ?? 'active',
      goneVotes: (d['goneVotes'] as num?)?.toInt() ?? 0,
      createdBy: d['createdBy'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  // Mappa per la CREAZIONE. I valori vincolati (status/goneVotes) sono forzati
  // qui e ricontrollati dalle security rules. Vedi D8.
  static Map<String, dynamic> createMap({
    required double lat,
    required double lng,
    required String label,
    required String type,
    String? operator,
    required String address,
    required String createdBy,
  }) {
    final geoPoint = GeoFirePoint(GeoPoint(lat, lng));
    return {
      'geo': geoPoint.data, // -> {geohash: ..., geopoint: ...}
      'label': label,
      'type': type,
      'operator': operator,
      'address': address,
      'photoUrl': null,
      'status': 'active',
      'goneVotes': 0,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
