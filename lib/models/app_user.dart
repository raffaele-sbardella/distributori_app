import 'package:cloud_firestore/cloud_firestore.dart';

/// Minimale ora, ma reputation/validatedContributions esistono GIA' cosi'
/// quando aggiungerai il sistema di fiducia non dovrai migrare nulla.
class AppUser {
  final String id;
  final String displayName;
  final int reputation;
  final int validatedContributions;

  AppUser({
    required this.id,
    required this.displayName,
    required this.reputation,
    required this.validatedContributions,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return AppUser(
      id: doc.id,
      displayName: d['displayName'] as String? ?? 'Anonimo',
      reputation: (d['reputation'] as num?)?.toInt() ?? 0,
      validatedContributions:
          (d['validatedContributions'] as num?)?.toInt() ?? 0,
    );
  }

  static Map<String, dynamic> createMap({required String displayName}) => {
    'displayName': displayName,
    'reputation': 0,               // le rules impongono 0 alla creazione
    'validatedContributions': 0,
    'createdAt': FieldValue.serverTimestamp(),
  };
}
