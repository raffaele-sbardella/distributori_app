import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

// Generato da `flutterfire configure` (passo B6 di docs/04-SETUP.md).
// Finche' non lo esegui, questo import e' rosso: e' l'UNICO file che manca.
import 'firebase_options.dart';
import 'models/app_user.dart';
import 'screens/map/map_screen.dart';
import 'screens/tutorial/tutorial_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  // Obbligatorio PRIMA di qualsiasi await in main(): i plugin nativi
  // (Firebase) parlano con Android attraverso un "ponte" che esiste solo
  // dopo questa chiamata. Senza, initializeApp() crasha all'avvio.
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const DistributoriApp());
}

class DistributoriApp extends StatelessWidget {
  const DistributoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnackSpot',
      // Il tema "SnackSpot Bold" vive tutto in theme/app_theme.dart: colori,
      // font, forma di bottoni/campi/snackbar. Le schermate lo ereditano.
      theme: buildSnackSpotTheme(),
      home: const AuthGate(),
    );
  }
}

/// Cancello d'ingresso: login anonimo automatico + users/{uid} se assente,
/// PRIMA di mostrare la mappa. Cosi' tutte le schermate a valle possono
/// contare su currentUser != null (machine_detail lo usa per i report).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Il Future va tenuto nello STATO, mai creato dentro build(): stessa regola
  // degli Stream. Un FutureBuilder con un future nuovo a ogni build
  // rifarebbe il login a ogni ridisegno.
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _signInAndEnsureUserDoc();
  }

  Future<void> _signInAndEnsureUserDoc() async {
    final auth = FirebaseAuth.instance;

    // Firebase ricorda la sessione sul dispositivo: signInAnonymously() serve
    // solo al PRIMO avvio. Ai successivi currentUser e' gia' valorizzato, e
    // l'uid resta lo stesso (e restera' lo stesso anche dopo l'upgrade a
    // Google, D14: si "linka" il provider, non si cambia utente).
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    final uid = auth.currentUser!.uid;

    // Crea users/{uid} se assente. reputation/validatedContributions nascono
    // a 0 (imposto da createMap e ricontrollato dalle rules, D8).
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      await userRef.set(AppUser.createMap(displayName: 'Anonimo'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Tipico primo avvio offline: senza rete il login anonimo fallisce.
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossibile collegarsi.\nControlla la connessione e riprova.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      // setState con un future NUOVO = riprova da capo.
                      onPressed: () => setState(() {
                        _ready = _signInAndEnsureUserDoc();
                      }),
                      child: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Secondo cancello: al primo avvio su questo dispositivo, prima
        // della mappa si passa dal tutorial (flag in SharedPreferences).
        return const TutorialGate(child: MapScreen());
      },
    );
  }
}
