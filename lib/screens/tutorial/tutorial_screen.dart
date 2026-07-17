import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

/// Chiave con cui salviamo su disco "il tutorial e' gia' stato visto".
/// SharedPreferences e' un piccolo archivio chiave->valore LOCALE al telefono
/// (l'equivalente di un file .ini): perfetto per flag di UI come questa.
/// NON va su Firestore: e' una proprieta' del DISPOSITIVO, non dell'utente.
const _kTutorialSeenKey = 'tutorialSeen';

/// Una pagina del tutorial: solo dati, niente logica.
/// Classe privata (il prefisso _ vale anche per le classi): fuori da questo
/// file nessuno ha bisogno di sapere com'e' fatta una pagina.
/// Ogni pagina porta anche la sua terna di colori (fondo/icona/ombra del
/// riquadro), presa dal prototipo Bold.
class _TutorialPage {
  final IconData icon;
  final String title;
  final String body;
  final Color iconBg;
  final Color iconColor;
  final Color iconShadow;
  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.iconBg,
    required this.iconColor,
    required this.iconShadow,
  });
}

const _pages = <_TutorialPage>[
  _TutorialPage(
    icon: Icons.storefront,
    iconBg: Color(0xFFFEE7DC),
    iconColor: Color(0xFFF4511E),
    iconShadow: Color(0x47F4511E),
    title: 'Benvenuto su SnackSpot',
    body: 'La mappa dei distributori automatici della tua zona, con i prezzi '
        'di ogni prodotto.\n\nCosì scopri PRIMA di uscire di casa dove '
        'costa meno la tua merenda.\n\nI dati li inseriscono gli utenti '
        'come te: più contribuisci, più la mappa è utile a tutti.',
  ),
  _TutorialPage(
    icon: Icons.map,
    iconBg: Color(0xFFE3F0FC),
    iconColor: Color(0xFF1E88E5),
    iconShadow: Color(0x421E88E5),
    title: 'Esplora la mappa',
    body: 'Ogni pin è un distributore. Sposta e zooma la mappa '
        'liberamente: vedrai i distributori della zona inquadrata, anche '
        'lontano da dove ti trovi.\n\nTocca un pin per aprire la lista dei '
        'suoi prodotti con i prezzi.',
  ),
  _TutorialPage(
    icon: Icons.verified,
    iconBg: Color(0xFFDFF3E4),
    iconColor: Color(0xFF2E9E5B),
    iconShadow: Color(0x422E9E5B),
    title: 'Prezzi con "data di scadenza"',
    body: 'Accanto a ogni prezzo trovi un pallino colorato e la scritta '
        '"confermato N giorni fa": ti dicono QUANTO fidarti di quel '
        'prezzo.\n\nVerde = confermato di recente. Rosso/grigio = vecchio '
        'o mai verificato.\n\nUn prezzo datato non è un errore: '
        'l\'importante è saperlo.',
  ),
  _TutorialPage(
    icon: Icons.thumb_up,
    iconBg: Color(0xFFFFF0CE),
    iconColor: Color(0xFFE09600),
    iconShadow: Color(0x42E09600),
    title: 'Conferma o correggi i prezzi',
    body: 'Sei davanti al distributore? Apri un prodotto: se il prezzo è '
        'giusto, confermalo con UN tocco; se è cambiato, inserisci quello '
        'nuovo.\n\nCol GPS acceso e vicino al distributore la tua '
        'segnalazione vale di più.\n\nOgni conferma tiene la mappa fresca '
        'per tutti.',
  ),
  _TutorialPage(
    icon: Icons.add_location_alt,
    iconBg: Color(0xFFF3E6FB),
    iconColor: Color(0xFF8E4EC6),
    iconShadow: Color(0x428E4EC6),
    title: 'Aggiungi un distributore',
    body: 'Manca un distributore che conosci?\n\nTieni premuto sulla mappa '
        'nel punto esatto in cui si trova: si apre il modulo per '
        'aggiungerlo (nome, tipo, indirizzo).\n\nPoi inserisci i primi '
        'prezzi e il gioco è fatto.',
  ),
];

/// Le schermate di tutorial, sfogliabili in orizzontale.
///
/// Due modi d'uso:
///  - primo avvio: [onFinish] valorizzato -> "Inizia" chiama la callback
///    (che salva la flag e mostra la mappa);
///  - riaperta dal bottone (i) sulla mappa: [onFinish] null -> "Fine" fa
///    semplicemente pop e si torna dov'eri.
class TutorialScreen extends StatefulWidget {
  final VoidCallback? onFinish;
  const TutorialScreen({super.key, this.onFinish});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  // PageController sta a PageView come MapController sta a FlutterMap:
  // permette di comandare il widget da codice (qui: animateToPage sul
  // bottone "Avanti"). E come ogni controller, lo possiede lo State e
  // va rilasciato nel dispose() (stessa regola della trappola n.7).
  final _pageController = PageController();
  int _index = 0; // pagina corrente, per pallini e testo del bottone

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _pages.length - 1;

  void _finish() {
    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // SafeArea evita che il contenuto finisca sotto notch/barra di stato.
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // PageView = una "pagina" a schermo intero per figlio, con lo
              // swipe orizzontale gratis. onPageChanged scatta anche quando
              // l'utente sfoglia col dito, non solo col bottone.
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 34),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Il riquadro colorato dietro l'icona: ogni pagina ha
                        // la sua tinta, e l'ombra e' della STESSA tinta (piu'
                        // trasparente) — e' questo che la fa "brillare".
                        Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: page.iconBg,
                            borderRadius: BorderRadius.circular(44),
                            boxShadow: [
                              BoxShadow(
                                offset: const Offset(0, 12),
                                blurRadius: 30,
                                color: page.iconShadow,
                              ),
                            ],
                          ),
                          child: Icon(page.icon,
                              size: 80, color: page.iconColor),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          page.title,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            height: 1.6,
                            color: SsColors.body,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // I pallini indicatori: uno per pagina, quello attivo e' una
            // "pillola" piu' larga. AnimatedContainer anima da solo il
            // passaggio tra i due stati quando width/color cambiano.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _index
                          ? SsColors.primary
                          : SsColors.chipBorder,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
              child: Row(
                children: [
                  // "Salta" sparisce sull'ultima pagina: li' c'e' gia' il
                  // bottone di chiusura. Opacity+IgnorePointer invece di un
                  // if: il bottone occupa comunque il suo spazio e la riga
                  // non "salta" cambiando pagina.
                  IgnorePointer(
                    ignoring: _isLast,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isLast ? 0 : 1,
                      child: TextButton(
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: SsColors.subtle,
                        ),
                        child: const Text('Salta'),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 13),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      elevation: 5,
                      shadowColor: const Color(0x61F4511E),
                    ),
                    child: Text(_isLast
                        ? (widget.onFinish != null ? 'Inizia' : 'Fine')
                        : 'Avanti'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cancello del tutorial: mostra [child] (la mappa) solo se il tutorial e'
/// gia' stato visto su questo dispositivo, altrimenti prima il tutorial.
/// Stesso pattern di AuthGate in main.dart: un widget-guardiano che decide
/// cosa mostrare in base a uno stato letto in modo asincrono.
class TutorialGate extends StatefulWidget {
  final Widget child;
  const TutorialGate({super.key, required this.child});

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate> {
  bool? _seen; // null = sto ancora leggendo la flag da disco

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _seen = prefs.getBool(_kTutorialSeenKey) ?? false);
    }
  }

  Future<void> _markSeen() async {
    // Prima la UI (subito), poi il disco: se la scrittura fosse lenta
    // l'utente non deve aspettarla per vedere la mappa.
    setState(() => _seen = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTutorialSeenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_seen) {
      // La lettura da disco e' questione di millisecondi: uno sfondo neutro
      // basta, uno spinner qui lampeggerebbe soltanto.
      null => const Scaffold(body: SizedBox.shrink()),
      false => TutorialScreen(onFinish: _markSeen),
      true => widget.child,
    };
  }
}
