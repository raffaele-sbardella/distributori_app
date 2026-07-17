import 'package:flutter_test/flutter_test.dart';

import 'package:distributori_app/services/marker_clusterer.dart';

/// Test sul clustering greedy in spazio schermo. Funzione pura e generica:
/// qui i "marker" sono semplici stringhe con una posizione in una mappa.

void main() {
  group('clusterByPixelDistance', () {
    // Ogni test definisce le posizioni come pixel sullo schermo.
    List<List<String>> cluster(
      Map<String, Offset> positions, {
      double radiusPx = 48,
    }) =>
        clusterByPixelDistance(
          positions.keys,
          positionOf: (name) => positions[name]!,
          radiusPx: radiusPx,
        );

    test('lista vuota -> nessun cluster, senza esplodere', () {
      expect(cluster({}), isEmpty);
    });

    test('marker lontani -> ognuno resta un cluster da 1', () {
      final result = cluster({
        'a': const Offset(0, 0),
        'b': const Offset(500, 0),
        'c': const Offset(0, 500),
      });
      expect(result, hasLength(3));
      for (final c in result) {
        expect(c, hasLength(1));
      }
    });

    test('marker sovrapposti -> un solo cluster con tutti', () {
      final result = cluster({
        'a': const Offset(100, 100),
        'b': const Offset(110, 100),
        'c': const Offset(100, 130),
      });
      expect(result, hasLength(1));
      expect(result.single.toSet(), {'a', 'b', 'c'});
    });

    test('l\'ordine di arrivo NON conta (Firestore non lo garantisce)', () {
      // Il caso che sullo schermo si vedeva come "cluster che ballano":
      // ogni pan ri-sottoscrive lo stream e i documenti arrivano in ordine
      // diverso. Stessa scena -> stessi cluster, sempre.
      const positions = {
        'a': Offset(0, 0),
        'b': Offset(40, 0),
        'c': Offset(80, 0),
        'd': Offset(300, 300),
      };
      // Set di set: confronta i RAGGRUPPAMENTI ignorando ogni ordine.
      Set<Set<String>> canon(List<List<String>> clusters) =>
          {for (final c in clusters) c.toSet()};

      final dritto = clusterByPixelDistance(
        positions.keys.toList(),
        positionOf: (n) => positions[n]!,
        radiusPx: 48,
      );
      final rovescio = clusterByPixelDistance(
        positions.keys.toList().reversed.toList(),
        positionOf: (n) => positions[n]!,
        radiusPx: 48,
      );
      expect(canon(dritto), canon(rovescio));
      // E il raggruppamento e' quello previsto: la catena a>b>c si spezza
      // sull'ancora (vedi test sotto), d sta per conto suo.
      expect(canon(dritto), {
        {'a', 'b'},
        {'c'},
        {'d'},
      });
    });

    test('la distanza e\' euclidea, non per-asse (3-4-5 -> 50 px)', () {
      // (30, 40) dista esattamente 50 px dall'origine: dentro con raggio 50,
      // fuori con raggio 49.
      final positions = {
        'a': const Offset(0, 0),
        'b': const Offset(30, 40),
      };
      expect(cluster(positions, radiusPx: 50), [
        ['a', 'b'],
      ]);
      expect(cluster(positions, radiusPx: 49), [
        ['a'],
        ['b'],
      ]);
    });

    test('ancora FISSA sul primo membro: la catena a>b>c non si salda', () {
      // b e' vicino ad a (40 px), c e' vicino a b (40 px) ma lontano
      // dall'ANCORA a (80 px): c fonda un cluster suo. E' il comportamento
      // voluto: l'ancora fissa evita il "cluster serpente" che ingoia
      // marker via via piu' lontani.
      final result = cluster({
        'a': const Offset(0, 0),
        'b': const Offset(40, 0),
        'c': const Offset(80, 0),
      });
      expect(result, [
        ['a', 'b'],
        ['c'],
      ]);
    });
  });
}
