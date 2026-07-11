# 04 — Setup (Windows + Firebase)

> Contesto: un tentativo precedente si era bloccato su **PATH** e **autenticazione Firebase
> CLI**. Questo documento è scritto per non ripetere quegli errori.

---

## Parte A — Console Firebase (solo browser, nessuna installazione)

⚠️ **Usare un account Google PERSONALE, non aziendale.** Se leghi il progetto a un account di
lavoro rischi di perderne l'accesso, e migrare un progetto Firebase tra account è una
seccatura.

1. **`console.firebase.google.com` → Crea progetto** (es. `vendingmap-battipaglia`).
   Google Analytics: **disattivalo**, per un MVP è solo un passaggio in più senza valore.

2. **Firestore** → *Build → Firestore Database → Crea database*
   - **Location: europea** (`eur3` o `europe-west1`) — latenza + GDPR.
     ⚠️ **NON è modificabile dopo.** Scelta definitiva.
   - Parti in **test mode** solo per sbloccarti, poi vai **subito** in *Rules*, cancella
     quelle di test e incolla `firestore.rules` → **Publish**.

3. **Authentication** → *Get started → Sign-in method*
   - Abilita **Anonymous** (ingresso senza attrito) **e Google** (per salvare i contributi).
   - Vedi D14: si potrà promuovere un anonimo a Google **mantenendo lo stesso `uid`**.

4. **Storage** → ⛔ **RIMANDATO.** Richiede il piano **Blaze** (carta di credito).
   - Non è bloccante: l'MVP gira **senza foto** (D15).
   - Quando lo attiverai (**da casa, mai dal PC aziendale**): stessa region, poi incolla
     `storage.rules`. Consigliato un **budget alert** (es. 1 €) su Google Cloud.

> ❌ **NON** registrare a mano l'app Android e **NON** scaricare `google-services.json`:
> ci pensa `flutterfire configure` (passo B6). Meno passaggi manuali, meno errori.

---

## Parte B — Macchina di sviluppo (Windows)

**L'ordine conta.** Quasi tutti i blocchi passati erano problemi di **PATH**.

### B1. Flutter SDK
Estrai lo ZIP (es. `C:\src\flutter`) → aggiungi **`C:\src\flutter\bin`** al **PATH utente**.
> `flutter non è un comando riconosciuto` = quasi sempre questo.

### B2. `flutter doctor`
Ti dice cosa manca. Su Windows di solito è la **toolchain Android**:
```
# installa Android Studio, poi:
flutter doctor --android-licenses
```
> ⚠️ Accettare le licenze è lo step che **quasi tutti saltano** e che poi blocca la build.

### B3. Firebase CLI
Via Node LTS: `npm install -g firebase-tools`
> ⚠️ Se usi npm, la **cartella bin globale di npm deve essere nel PATH**.
(In alternativa esiste il binario standalone.)

### B4. FlutterFire CLI — ⚠️ **IL PATH-KILLER N.1**
```
dart pub global activate flutterfire_cli
```
L'eseguibile finisce in:
```
%USERPROFILE%\AppData\Local\Pub\Cache\bin
```
**che di DEFAULT non è nel PATH** → risultato: `flutterfire` "comando non trovato" **anche se
l'hai appena installato**. → **Aggiungi quella cartella al PATH.**

### B5. `firebase login`
> ⚠️ **Fallo da CASA, sulla tua rete, col tuo account.**
- Se il browser resta appeso: `firebase login --no-localhost`
- **Il proxy/rete aziendale da solo può bloccare l'autenticazione** — è probabilmente una
  delle cause del blocco precedente.

### B6. `flutterfire configure`
Lega l'app Flutter al progetto Firebase creato nella Parte A e genera
**`lib/firebase_options.dart`** in automatico.

---

## Parte C — `AndroidManifest.xml` (fanno perdere ore)

In `android/app/src/main/AndroidManifest.xml`, **dentro `<manifest>` e prima di
`<application>`**:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

> ⚠️ **Trappola crudele:** Flutter aggiunge `INTERNET` **solo nella build di DEBUG**. In
> sviluppo funziona tutto; poi **in release la mappa resta bianca e Firestore muto**, e cerchi
> un bug che non c'è. Senza i permessi di posizione, `Geolocator` fallisce a prescindere dal
> codice.

---

## Parte D — `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.6.0
  cloud_firestore: ^5.4.0
  firebase_auth: ^5.3.0
  # firebase_storage: ^12.3.0   # SOLO quando attiverai Blaze + foto (D15)
  flutter_map: ^7.0.2           # rendering mappa (OpenStreetMap)
  latlong2: ^0.9.1              # tipo LatLng usato da flutter_map
  geolocator: ^13.0.1           # posizione GPS + distanza
  geoflutterfire_plus: ^0.0.31  # geohash + query "vicino a me" su Firestore
```

> ⚠️ **`geoflutterfire_plus`**: il nome del metodo di query è **cambiato tra le versioni**
> (`subscribeWithin` / `fetchWithin` / `within`). **Verifica sulla versione che installi** —
> è il primo punto in cui `firestore_service.dart` potrebbe non compilare.

---

## Checklist "sono pronto a scrivere codice"

- [ ] `flutter doctor` senza errori bloccanti
- [ ] `flutterfire --version` risponde (= PATH di Pub Cache OK)
- [ ] `firebase login` completato (da casa)
- [ ] progetto Firebase creato, Firestore + Auth attivi, rules pubblicate
- [ ] `flutterfire configure` eseguito → esiste `lib/firebase_options.dart`
- [ ] i 3 permessi nel `AndroidManifest.xml`
- [ ] `flutter run` avvia l'app sull'emulatore/telefono
