import 'package:flutter/material.dart';

/// Bottone dell'header "SnackSpot Bold": quadrato arrotondato, bianco
/// traslucido sull'arancio. Usato per l'aiuto (?) sulla mappa e per la
/// freccia indietro nelle schermate interne.
class SsHeaderButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;
  const SsHeaderButton({
    super.key,
    required this.icon,
    this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 24),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        // withValues(alpha:): la stessa tinta ma trasparente al 18% — il
        // "vetro smerigliato" bianco dei bottoni sull'header arancione.
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        foregroundColor: Colors.white,
        fixedSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

/// La freccia "indietro" nel linguaggio Bold, gia' pronta per `leading:`.
/// (leading = lo slot a sinistra del titolo nell'AppBar.)
class SsBackButton extends StatelessWidget {
  const SsBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: SsHeaderButton(
        icon: Icons.arrow_back,
        tooltip: 'Indietro',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
