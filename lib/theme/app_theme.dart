import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tema "SnackSpot Bold": l'unica fonte dei colori e degli stili dell'app.
/// Viene dal prototipo `SnackSpot Bold.dc.html` (claude.ai/design).
///
/// Regola: le schermate NON inventano colori. O il colore e' gia' nel
/// ThemeData (bottoni, input, snackbar...) e arriva da solo, o e' una
/// costante presa da [SsColors] / [SsCategories].
abstract final class SsColors {
  // abstract final class: non istanziabile e non estendibile — e' solo un
  // "contenitore con nome" per costanti (l'equivalente di un namespace).

  // Brand.
  static const primary = Color(0xFFF4511E); // arancio: header, bottoni pieni
  static const primaryDark = Color(0xFFC63D12); // arancio scuro: link, bottoni testo
  static const headerShadow = Color(0x59C43D12); // ombra sotto l'header (35%)

  // Superfici e testo.
  static const bg = Color(0xFFFFF6EE); // crema: sfondo di ogni schermata
  static const card = Colors.white;
  static const ink = Color(0xFF241A12); // quasi-nero caldo: testo principale
  static const body = Color(0xFF5C4D3F); // testo secondario lungo
  static const subtle = Color(0xFF8A7B6D); // etichette, hint, sottotitoli

  // Bordi (dal piu' chiaro al piu' marcato).
  static const cardDivider = Color(0xFFF4EADF); // riga dentro le card
  static const searchBorder = Color(0xFFF0E2D5); // barra di ricerca, divisori
  static const inputBorder = Color(0xFFE9D6C6); // campi dei form
  static const chipBorder = Color(0xFFE4D3C4); // chip non selezionati
  static const outlineBtn = Color(0xFFF0DACB); // bottoni con bordo

  // FAB ambra "Aggiungi prodotto".
  static const fab = Color(0xFFFFB020);
  static const fabInk = Color(0xFF3D2A00);

  // Snackbar scura su fondo crema.
  static const snackBg = Color(0xFF241A12);
  static const snackInk = Color(0xFFFFE9C7);

  // Fasce di stato: ambra = avviso, verde = tutto ok.
  static const warnBg = Color(0xFFFFE7B8);
  static const warnInk = Color(0xFF6B4A00);
  static const okBg = Color(0xFFDFF3E4);
  static const okInk = Color(0xFF1E7A3C);

  // Semantici.
  static const success = Color(0xFF2E9E5B);
  static const error = Color(0xFFC0261E);

  // Pallino di confidence (soglie di 03-ALGORITMO-PREZZI.md).
  static const confHigh = Color(0xFF2E9E5B); // > 0.6
  static const confMid = Color(0xFFF5A623); // 0.3 – 0.6
  static const confLow = Color(0xFFB0A79E); // < 0.3

  // Mappa.
  static const marker = Color(0xFFFF5252);
  static const userDot = Color(0xFF1E88E5);

  static Color confidence(double c) {
    if (c > 0.6) return confHigh;
    if (c >= 0.3) return confMid;
    return confLow;
  }
}

/// Colore, tinta di sfondo e icona di ogni categoria prodotto: le card del
/// dettaglio e i risultati della ricerca le usano identiche.
abstract final class SsCategories {
  static const labels = {
    'bibita': 'Bibite',
    'snack': 'Snack',
    'caffè': 'Caffè',
    'altro': 'Altro',
  };

  static const _colors = {
    'bibita': Color(0xFF1E88E5),
    'snack': Color(0xFFF4511E),
    'caffè': Color(0xFF8D5A3C),
    'altro': Color(0xFF78909C),
  };

  static const _tints = {
    'bibita': Color(0xFFE3F0FC),
    'snack': Color(0xFFFEE7DC),
    'caffè': Color(0xFFF0E6DF),
    'altro': Color(0xFFEAEEF0),
  };

  static const _icons = {
    'bibita': Icons.local_drink,
    'snack': Icons.cookie,
    'caffè': Icons.coffee,
    'altro': Icons.category,
  };

  // Categoria sconosciuta (item vecchi senza campo) -> stile di 'altro'.
  static Color color(String cat) => _colors[cat] ?? _colors['altro']!;
  static Color tint(String cat) => _tints[cat] ?? _tints['altro']!;
  static IconData icon(String cat) => _icons[cat] ?? _icons['altro']!;
  static String label(String cat) => labels[cat] ?? labels['altro']!;
}

/// Il ThemeData dell'app. Costruirlo in una funzione (e non inline in
/// main.dart) tiene main pulito e il tema testabile/riusabile.
ThemeData buildSnackSpotTheme() {
  // Il font del prototipo. GoogleFonts scarica e mette in cache i pesi che
  // servono al primo avvio (l'app richiede comunque la rete); se offline,
  // Flutter ripiega sul font di sistema senza errori.
  final textTheme = GoogleFonts.plusJakartaSansTextTheme().apply(
    bodyColor: SsColors.ink,
    displayColor: SsColors.ink,
  );

  final colorScheme = ColorScheme.fromSeed(
    seedColor: SsColors.primary,
  ).copyWith(
    primary: SsColors.primary,
    onPrimary: Colors.white,
    surface: SsColors.bg,
    onSurface: SsColors.ink,
    error: SsColors.error,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: SsColors.bg,
    textTheme: textTheme,

    appBarTheme: AppBarTheme(
      backgroundColor: SsColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shadowColor: SsColors.headerShadow,
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: Colors.white,
      ),
    ),

    // Campi di testo: bianchi, bordo caldo 2px, angoli 14, label che "galleggia".
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SsColors.inputBorder, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SsColors.inputBorder, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SsColors.primary, width: 2),
      ),
      labelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: SsColors.subtle,
      ),
      floatingLabelStyle: const TextStyle(
        fontWeight: FontWeight.w700,
        color: SsColors.subtle,
      ),
      hintStyle: const TextStyle(
        fontWeight: FontWeight.w500,
        color: SsColors.subtle,
      ),
    ),

    // Bottoni: pieni = pillola arancio; testo/bordo = arancio scuro.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SsColors.primary,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SsColors.primaryDark,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SsColors.primaryDark,
        side: const BorderSide(color: SsColors.outlineBtn, width: 2),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),

    // FAB ambra, quadrato arrotondato (non il cerchio Material di default).
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: SsColors.fab,
      foregroundColor: SsColors.fabInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SsColors.snackBg,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: SsColors.snackInk,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: SsColors.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: SsColors.ink,
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: SsColors.searchBorder,
      thickness: 2,
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SsColors.primary,
    ),
  );
}
