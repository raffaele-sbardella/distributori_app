import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chiave con cui salviamo su disco "il tutorial e' gia' stato visto".
/// SharedPreferences e' un piccolo archivio chiave->valore LOCALE al telefono
/// (l'equivalente di un file .ini): perfetto per flag di UI come questa.
/// NON va su Firestore: e' una proprieta' del DISPOSITIVO, non dell'utente.
const _kTutorialSeenKey = 'tutorialSeen';

/// Una pagina del tutorial: solo dati, niente logica.
/// Classe privata (il prefisso _ vale anche per le classi): fuori da questo
/// file nessuno ha bisogno di sapere com'e' fatta una pagina.
class _TutorialPage {
  final IconData icon;
  final String title;
  final String body;
  const _TutorialPage({
    required this.icon,
    required this.title,
    required this.body,
  });
}

const _pages = <_TutorialPage>[
  _TutorialPage(
    icon: Icons.storefront,
    title: 'Benvenuto su SnackSpot',
    body: 'La mappa dei distributori automatici della tua zona, con i prezzi '
        'di ogni prodotto.\n\nCosi\' scopri PRIMA di uscire di casa dove '
        'costa meno la tua merenda.\n\nI dati li inseriscono gli utenti '
        'come te: piu\' contribuisci, piu\' la mappa e\' utile a tutti.',
  ),
  _TutorialPage(
    icon: Icons.map_outlined,
    title: 'Esplora la mappa',
    body: 'Ogni pin rosso e\' un distributore. Sposta e zooma la mappa '
        'liberamente: vedrai i distributori della zona inquadrata, anche '
        'lontano da dove ti trovi.\n\nTocca un pin per aprire la lista dei '
        'suoi prodotti con i prezzi.',
  ),
  _TutorialPage(
    icon: Icons.verified_outlined,
    title: 'Prezzi con "data di scadenza"',
    body: 'Accanto a ogni prezzo trovi un pallino colorato e la scritta '
        '"confermato N giorni fa": ti dicono QUANTO fidarti di quel '
        'prezzo.\n\nVerde = confermato di recente da piu\' persone. '
        'Rosso = vecchio o mai verificato.\n\nUn prezzo datato non e\' un '
        'errore: l\'importante e\' che tu sappia che e\' datato.',
  ),
  _TutorialPage(
    icon: Icons.thumb_up_alt_outlined,
    title: 'Conferma o correggi i prezzi',
    body: 'Sei davanti al distributore? Apri un prodotto: se il prezzo e\' '
        'giusto, confermalo con UN tocco; se e\' cambiato, inserisci quello '
        'nuovo.\n\nCol GPS acceso e vicino al distributore la tua '
        'segnalazione vale di piu\'.\n\nOgni conferma tiene la mappa fresca '
        'per tutti.',
  ),
  _TutorialPage(
    icon: Icons.add_location_alt_outlined,
    title: 'Aggiungi un distributore',
    body: 'Manca un distributore che conosci?\n\nTieni premuto sulla mappa '
        'nel punto esatto in cui si trova: si apre il modulo per '
        'aggiungerlo (nome, tipo, indirizzo).\n\nPoi inserisci i primi '
        'prezzi e il gioco e\' fatto.',
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
    final theme = Theme.of(context);
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
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon,
                            size: 96, color: theme.colorScheme.primary),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          style: theme.textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          style: theme.textTheme.bodyLarge,
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
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: i == _index
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
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
                        child: const Text('Salta'),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
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
