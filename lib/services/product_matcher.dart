import 'dart:math' as math;

import '../models/product.dart';

/// Prevenzione dei typo nel catalogo canonico (D3): normalizzazione
/// dell'input e ricerca fuzzy di un prodotto somigliante PRIMA di crearne
/// uno nuovo. Tutto puro: niente Firestore, niente widget -> testabile.
///
/// Filosofia: un typo PREVENUTO vale dieci volte un typo corretto, perche'
/// la correzione a posteriori richiede un merge server-side (productName e'
/// denormalizzato sugli item, e itemId == productId rende il travaso
/// laborioso). Vedi CLAUDE.md, "Non ancora deciso / aperto".

// ============ NORMALIZZAZIONE (cosmetica, applicata al salvataggio) ============

/// Spazi ripuliti + iniziali maiuscole SOLO se l'utente ha scritto tutto
/// minuscolo ("coca cola" -> "Coca Cola"). Se ha usato maiuscole sue
/// ("KitKat", "iTea") non le tocchiamo: ne sa piu' lui di noi.
String normalizeProductName(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty || s != s.toLowerCase()) return s;
  return s
      .split(' ')
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// I formati tutti minuscoli ("33 CL" -> "33 cl"): sono unita' di misura,
/// la convenzione unica evita che "33CL" e "33cl" sembrino formati diversi.
String normalizeProductSize(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

// ============ RICERCA FUZZY ============

// Soglie di somiglianza (1.0 = identici). Il nome e' piu' severo del
// formato: "Fanta"/"Sprite" non devono somigliarsi mai, ma "33c"/"33cl"
// (typo di formato) si'. E un formato DAVVERO diverso ("50cl" vs "33cl")
// resta sotto soglia: e' un prodotto legittimamente nuovo, niente avviso.
const double _nameThreshold = 0.8;
const double _sizeThreshold = 0.7;

/// Cerca nel catalogo un prodotto cosi' somigliante (nome E formato) da far
/// sospettare che l'utente stia ricreando quello. null = nessun sospetto.
Product? findSimilarProduct(
  List<Product> catalog, {
  required String name,
  required String size,
}) {
  final nameKey = _matchKey(name);
  final sizeKey = _matchKey(size);
  if (nameKey.isEmpty) return null;

  Product? best;
  var bestScore = 0.0;
  for (final p in catalog) {
    final nameSim = _keysAlike(nameKey, _matchKey(p.name));
    if (nameSim < _nameThreshold) continue;

    final pSizeKey = _matchKey(p.size);
    final sizeSim = (sizeKey.isEmpty && pSizeKey.isEmpty)
        ? 1.0
        : _keysAlike(sizeKey, pSizeKey);
    if (sizeSim < _sizeThreshold) continue;

    final score = nameSim + sizeSim;
    if (score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

/// La "chiave di confronto": minuscolo, senza accenti, SOLO lettere e cifre.
/// Cosi' "Coca-Cola", "coca cola" e "CocaCola" collassano tutti su
/// "cocacola" e il confronto misura le differenze che contano davvero.
String _matchKey(String s) {
  const accents = {
    'à': 'a', 'á': 'a', 'è': 'e', 'é': 'e', 'ì': 'i', 'í': 'i',
    'ò': 'o', 'ó': 'o', 'ù': 'u', 'ú': 'u',
  };
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final mapped = accents[ch] ?? ch;
    if (RegExp(r'[a-z0-9]').hasMatch(mapped)) sb.write(mapped);
  }
  return sb.toString();
}

/// Somiglianza tra due chiavi in [0,1]: distanza di Levenshtein normalizzata,
/// con un bonus se una chiave CONTIENE l'altra ("cocacola" dentro
/// "cocacolazero"): l'inclusione e' un segnale forte anche quando la
/// distanza pura non basterebbe.
double _keysAlike(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final maxLen = math.max(a.length, b.length);
  if (maxLen == 0) return 1;
  var sim = 1 - _levenshtein(a, b) / maxLen;

  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  if (shorter.length >= 4 && longer.contains(shorter)) {
    sim = math.max(sim, 0.9);
  }
  return sim;
}

/// Distanza di Damerau-Levenshtein (variante OSA): numero minimo di modifiche
/// a un carattere per trasformare [a] in [b], dove le modifiche sono
/// inserisci / cancella / sostituisci / SCAMBIA due adiacenti.
/// Lo scambio ("33lc" per "33cl") e' IL typo da tastiera per eccellenza:
/// il Levenshtein puro lo conterebbe 2 e lo lascerebbe passare.
/// Programmazione dinamica riga per riga: O(len(a) * len(b)), istantaneo
/// su nomi di prodotto (10-20 caratteri).
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var prevPrev = List<int>.filled(b.length + 1, 0); // riga i-2 (per lo scambio)
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final curr = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1), // inserimento / cancellazione
        prev[j - 1] + cost,                     // sostituzione (o match)
      );
      // Scambio di adiacenti: "..lc.." <-> "..cl..".
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        curr[j] = math.min(curr[j], prevPrev[j - 2] + 1);
      }
    }
    prevPrev = prev;
    prev = curr;
  }
  return prev[b.length];
}
