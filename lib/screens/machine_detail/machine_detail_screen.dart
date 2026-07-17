import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../models/vending_item.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ss_header_button.dart';
import '../add_report/add_report_screen.dart';

/// Dettaglio di UN distributore: lista prodotti con prezzo, pallino di
/// confidence (verde/giallo/grigio) e "confermato N giorni fa" SEMPRE visibile
/// accanto al prezzo — e' la promessa di onesta' del progetto (vedi CLAUDE.md §2).
///
/// Se l'utente e' fisicamente vicino (D6), ogni riga offre la conferma a un
/// tocco (D7): "Ancora €1,50? [Si'] [E' cambiato]".
class MachineDetailScreen extends StatefulWidget {
  final Machine machine;
  const MachineDetailScreen({super.key, required this.machine});

  @override
  State<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends State<MachineDetailScreen> {
  final _location = LocationService();
  late final FirestoreService _service;

  // Lo stream si crea UNA volta, MAI dentro build() (convenzione del progetto).
  late final Stream<List<VendingItem>> _itemsStream;

  // null = controllo posizione ancora in corso. Decide se mostrare i bottoni
  // di conferma a un tocco. NB: e' solo UI — submitReport() riverifica la
  // prossimita' da capo al momento dell'invio.
  ProximityResult? _proximity;

  // Id degli item con un invio in corso: disabilita i bottoni della riga
  // per evitare il doppio tap.
  final Set<String> _submitting = {};

  // Ultima lista emessa dallo stream: serve al bottone "Aggiungi prodotto"
  // per passare gli item correnti a add_report (controllo duplicati, D9).
  List<VendingItem> _lastItems = const [];

  // Ricerca e filtro categoria: agiscono in MEMORIA sulla lista che arriva
  // dallo stream, zero query in piu'. _query e' la copia lowercase del testo
  // (per non rifare toLowerCase a ogni riga a ogni ridisegno).
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryFilter; // null = tutte le categorie

  // Il bottone "Aggiungi prodotto" nasce esteso (icona + scritta) per farsi
  // notare, poi dopo 3 secondi si riduce alla sola icona: cosi' non resta
  // per sempre sopra i bottoni delle ultime righe (Si' / E' cambiato).
  bool _fabExtended = true;
  Timer? _fabTimer;

  // Etichetta corta del TIPO di distributore, per il badge nell'header.
  static const _typeLabels = {
    'combo': 'Misto',
    'snack': 'Snack',
    'drink': 'Bibite',
    'coffee': 'Caffè',
  };

  @override
  void initState() {
    super.initState();
    _service = FirestoreService(FirebaseFirestore.instance);
    _itemsStream = _service.itemsForMachine(widget.machine.id);
    _checkProximity();
    _fabTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _fabExtended = false);
    });
  }

  @override
  void dispose() {
    // Il controller lo possediamo noi (siamo il widget che costruisce il
    // TextField della ricerca): va rilasciato nel NOSTRO dispose.
    _searchCtrl.dispose();
    // Se l'utente esce prima dei 3 secondi, il Timer farebbe setState su una
    // schermata morta: va cancellato come le subscription.
    _fabTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkProximity() async {
    final prox = await _location.checkProximity(
      machineLat: widget.machine.geopoint.latitude,
      machineLng: widget.machine.geopoint.longitude,
    );
    if (!mounted) return; // la schermata potrebbe essere gia' stata chiusa
    setState(() => _proximity = prox);
  }

  // ============ AZIONI ============

  /// Il tap "Si'": stesso prezzo -> decideReportKind() lo classifichera'
  /// come confirm. E' il gesto frictionless che tiene freschi i dati (D7).
  Future<void> _confirmPrice(VendingItem item) =>
      _submit(item, item.currentPrice);

  /// Il tap "E' cambiato": chiede il nuovo prezzo in un dialog.
  /// showDialog restituisce un Future che si completa quando il dialog viene
  /// chiuso, col valore passato a Navigator.pop(): il prezzo, o null se
  /// l'utente annulla.
  Future<void> _askNewPrice(VendingItem item) async {
    final newPrice = await showDialog<double>(
      context: context,
      builder: (_) => _PriceDialog(title: item.productName),
    );
    if (newPrice != null) await _submit(item, newPrice);
  }

  /// Unico punto d'invio: chiama l'orchestratore e traduce l'esito in un
  /// messaggio per l'utente.
  Future<void> _submit(VendingItem item, double price) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // main.dart non ha ancora fatto il login anonimo: non si puo' scrivere
      // (le rules chiedono request.auth.uid). Meglio un messaggio di un crash.
      _showMessage('Accesso non ancora pronto, riprova tra un istante.');
      return;
    }

    setState(() => _submitting.add(item.id));
    try {
      final outcome = await _service.submitReport(
        machine: widget.machine,
        existingItem: item,
        productId: item.productId,
        productName: item.productName,
        productCategory: item.category,
        price: price,
        userId: uid,
        location: _location,
      );
      if (!mounted) return;

      _showMessage(outcome.userMessage);
    } catch (e) {
      if (mounted) _showMessage('Invio non riuscito, riprova. ($e)');
    } finally {
      if (mounted) setState(() => _submitting.remove(item.id));
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Apre add_report; se ha inviato, mostra qui l'esito (la schermata si e'
  /// gia' chiusa: uno snackbar mostrato la' morirebbe con lei).
  Future<void> _openAddReport() async {
    final outcome = await Navigator.of(context).push<ReportOutcome>(
      MaterialPageRoute(
        builder: (_) => AddReportScreen(
          machine: widget.machine,
          existingItems: _lastItems,
        ),
      ),
    );
    if (outcome != null && mounted) _showMessage(outcome.userMessage);
  }

  // ============ HELPER DI PRESENTAZIONE ============

  /// €1,50 — virgola decimale, e sempre due cifre.
  String _fmtPrice(double p) =>
      '€${p.toStringAsFixed(2).replaceAll('.', ',')}';

  /// "2 giorni fa" in forma umana. E' il mantenimento della promessa: un
  /// prezzo vecchio va DICHIARATO vecchio, mai spacciato per attuale.
  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'adesso';
    if (diff.inHours < 1) return '${diff.inMinutes} min fa';
    if (diff.inDays < 1) return '${diff.inHours} ore fa';
    if (diff.inDays == 1) return 'ieri';
    if (diff.inDays < 60) return '${diff.inDays} giorni fa';
    return '${(diff.inDays / 30).round()} mesi fa';
  }

  bool get _canOneTapConfirm => _proximity?.gpsVerified == true;

  // ============ BUILD ============

  @override
  Widget build(BuildContext context) {
    final machine = widget.machine;
    // "indirizzo · gestore" se il gestore c'e', solo l'indirizzo altrimenti.
    final addressLine = machine.operator == null
        ? machine.address
        : '${machine.address} · ${machine.operator}';

    return Scaffold(
      appBar: AppBar(
        leading: const SsBackButton(),
        title: Text(machine.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // Il badge col tipo (Misto/Snack/Bibite/Caffè), stile "vetro".
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              _typeLabels[machine.type] ?? machine.type,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
        // bottom = fascia extra sotto la riga del titolo, SEMPRE dell'AppBar
        // (quindi arancione): qui ci va l'indirizzo. PreferredSize dichiara
        // quanto e' alta, cosi' l'AppBar sa quanto spazio riservarle.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.place, size: 17, color: Colors.white70),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    addressLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // AnimatedSwitcher fa la dissolvenza tra il figlio "vecchio" e quello
      // "nuovo" quando cambiano. Per capire che SONO cambiati confronta tipo
      // e key: i due FAB hanno tipi diversi, quindi basta gia' cosi', ma le
      // ValueKey rendono l'intenzione esplicita.
      floatingActionButton: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _fabExtended
            ? FloatingActionButton.extended(
                key: const ValueKey('fab-extended'),
                onPressed: _openAddReport,
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi prodotto'),
              )
            : FloatingActionButton(
                key: const ValueKey('fab-round'),
                onPressed: _openAddReport,
                // tooltip = la scritta compare al TOCCO PROLUNGATO sul
                // bottone (stesso meccanismo del pallino di confidence).
                tooltip: 'Aggiungi prodotto',
                child: const Icon(Icons.add),
              ),
      ),
      body: Column(
        children: [
          _buildProximityBanner(),
          Expanded(
            child: StreamBuilder<List<VendingItem>>(
              stream: _itemsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Errore nel caricamento: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                // Copia ordinata per nome: l'ordine dei documenti Firestore
                // non e' garantito e le righe "salterebbero" a ogni update.
                final items = [...snapshot.data!]
                  ..sort((a, b) => a.productName.compareTo(b.productName));
                // Fotografia per il bottone "Aggiungi prodotto". Assegnazione
                // semplice, NIENTE setState: siamo dentro build().
                _lastItems = items;

                if (items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'Nessun prodotto ancora qui.\n\n'
                        'Aggiungi il primo col bottone arancione! 🍫',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                          color: SsColors.subtle,
                        ),
                      ),
                    ),
                  );
                }

                // Ricerca + categoria si applicano QUI, sulla lista completa:
                // lo stream resta intatto (i filtri sono solo presentazione).
                final visible = items.where((it) {
                  final okCategory = _categoryFilter == null ||
                      it.category == _categoryFilter;
                  final okText = _query.isEmpty ||
                      it.productName.toLowerCase().contains(_query);
                  return okCategory && okText;
                }).toList();

                return Column(
                  children: [
                    _buildFilterBar(items),
                    Expanded(
                      child: visible.isEmpty
                          ? const Center(
                              child: Text(
                                'Nessun prodotto corrisponde ai filtri.',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: SsColors.subtle,
                                ),
                              ),
                            )
                          : ListView.builder(
                              // In fondo c'e' aria extra: l'ultima card deve
                              // poter scorrere sopra il FAB, non sotto.
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 14, 100),
                              itemCount: visible.length,
                              itemBuilder: (context, i) =>
                                  _buildItemCard(visible[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Barra di ricerca + chip delle categorie, sopra la lista prodotti.
  Widget _buildFilterBar(List<VendingItem> items) {
    // Chip solo per le categorie DAVVERO presenti in questo distributore:
    // un chip che porta a una lista vuota e' rumore. L'ordine e' quello
    // fisso del catalogo categorie, non quello (casuale) degli item.
    final present = {for (final it in items) it.category};
    final cats = [
      for (final key in SsCategories.labels.keys)
        if (present.contains(key)) key,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Cerca un prodotto...',
              prefixIcon: const Icon(Icons.search, color: SsColors.subtle),
              // La ricerca ha un bordo piu' tenue e angoli piu' morbidi dei
              // campi dei form (dal prototipo): override locali sul tema.
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: SsColors.searchBorder, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: SsColors.primary, width: 2),
              ),
              // La X per svuotare compare solo quando c'e' del testo.
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, color: SsColors.subtle),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (text) =>
                setState(() => _query = text.trim().toLowerCase()),
          ),
          // I chip hanno senso solo se c'e' davvero da scegliere: con una
          // sola categoria presente filtrerebbero... niente.
          if (cats.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(top: 11),
                child: Row(
                  children: [
                    _categoryChip(null, 'Tutti'),
                    for (final c in cats) ...[
                      const SizedBox(width: 8),
                      _categoryChip(c, SsCategories.labels[c]!),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Un singolo chip: value == null significa "Tutti" (nessun filtro).
  /// Pillola custom (non ChoiceChip): selezionata = piena arancio,
  /// non selezionata = solo bordo, come nel prototipo Bold.
  Widget _categoryChip(String? value, String label) {
    final active = _categoryFilter == value;
    return OutlinedButton(
      onPressed: () => setState(() => _categoryFilter = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? SsColors.primary : Colors.transparent,
        foregroundColor: active ? Colors.white : SsColors.subtle,
        side: BorderSide(
          color: active ? SsColors.primary : SsColors.chipBorder,
          width: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  /// Fascia sotto l'AppBar che spiega se la conferma a un tocco e' attiva.
  Widget _buildProximityBanner() {
    final prox = _proximity;

    final (bg, ink, icon, text) = switch (prox) {
      null => (
          SsColors.searchBorder,
          SsColors.body,
          Icons.location_searching,
          'Controllo della posizione...',
        ),
      ProximityResult(gpsVerified: true) => (
          SsColors.okBg,
          SsColors.okInk,
          Icons.where_to_vote,
          'Sei al distributore: conferma i prezzi con un tocco.',
        ),
      ProximityResult(distanceMeters: final d?) => (
          SsColors.warnBg,
          SsColors.warnInk,
          Icons.near_me,
          'Sei a ${d.round()} m: avvicinati per confermare i prezzi.',
        ),
      _ => (
          SsColors.warnBg,
          SsColors.warnInk,
          Icons.location_disabled,
          'Posizione non disponibile: conferma a un tocco disattivata.',
        ),
    };

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 19, color: ink),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(VendingItem item) {
    final hasPrice = item.reportCount > 0 && item.lastConfirmedAt != null;
    final confidence = item.confidence(DateTime.now());
    final busy = _submitting.contains(item.id);
    final lowConfidence = confidence < 0.3;
    final catColor = SsCategories.color(item.category);

    final subLine = hasPrice
        ? (lowConfidence
            ? 'confermato ${_timeAgo(item.lastConfirmedAt!)} — da confermare'
            : 'confermato ${_timeAgo(item.lastConfirmedAt!)}')
        : 'nessun prezzo segnalato';

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      // clipBehavior: ritaglia i figli sulla forma della decoration, cosi'
      // la striscia laterale non sborda dagli angoli arrotondati.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SsColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            offset: Offset(0, 3),
            blurRadius: 10,
            color: Color(0x125A3214), // ombra calda, appena percettibile
          ),
        ],
      ),
      child: Stack(
        children: [
          // La striscia verticale col colore della categoria.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 6,
            child: ColoredBox(color: catColor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // L'icona della categoria su fondo tinta pastello.
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SsCategories.tint(item.category),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        SsCategories.icon(item.category),
                        size: 23,
                        color: catColor,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              // Il pallino di confidence: la promessa di
                              // onesta' (§2). Tooltip = long-press.
                              Tooltip(
                                message:
                                    'Affidabilità: ${(confidence * 100).round()}%',
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: SsColors.confidence(confidence),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  subLine,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: lowConfidence
                                        ? SsColors.error
                                        : SsColors.subtle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (hasPrice) ...[
                      const SizedBox(width: 8),
                      Text(
                        _fmtPrice(item.currentPrice),
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ],
                ),
                // La riga d'azione compare SOLO se il GPS certifica la
                // vicinanza: e' il gesto D7, per chi e' davanti alla macchina.
                if (_canOneTapConfirm)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.only(top: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: SsColors.cardDivider,
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: busy
                        ? const Center(
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : hasPrice
                            ? Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Ancora ${_fmtPrice(item.currentPrice)}?',
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: SsColors.body,
                                      ),
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () => _confirmPrice(item),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 8),
                                      minimumSize: Size.zero,
                                    ),
                                    child: const Text('Sì'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () => _askNewPrice(item),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      minimumSize: Size.zero,
                                    ),
                                    child: const Text('È cambiato'),
                                  ),
                                ],
                              )
                            : Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton(
                                  onPressed: () => _askNewPrice(item),
                                  child: const Text('Segnala il prezzo'),
                                ),
                              ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog "nuovo prezzo" come widget CON STATO PROPRIO.
///
/// Perche' non un semplice showDialog con un controller creato fuori?
/// Perche' il Future di showDialog si completa AL POP, ma il dialog resta
/// montato ancora qualche frame per l'animazione di chiusura: fare
/// controller.dispose() subito dopo l'await distrugge il controller mentre
/// il TextField lo sta ancora usando -> crash "_dependents.isEmpty".
/// Regola: il controller lo POSSIEDE il widget che costruisce il TextField,
/// e lo rilascia nel SUO dispose(), che Flutter chiama solo a smontaggio
/// davvero avvenuto.
class _PriceDialog extends StatefulWidget {
  final String title;
  const _PriceDialog({required this.title});

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Prezzo attuale (€)',
          hintText: 'es. 1,80',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () {
            // Virgola decimale all'italiana -> punto, poi parse.
            final parsed = double.tryParse(
                _controller.text.trim().replaceAll(',', '.'));
            if (parsed != null && parsed > 0 && parsed < 100) {
              Navigator.of(context).pop(parsed);
            }
          },
          child: const Text('Invia'),
        ),
      ],
    );
  }
}
