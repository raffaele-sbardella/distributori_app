import 'dart:ui' show Offset;

/// Clustering dei marker in spazio SCHERMO (pixel), scritto in casa.
///
/// Perche' non un plugin: sia flutter_map_marker_cluster sia
/// flutter_map_supercluster sono fermi a latlong2 0.9, incompatibile col
/// nostro latlong2 0.10 (richiesto da flutter_map 8.3) — trappola n.8.
/// Per decine di marker basta un raggruppamento "greedy" di 30 righe:
/// pura funzione, zero dipendenze, testabile in isolamento.
///
/// L'idea: due marker vanno uniti quando si SOVRAPPONGONO SULLO SCHERMO,
/// che e' una distanza in pixel, non in metri. La stessa coppia di
/// distributori e' due pin separati a zoom 17 e un cluster a zoom 12:
/// per questo il chiamante passa le posizioni gia' PROIETTATE in pixel
/// (dalla camera corrente) e il ricalcolo avviene a ogni zoom/pan.
///
/// Algoritmo greedy: si scorre la lista una volta sola; ogni elemento
/// entra nel primo cluster la cui ANCORA (la posizione del suo primo
/// membro) dista meno di [radiusPx], altrimenti fonda un cluster nuovo.
/// L'ancora resta fissa (niente baricentro mobile): piu' stabile mentre
/// si zooma, e O(n * cluster) e' istantaneo alle nostre scale.
///
/// DETERMINISMO (il dettaglio che non si vede ma si nota): il greedy
/// dipende dall'ordine di scorrimento — chi arriva prima diventa ancora.
/// Firestore/geoflutterfire pero' riconsegna i documenti in ordine DIVERSO
/// a ogni ri-sottoscrizione (cioe' a ogni pan): senza rimedio, i cluster
/// "ballano" a ogni micro-movimento della mappa. Per questo qui si ordina
/// PRIMA per posizione proiettata (x, poi y): stessa scena -> stessi
/// cluster, qualunque sia l'ordine di arrivo. E siccome un pan e' una
/// TRASLAZIONE (sposta tutti i pixel della stessa quantita'), l'ordinamento
/// per posizione non cambia muovendo la mappa.
///
/// Costrutto Dart nuovo — GENERICS su funzione: `<T>` rende la funzione
/// indipendente dal tipo concreto (Machine, o qualunque cosa nei test);
/// `positionOf` e' il "ponte" che estrae la posizione da un T senza che
/// questa funzione debba conoscerlo.
List<List<T>> clusterByPixelDistance<T>(
  Iterable<T> items, {
  required Offset Function(T) positionOf,
  required double radiusPx,
}) {
  // Coppie (item, posizione): la posizione si calcola UNA volta per item,
  // e serve sia per ordinare sia per misurare le distanze.
  final entries = [for (final item in items) (item: item, pos: positionOf(item))];
  entries.sort((a, b) {
    final byX = a.pos.dx.compareTo(b.pos.dx);
    return byX != 0 ? byX : a.pos.dy.compareTo(b.pos.dy);
  });

  final anchors = <Offset>[];
  final clusters = <List<T>>[];
  for (final entry in entries) {
    final pos = entry.pos;
    final item = entry.item;
    var placed = false;
    for (var i = 0; i < anchors.length; i++) {
      // Offset - Offset = vettore differenza; .distance = la sua lunghezza
      // (teorema di Pitagora), cioe' la distanza in pixel tra i due punti.
      if ((pos - anchors[i]).distance <= radiusPx) {
        clusters[i].add(item);
        placed = true;
        break;
      }
    }
    if (!placed) {
      anchors.add(pos);
      clusters.add([item]);
    }
  }
  return clusters;
}
