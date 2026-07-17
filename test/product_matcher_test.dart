import 'package:flutter_test/flutter_test.dart';

import 'package:distributori_app/models/product.dart';
import 'package:distributori_app/services/product_matcher.dart';

/// Test sul paracadute anti-typo: normalizzazione + ricerca fuzzy.
/// Tutte funzioni pure: si costruisce un catalogo a mano e si guarda l'output.

Product product({
  required String id,
  required String name,
  String size = '',
  String? brand,
}) =>
    Product(
      id: id,
      name: name,
      brand: brand,
      size: size,
      category: 'bibita',
      verified: false,
      createdBy: 'u',
    );

void main() {
  group('normalizeProductName', () {
    test('spazi doppi e ai bordi spariscono', () {
      expect(normalizeProductName('  coca   cola '), 'Coca Cola');
    });

    test('tutto minuscolo -> iniziali maiuscole', () {
      expect(normalizeProductName('acqua naturale'), 'Acqua Naturale');
    });

    test('maiuscole dell\'utente RISPETTATE (KitKat non diventa Kitkat)', () {
      expect(normalizeProductName('KitKat'), 'KitKat');
    });
  });

  group('normalizeProductSize', () {
    test('minuscolo e spazi puliti: "33 CL" -> "33 cl"', () {
      expect(normalizeProductSize(' 33 CL '), '33 cl');
    });
  });

  group('findSimilarProduct', () {
    final catalog = [
      product(id: 'p1', name: 'Coca-Cola', size: '33cl'),
      product(id: 'p2', name: 'Acqua Naturale', size: '50cl'),
      product(id: 'p3', name: 'Kinder Bueno', size: '43g'),
    ];

    test('stesso prodotto scritto diverso -> trovato', () {
      final m = findSimilarProduct(catalog, name: 'coca cola', size: '33 cl');
      expect(m?.id, 'p1');
    });

    test('typo nel nome ("Cocacola") -> trovato', () {
      final m = findSimilarProduct(catalog, name: 'Cocacola', size: '33cl');
      expect(m?.id, 'p1');
    });

    test('typo nel formato ("33lc") -> trovato', () {
      final m = findSimilarProduct(catalog, name: 'Coca-Cola', size: '33lc');
      expect(m?.id, 'p1');
    });

    test('prodotto davvero nuovo -> nessun sospetto', () {
      final m = findSimilarProduct(catalog, name: 'Fanta', size: '33cl');
      expect(m, isNull);
    });

    test('stesso nome ma formato DIVERSO (50cl vs 33cl) -> legittimo, null',
        () {
      // La lattina e la bottiglia sono prodotti diversi per costruzione (D3):
      // niente avviso, altrimenti il dialog diventerebbe un fastidio fisso.
      final m = findSimilarProduct(catalog, name: 'Coca-Cola', size: '50cl');
      expect(m, isNull);
    });

    test('formato vuoto contro formato pieno -> avvisa (decide l\'utente)', () {
      // Col formato facoltativo (D20), "Kinder Bueno" senza formato DEVE far
      // scattare il dialog se in catalogo esiste "Kinder Bueno 43g":
      // il formato mancante non puo' escludere che sia lo stesso prodotto.
      final m = findSimilarProduct(catalog, name: 'kinder bueno', size: '');
      expect(m?.id, 'p3');
    });

    test('formato pieno contro catalogo senza formato -> avvisa', () {
      final withBare = [...catalog, product(id: 'p4', name: 'Mars')];
      final m = findSimilarProduct(withBare, name: 'Mars', size: '51g');
      expect(m?.id, 'p4');
    });

    test('le parentesi del contenitore non pesano nel confronto', () {
      // "(lattina) 33cl" vs "33cl": la chiave di confronto scarta i simboli,
      // e "33cl" e' contenuto in "lattina33cl" -> avviso. Utile finche' in
      // catalogo convivono la vecchia convenzione e quella nuova (D20).
      final m = findSimilarProduct(
        catalog,
        name: 'Coca-Cola',
        size: '(lattina) 33cl',
      );
      expect(m?.id, 'p1');
    });

    test('catalogo vuoto o nome vuoto -> null, senza esplodere', () {
      expect(findSimilarProduct([], name: 'Coca-Cola', size: '33cl'), isNull);
      expect(findSimilarProduct(catalog, name: '', size: ''), isNull);
    });
  });
}
