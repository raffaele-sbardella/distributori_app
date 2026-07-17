import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ss_header_button.dart';

/// Form "nuovo distributore", aperto dal long-press sulla mappa.
/// Il punto premuto E' la posizione del distributore: niente campi lat/lng
/// da digitare a mano (fonte di errori certa).
class AddMachineScreen extends StatefulWidget {
  final LatLng position;
  const AddMachineScreen({super.key, required this.position});

  @override
  State<AddMachineScreen> createState() => _AddMachineScreenState();
}

class _AddMachineScreenState extends State<AddMachineScreen> {
  late final FirestoreService _service;
  final _location = LocationService();

  // GlobalKey: un "gancio" per parlare con lo stato del Form da fuori.
  // Serve per chiamare validate() su TUTTI i campi in un colpo solo.
  final _formKey = GlobalKey<FormState>();

  final _labelCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _operatorCtrl = TextEditingController();
  String _type = 'combo';
  bool _saving = false;

  // I valori "wire" (inglese, nel DB) e le etichette mostrate (italiano)
  // sono cose diverse fin da subito: cosi' cambiare la UI non tocca i dati.
  static const _types = {
    'combo': 'Misto (snack + bibite)',
    'snack': 'Solo snack',
    'drink': 'Solo bibite',
    'coffee': 'Caffè',
  };

  @override
  void initState() {
    super.initState();
    _service = FirestoreService(FirebaseFirestore.instance);
    _prefillAddress(); // parte in background, il form e' subito usabile
  }

  /// Reverse geocoding dal punto del long-press: l'indirizzo si compila da
  /// solo. Resta un normale campo modificabile: se il geocoder sbaglia o non
  /// risponde (offline), l'utente scrive/corregge a mano e nessuno si blocca.
  Future<void> _prefillAddress() async {
    final addr = await _location.addressFromPoint(
      widget.position.latitude,
      widget.position.longitude,
    );
    if (!mounted || addr == null) return;
    // Se nel frattempo l'utente ha gia' scritto qualcosa, non sovrascrivere.
    if (_addressCtrl.text.isNotEmpty) return;
    setState(() => _addressCtrl.text = addr);
  }

  @override
  void dispose() {
    // Ogni TextEditingController creato va rilasciato qui (stesso contratto
    // della StreamSubscription in map_screen).
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _operatorCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // validate() esegue il validator di ogni campo: se almeno uno restituisce
    // una stringa (= messaggio d'errore), torna false e la UI mostra gli
    // errori sotto i campi. Niente di valido -> non si parte nemmeno.
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showMessage('Accesso non ancora pronto, riprova tra un istante.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.createMachine(
        lat: widget.position.latitude,
        lng: widget.position.longitude,
        label: _labelCtrl.text.trim(),
        type: _type,
        // Campo facoltativo: stringa vuota -> null (nel DB "non so" e' null,
        // non stringa vuota).
        operator: _operatorCtrl.text.trim().isEmpty
            ? null
            : _operatorCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        userId: uid,
      );
      if (!mounted) return;
      // pop(true) = "creato con successo": la mappa lo usa per lo snackbar.
      // Il marker nuovo arrivera' da solo via stream realtime.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        _showMessage('Salvataggio non riuscito, riprova. ($e)');
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.position;

    return Scaffold(
      appBar: AppBar(
        leading: const SsBackButton(),
        title: const Text('Nuovo distributore'),
      ),
      body: Form(
        key: _formKey,
        // ListView invece di Column: quando la tastiera si apre lo spazio si
        // dimezza, e una Column fissa andrebbe in overflow (strisce gialle).
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
          children: [
            // Conferma visiva del punto scelto col long-press: verde = ok,
            // la posizione c'e' gia', non va digitata.
            Container(
              decoration: BoxDecoration(
                color: SsColors.okBg,
                borderRadius: BorderRadius.circular(16),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              margin: const EdgeInsets.only(bottom: 18),
              child: Row(
                children: [
                  const Icon(Icons.my_location,
                      size: 20, color: SsColors.okInk),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Posizione dal punto toccato · '
                      '${pos.latitude.toStringAsFixed(4)}, '
                      '${pos.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SsColors.okInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome / descrizione *',
                hintText: 'es. Distributore atrio Ingegneria',
              ),
              // validator: null = campo ok, stringa = messaggio d'errore.
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Serve un nome: e\' cio\' che gli altri vedranno'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Tipo',
              ),
              items: [
                for (final e in _types.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'combo'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Indirizzo',
                hintText: 'si compila da solo, correggilo se serve',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _operatorCtrl,
              decoration: const InputDecoration(
                labelText: 'Gestore (facoltativo)',
                hintText: 'es. IVS, Argenta... se leggibile sulla macchina',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save, // null = bottone disabilitato
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
                  : const Icon(Icons.add_location_alt, size: 21),
              label: Text(_saving ? 'Salvataggio...' : 'Aggiungi distributore'),
            ),
          ],
        ),
      ),
    );
  }
}
