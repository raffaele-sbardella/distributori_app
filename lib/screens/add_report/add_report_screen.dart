import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/machine.dart';
import '../../models/product.dart';
import '../../models/vending_item.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/product_matcher.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ss_header_button.dart';

/// Aggiungi un prodotto (con prezzo) a un distributore.
///
/// Il punto delicato e' il catalogo canonico (D3): l'autocomplete spinge a
/// SCEGLIERE un prodotto esistente; creare un prodotto nuovo e' possibile ma
/// e' la strada "in salita", perche' ogni duplicato ("coca cola" / "Coca-Cola")
/// rompe il confronto prezzi tra distributori.
///
/// Restituisce al chiamante il ReportOutcome (via Navigator.pop) se ha inviato.
///
/// I contenitori proposti per le bibite (D20): vocabolario CHIUSO, cosi' sul
/// contenitore i typo sono impossibili per costruzione (piu' robusto di
/// qualunque fuzzy matching) e "lattina"/"bottiglia" e' esattamente cio' che
/// la gente ricorda di un distributore.
const List<String> kDrinkContainers = ['lattina', 'bottiglia', 'vetro', 'cartone'];

class AddReportScreen extends StatefulWidget {
  final Machine machine;

  /// Item gia' presenti nel distributore: se l'utente sceglie un prodotto
  /// gia' in lista, il report diventa un confirm/change su quell'item
  /// (D9: mai due item per lo stesso prodotto).
  final List<VendingItem> existingItems;

  const AddReportScreen({
    super.key,
    required this.machine,
    required this.existingItems,
  });

  @override
  State<AddReportScreen> createState() => _AddReportScreenState();
}

class _AddReportScreenState extends State<AddReportScreen> {
  late final FirestoreService _service;
  final _location = LocationService();
  final _formKey = GlobalKey<FormState>();

  List<Product>? _catalog;   // null = ancora in caricamento
  bool _catalogError = false;

  Product? _selected;        // prodotto scelto dall'autocomplete
  bool _creating = false;    // modalita' "crea prodotto nuovo"

  final _priceCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  String _category = 'bibita';
  String? _container; // scelto dalle chips; ha senso solo se _category == 'bibita'
  bool _saving = false;

  // Il controller del campo di ricerca lo POSSIEDE il widget Autocomplete:
  // noi teniamo solo un riferimento (per leggere il testo digitato), quindi
  // NON va messo in dispose() — non e' nostro.
  TextEditingController? _searchCtrl;

  @override
  void initState() {
    super.initState();
    _service = FirestoreService(FirebaseFirestore.instance);
    _loadCatalog();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _sizeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final products = await _service.fetchProducts();
      if (mounted) setState(() => _catalog = products);
    } catch (_) {
      if (mounted) {
        setState(() {
          _catalog = [];
          _catalogError = true;
        });
      }
    }
  }

  // ============ INVIO ============

  double? _parsePrice() {
    final parsed =
        double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0 || parsed >= 100) return null;
    return parsed;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_creating && _selected == null) {
      _showMessage('Scegli un prodotto dalla lista (o creane uno nuovo).');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showMessage('Accesso non ancora pronto, riprova tra un istante.');
      return;
    }
    final price = _parsePrice()!; // il validator ha gia' garantito che c'e'

    // Paracadute anti-typo (prima di qualunque scrittura): se il nome+formato
    // digitati somigliano a un prodotto gia' in catalogo, meglio chiedere.
    // "chosen" e' il prodotto gia' esistente da usare (scelto dall'utente o
    // suggerito dal fuzzy); null = va creato.
    Product? chosen = _creating ? null : _selected;
    var newName = '';
    var newSize = '';
    if (_creating) {
      newName = normalizeProductName(_nameCtrl.text);
      newSize = _composeSize();
      final similar = findSimilarProduct(
        _catalog ?? const [],
        name: newName,
        size: newSize,
      );
      if (similar != null) {
        final useExisting = await _askUseSimilar(similar);
        if (useExisting == null) return;      // ci ha ripensato: non fare nulla
        if (useExisting) chosen = similar;    // altrimenti: crea comunque
      }
      if (!mounted) return;
    }

    setState(() => _saving = true);
    try {
      // 1) Il prodotto: gia' esistente (scelto o suggerito), o creato adesso
      //    coi valori NORMALIZZATI (spazi, maiuscole, formato minuscolo).
      final product = chosen ??
          await _service.createProduct(
            name: newName,
            brand: _brandCtrl.text.trim().isEmpty
                ? null
                : _brandCtrl.text.trim(),
            size: newSize,
            category: _category,
            userId: uid,
          );

      // 2) Se il prodotto e' GIA' un item di questo distributore, il report
      //    va su quello (confirm/change), non su un item nuovo (D9).
      VendingItem? existing;
      for (final i in widget.existingItems) {
        if (i.productId == product.id) {
          existing = i;
          break;
        }
      }

      // 3) Invio: submitReport fa tutto (prossimita' GPS, kind, item se
      //    manca, ricalcolo derivati).
      final outcome = await _service.submitReport(
        machine: widget.machine,
        existingItem: existing,
        productId: product.id,
        productName: product.displayName,
        productCategory: product.category,
        price: price,
        userId: uid,
        location: _location,
      );
      if (!mounted) return;
      Navigator.of(context).pop(outcome); // l'esito lo mostra il chiamante
    } catch (e) {
      if (mounted) {
        _showMessage('Invio non riuscito, riprova. ($e)');
        setState(() => _saving = false);
      }
    }
  }

  /// La stringa `size` salvata sul prodotto (D20). Il contenitore va tra
  /// parentesi, cosi' displayName legge "Coca-Cola (lattina) 33cl" SENZA
  /// toccare il model: size resta un'unica stringa, nessun campo nuovo su
  /// Firestore, nessuna modifica alle rules.
  String _composeSize() {
    final taglia = normalizeProductSize(_sizeCtrl.text);
    switch (_category) {
      case 'caffè':
        return ''; // il caffe' non ha formato per costruzione
      case 'bibita':
        // _container non e' mai null qui: il FormField delle chips l'ha
        // appena validato in _submit.
        return taglia.isEmpty ? '(${_container!})' : '(${_container!}) $taglia';
      default:
        return taglia; // snack / altro: formato facoltativo
    }
  }

  /// "Forse intendevi...?" — true = usa il prodotto esistente, false = crea
  /// comunque, null = annullato (tap fuori dal dialog: nessuna azione).
  /// Niente TextField ne' controller qui dentro: un AlertDialog "usa e getta"
  /// inline va benissimo (la trappola n.7 riguarda solo i controller).
  Future<bool?> _askUseSimilar(Product similar) {
    final brand = similar.brand;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forse è già in catalogo'),
        content: Text(
          'Esiste già:\n\n'
          '${similar.displayName}${brand == null ? '' : ' ($brand)'}\n\n'
          'È questo? Usarlo tiene i prezzi confrontabili tra distributori; '
          'un doppione li separa per sempre.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, crea nuovo'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sì, usa quello'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ============ BUILD ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SsBackButton(),
        title: Text(
          'Aggiungi a ${widget.machine.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _catalog == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                children: [
                  if (_catalogError)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: SsColors.warnBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: const Text(
                        'Catalogo non raggiungibile: puoi comunque creare '
                        'il prodotto a mano.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: SsColors.warnInk,
                        ),
                      ),
                    ),
                  if (!_creating) ...[
                    _buildSearchField(),
                    const SizedBox(height: 12),
                    // Il prodotto scelto: card verde di conferma, con la X
                    // per tornare a cercare.
                    if (_selected != null)
                      Container(
                        decoration: BoxDecoration(
                          color: SsColors.okBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 15, vertical: 13),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                size: 25, color: SsColors.success),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selected!.displayName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    SsCategories.label(_selected!.category),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: SsColors.okInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 20, color: SsColors.okInk),
                              onPressed: () =>
                                  setState(() => _selected = null),
                            ),
                          ],
                        ),
                      ),
                    // La via "crea nuovo" esiste ma e' volutamente in seconda
                    // fila rispetto alla ricerca (D3).
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _creating = true;
                        _selected = null;
                        // Cortesia: quello che avevi digitato nella ricerca
                        // diventa la base del nome del prodotto nuovo.
                        final typed = _searchCtrl?.text.trim() ?? '';
                        if (_nameCtrl.text.isEmpty && typed.isNotEmpty) {
                          _nameCtrl.text = typed;
                        }
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('Non lo trovi? Crea un prodotto nuovo'),
                    ),
                  ] else ...[
                    const Text(
                      'Nuovo prodotto nel catalogo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Occhio ai duplicati: se esiste già (anche scritto '
                      'diverso), torna alla ricerca e scegli quello.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: SsColors.subtle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nome *',
                        hintText: 'es. Coca-Cola',
                      ),
                      validator: (v) => (_creating &&
                              (v == null || v.trim().isEmpty))
                          ? 'Il nome serve'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // La categoria PRIMA del formato: e' lei a decidere
                    // quali campi compaiono sotto (D20).
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                      ),
                      items: [
                        for (final e in SsCategories.labels.entries)
                          DropdownMenuItem(
                              value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) =>
                          setState(() => _category = v ?? 'bibita'),
                    ),
                    if (_category == 'bibita') ...[
                      const SizedBox(height: 16),
                      _buildContainerPicker(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _sizeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Taglia (facoltativa)',
                          hintText: 'es. 33cl, 50cl',
                        ),
                      ),
                    ] else if (_category != 'caffè') ...[
                      // Snack e altro: solo formato, facoltativo ("il pacchetto
                      // di patatine" non ha grammi che la gente ricordi).
                      // Il caffe' non ha proprio il campo.
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _sizeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Formato (facoltativo)',
                          hintText: 'es. 45g, 2 pezzi',
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _brandCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Marca (facoltativa)',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _creating = false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Torna alla ricerca nel catalogo'),
                    ),
                  ],
                  const Divider(height: 32),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Prezzo (€) *',
                      hintText: 'es. 1,50',
                      border: OutlineInputBorder(),
                    ),
                    validator: (_) => _parsePrice() == null
                        ? 'Prezzo non valido (es. 1,50)'
                        : null,
                  ),
                  const SizedBox(height: 24),
                  // Il bottone d'invio: pieno, largo tutta la pagina, angoli
                  // 18 (non pillola: e' il gesto "importante" della schermata).
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, size: 21),
                    label: Text(_saving ? 'Invio...' : 'Invia prezzo'),
                  ),
                ],
              ),
            ),
    );
  }

  /// Le chips del contenitore (solo bibite).
  ///
  /// Costrutto nuovo: `FormField<T>` e' il "genitore generico" di
  /// TextFormField — QUALUNQUE widget puo' partecipare alla validazione del
  /// Form (validator chiamato da _formKey.validate(), messaggio d'errore),
  /// non solo i campi di testo. Qui il valore vero vive in _container (stato
  /// nostro) e il FormField serve solo per validare e mostrare l'errore.
  Widget _buildContainerPicker() {
    return FormField<String>(
      validator: (_) =>
          (_creating && _category == 'bibita' && _container == null)
              ? 'Scegli il contenitore'
              : null,
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Contenitore *',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: SsColors.subtle,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in kDrinkContainers)
                ChoiceChip(
                  // Solo l'etichetta e' capitalizzata: in `size` il
                  // contenitore va minuscolo, coerente con normalizeProductSize.
                  label: Text(c[0].toUpperCase() + c.substring(1)),
                  selected: _container == c,
                  onSelected: (sel) =>
                      setState(() => _container = sel ? c : null),
                ),
            ],
          ),
          if (state.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.errorText!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    // Autocomplete<T> di Material: tu gli dai le opzioni filtrate
    // (optionsBuilder) e come mostrarle (displayStringForOption), lui
    // gestisce overlay, tastiera e selezione.
    return Autocomplete<Product>(
      displayStringForOption: (p) => p.displayName,
      optionsBuilder: (TextEditingValue tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<Product>.empty();
        // Filtro in memoria su nome+marca+formato: il catalogo MVP e' piccolo.
        return _catalog!.where((p) =>
            '${p.name} ${p.brand ?? ''} ${p.size}'.toLowerCase().contains(q));
      },
      onSelected: (p) => setState(() => _selected = p),
      // Come mostrare i RISULTATI (di default sarebbe una lista piatta):
      // card bianca arrotondata, ogni riga con icona e nome della categoria.
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              // Larghezza schermo meno il padding della pagina (16+16):
              // l'overlay dell'Autocomplete non conosce il campo sottostante.
              width: MediaQuery.sizeOf(context).width - 32,
              constraints: const BoxConstraints(maxHeight: 270),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    offset: Offset(0, 3),
                    blurRadius: 10,
                    color: Color(0x145A3214),
                  ),
                ],
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final p = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 13),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: SsColors.cardDivider,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            SsCategories.icon(p.category),
                            size: 21,
                            color: SsCategories.color(p.category),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              p.displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            SsCategories.label(p.category),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: SsColors.subtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        _searchCtrl = controller; // riferimento, non proprieta' (v. sopra)
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Cerca nel catalogo',
            hintText: 'es. Coca, acqua, kinder...',
            prefixIcon: Icon(Icons.search, color: SsColors.subtle),
          ),
          // Se riscrivi dopo aver scelto, la scelta precedente decade.
          onChanged: (_) {
            if (_selected != null) setState(() => _selected = null);
          },
        );
      },
    );
  }
}
