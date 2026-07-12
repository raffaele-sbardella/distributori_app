import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../models/vending_item.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
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

  static const _categoryLabels = {
    'bibita': 'Bibite',
    'snack': 'Snack',
    'caffè': 'Caffè',
    'altro': 'Altro',
  };

  @override
  void initState() {
    super.initState();
    _service = FirestoreService(FirebaseFirestore.instance);
    _itemsStream = _service.itemsForMachine(widget.machine.id);
    _checkProximity();
  }

  @override
  void dispose() {
    // Il controller lo possediamo noi (siamo il widget che costruisce il
    // TextField della ricerca): va rilasciato nel NOSTRO dispose.
    _searchCtrl.dispose();
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

  /// Soglie UI di 03-ALGORITMO-PREZZI.md: >0.6 verde, 0.3-0.6 giallo, <0.3 grigio.
  Color _confidenceColor(double confidence) {
    if (confidence > 0.6) return Colors.green;
    if (confidence >= 0.3) return Colors.amber;
    return Colors.grey;
  }

  bool get _canOneTapConfirm => _proximity?.gpsVerified == true;

  // ============ BUILD ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.machine.label)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddReport,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi prodotto'),
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
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nessun prodotto ancora per questo distributore.\n\n'
                        'Aggiungi il primo col bottone qui sotto!',
                        textAlign: TextAlign.center,
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
                                  'Nessun prodotto corrisponde ai filtri.'),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
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
    // fisso di _categoryLabels, non quello (casuale) degli item.
    final present = {for (final it in items) it.category};
    final cats = [
      for (final key in _categoryLabels.keys)
        if (present.contains(key)) key,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Cerca un prodotto...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(),
              // La X per svuotare compare solo quando c'e' del testo.
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
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
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    _categoryChip(null, 'Tutti'),
                    for (final c in cats) ...[
                      const SizedBox(width: 8),
                      _categoryChip(c, _categoryLabels[c]!),
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
  Widget _categoryChip(String? value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _categoryFilter == value,
      onSelected: (_) => setState(() => _categoryFilter = value),
    );
  }

  /// Fascia sotto l'AppBar che spiega se la conferma a un tocco e' attiva.
  Widget _buildProximityBanner() {
    final prox = _proximity;

    final (color, text) = switch (prox) {
      null => (Colors.grey.shade200, 'Controllo della posizione...'),
      ProximityResult(gpsVerified: true) => (
          Colors.green.shade100,
          'Sei al distributore: conferma i prezzi con un tocco.',
        ),
      ProximityResult(distanceMeters: final d?) => (
          Colors.amber.shade100,
          'Sei a ${d.round()} m: avvicinati per confermare i prezzi.',
        ),
      _ => (
          Colors.amber.shade100,
          'Posizione non disponibile: conferma a un tocco disattivata.',
        ),
    };

    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.all(10),
      child: Text(text),
    );
  }

  Widget _buildItemCard(VendingItem item) {
    final hasPrice = item.reportCount > 0 && item.lastConfirmedAt != null;
    final confidence = item.confidence(DateTime.now());
    final busy = _submitting.contains(item.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Il pallino di confidence. Tooltip = long-press per i curiosi.
                Tooltip(
                  message: 'Affidabilità: '
                      '${(confidence * 100).round()}%',
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _confidenceColor(confidence),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasPrice)
                  Text(
                    _fmtPrice(item.currentPrice),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hasPrice
                  ? (confidence < 0.3
                      ? 'confermato ${_timeAgo(item.lastConfirmedAt!)} — da confermare'
                      : 'confermato ${_timeAgo(item.lastConfirmedAt!)}')
                  : 'nessun prezzo segnalato',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
            // La riga d'azione compare SOLO se il GPS certifica la vicinanza:
            // e' il gesto D7, pensato per chi e' davanti alla macchina.
            if (_canOneTapConfirm) ...[
              const SizedBox(height: 8),
              if (busy)
                const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (hasPrice)
                Row(
                  children: [
                    Expanded(
                      child: Text('Ancora ${_fmtPrice(item.currentPrice)}?'),
                    ),
                    OutlinedButton(
                      onPressed: () => _confirmPrice(item),
                      child: const Text('Sì'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _askNewPrice(item),
                      child: const Text('È cambiato'),
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () => _askNewPrice(item),
                    child: const Text('Segnala il prezzo'),
                  ),
                ),
            ],
          ],
        ),
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
