import 'package:cloud_firestore/cloud_firestore.dart';

/// Prodotto CANONICO, globale e condiviso tra tutti i distributori (D3).
/// Senza questa entita' il confronto prezzi tra distributori e' impossibile.
class Product {
  final String id;
  final String name;
  final String? brand;
  final String size;
  final String category;
  final String? imageUrl;
  final bool verified;
  final String createdBy;

  Product({
    required this.id,
    required this.name,
    this.brand,
    required this.size,
    required this.category,
    this.imageUrl,
    required this.verified,
    required this.createdBy,
  });

  /// Nome mostrato in UI e denormalizzato su item.productName:
  /// "Coca-Cola 33cl". La taglia fa parte dell'identita' del prodotto
  /// (la lattina e la bottiglia hanno prezzi diversi).
  String get displayName => size.isEmpty ? name : '$name $size';

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Product(
      id: doc.id,
      name: d['name'] as String? ?? '',
      brand: d['brand'] as String?,
      size: d['size'] as String? ?? '',
      category: d['category'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      verified: d['verified'] as bool? ?? false,
      createdBy: d['createdBy'] as String? ?? '',
    );
  }

  static Map<String, dynamic> createMap({
    required String name,
    String? brand,
    required String size,
    required String category,
    required String createdBy,
  }) => {
    'name': name,
    'brand': brand,
    'size': size,
    'category': category,
    'imageUrl': null,
    'verified': false, // nasce non verificato (coerente con le rules)
    'createdBy': createdBy,
    'createdAt': FieldValue.serverTimestamp(),
  };
}
