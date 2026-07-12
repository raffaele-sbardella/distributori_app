# CLAUDE.md — distributori_app

> Questo file è il contesto permanente del progetto. Claude Code lo legge automaticamente
> a ogni sessione. Se prendi una decisione di design nuova, **aggiornalo** (o aggiorna
> `docs/01-DECISIONI.md`), altrimenti andrà persa.

---

## 1. Cos'è il progetto

App Android (Flutter) che mappa i **distributori automatici** di una città (partenza:
**Battipaglia, SA**). Per ogni distributore l'utente vede la lista dei prodotti e i prezzi,
così può **confrontare i prezzi** tra distributori e andare al più conveniente.

I dati sono **crowdsourced**: sono gli utenti a inserire distributori, prodotti e prezzi.
Non esiste alcuna fonte ufficiale da cui importarli.

### Obiettivi (dichiarati dall'utente)
1. **Progetto reale** con ambizione di crescita, **e** pezzo di portfolio.
2. **Affidabilità dei prezzi molto importante.**
3. L'utente è disposto a fare un **seeding manuale** iniziale di pochi distributori.

### Chi ci lavora
Raffaele — background Python / ML / AI engineering. **Nessuna esperienza precedente con
Dart o Flutter**: sta imparando il linguaggio costruendo questa app.
→ Quando generi codice Dart/Flutter, **spiega i costrutti del linguaggio** che introduci
per la prima volta (null safety, `factory`, `Stream`, `StatefulWidget`, ecc.), non darli
per scontati.

---

## 2. La tensione centrale del progetto (leggere per prima cosa)

> "Prezzi molto affidabili" + "dati crowdsourced" sono in **tensione intrinseca**.

Nessuno tranne gli utenti sa quanto costa una Coca in quel distributore, ma gli utenti
aggiornano di rado. **La soluzione adottata NON è avere prezzi sempre perfetti, ma rendere
sempre visibile QUANTO un prezzo è affidabile** (come le app dei prezzi carburante).

> **Un prezzo vecchio non è un bug se è *dichiarato* vecchio. Diventa un tradimento solo
> se lo spacci per attuale.**

Da questo principio discende tutta l'architettura dati. Se una modifica futura contraddice
questo principio, è quasi certamente sbagliata.

---

## 3. Stato attuale (aggiornare man mano)

### Fatto
- [x] Modello dati Firestore progettato (`docs/02-MODELLO-DATI.md`)
- [x] Algoritmo prezzo/confidence progettato (`docs/03-ALGORITMO-PREZZI.md`)
- [x] Security rules scritte (`firestore.rules`, `storage.rules`)
- [x] Model Dart: `machine`, `product`, `vending_item`, `price_report`, `app_user`
- [x] `services/price_calculator.dart` (moda pesata + confidence)
- [x] `services/location_service.dart` (GPS + prossimità)
- [x] `services/firestore_service.dart` (stream + orchestrazione report)
- [x] `screens/map/map_screen.dart` (mappa + marker in tempo reale)
- [x] `screens/machine_detail/machine_detail_screen.dart` (lista prodotti + prezzo +
      pallino confidence + "confermato N fa" + conferma a un tocco se GPS vicino)
- [x] `main.dart`: init Firebase + `AuthGate` (login anonimo + `users/{uid}` se assente)
- [x] Dipendenze installate via `flutter pub add` (2026-07-11: firebase_core 4.11,
      cloud_firestore 6.6, firebase_auth 6.5, flutter_map 8.3, geolocator 14.0,
      geoflutterfire_plus 0.0.34 → `subscribeWithin` ESISTE, trappola n.4 evitata)
- [x] Test unitari su `computeDerived` (`test/price_calculator_test.dart`, 6 test verdi)

- [x] **Toolchain Android completa** (2026-07-11): Flutter 3.44.2, Android Studio
      2026.1.1.10, SDK 36.1.0, licenze accettate → `flutter doctor` tutto verde
- [x] Permessi in `AndroidManifest.xml` (trappola n.1 disinnescata)

- [x] **Progetto Firebase `app-distributori`** (2026-07-11): Firestore + Auth attivi,
      rules pubblicate col ramo **MVP** attivo alla riga del bivio (§6).
      **Storage NON attivo** (richiede piano Blaze — rimandato).
- [x] `flutterfire configure` → `lib/firebase_options.dart` generato, app Android
      registrata. `firebase.json` include ora `firestore.rules` → le rules si
      deployano con `firebase deploy --only firestore:rules`, niente copia-incolla.
- [x] `flutter analyze`: **zero problemi**

- [x] `screens/add_machine/add_machine_screen.dart`: form nuovo distributore da
      long-press sulla mappa (+ `FirestoreService.createMachine`) → sblocca il seeding.
      Indirizzo precompilato via reverse geocoding (`geocoding`, geocoder nativo Android)
- [x] `screens/add_report/add_report_screen.dart`: autocomplete sul catalogo (D3),
      creazione prodotto nuovo come via secondaria, prezzo → `submitReport`.
      **FASE 1 COMPLETA**: il loop core mappa→dettaglio→report è tutto scritto
- [x] Mappa: pallino blu posizione utente (positionStream), marker con `rotate: true`
- [x] **`flutter run` sul telefono**: primo avvio riuscito (2026-07-11).
      Fix a caldo: la mappa ora REAGISCE ad accensione/spegnimento del GPS
      (`serviceStatusStream` in `location_service` + subscription in `map_screen`)
- [x] **Cooldown segnalazioni (D19)**: 1 per utente/item/24h — `nextAllowedReportTime()`
      pura in `price_calculator.dart`, check in `submitReport` prima di ogni scrittura,
      esito `ReportOutcome.rateLimited`. Test inclusi (2026-07-12)
- [x] Dettaglio distributore: barra di ricerca + chip filtro categoria (in memoria).
      Il campo `category` è ora denormalizzato sugli item (come `productName`);
      item vecchi senza campo → 'altro' (2026-07-12)
- [x] Paracadute anti-typo alla creazione prodotto (`services/product_matcher.dart`,
      puro + testato): normalizzazione (spazi/maiuscole/formato) + fuzzy
      Damerau-Levenshtein sul catalogo → dialog "Forse è già in catalogo"
      con [Usa quello]/[Crea nuovo] in add_report (2026-07-12)

### Da fare (in ordine)
- [ ] **Seeding manuale di UN cluster denso a Battipaglia** ← PROSSIMO PASSO (Fase 2:
      si fa sul campo con l'app, non al PC)

### Non ancora deciso / aperto
- Quali funzioni premium sbloccare col contributo (vedi §5, decisione D13)
- Deduplica del catalogo `products` (per ora: autocomplete che spinge a scegliere)
- **Typo nei prodotti**: la PREVENZIONE è fatta (normalizzazione + avviso fuzzy in
  `product_matcher.dart`). La CORREZIONE a posteriori resta solo da console Firebase
  (le rules bloccano `update` sui products, ed è voluto); merge/rinomina come strumento
  admin server-side → Fase 4. NB: rinominare un prodotto NON basta — `productName` è
  denormalizzato sugli item.
- Query cross-distributore "prodotto X più economico entro 2 km" (serve indice
  collection-group; il campo `geohash` è già denormalizzato sugli item per questo)

---

## 4. Stack tecnico

| Cosa | Scelta | Perché |
|---|---|---|
| UI | Flutter (Android) | Un solo codebase, buon ecosistema mappe |
| Backend | Firebase / Firestore | Realtime out-of-the-box, zero server da gestire |
| Auth | Firebase Auth: **anonimo + Google** | Anonimo = zero attrito all'ingresso; Google = per "salvare" i contributi |
| Mappa (rendering) | `flutter_map` + tile OpenStreetMap | Gratis, nessuna API key |
| Query geografiche | `geoflutterfire_plus` | Firestore **non ha** query geo native: serve geohash |
| GPS | `geolocator` | Posizione + `distanceBetween` |
| Storage foto | `firebase_storage` — **RIMANDATO** | Richiede piano Blaze (carta di credito) |
| State management | **Nessuno** (`StreamBuilder` puro) | Su un MVP, Riverpod/BLoC è complessità prematura |

> ⚠️ `flutter_map` e `geoflutterfire_plus` fanno cose **diverse e indipendenti**:
> il primo *disegna* la mappa (non sa nulla di Firestore), il secondo *interroga* Firestore
> (non disegna nulla). Uno recupera i dati, l'altro li mostra.

---

## 5. Decisioni di design — le più importanti

> Elenco completo con motivazioni estese in **`docs/01-DECISIONI.md`**. Qui il riassunto
> operativo: **queste non vanno contraddette senza una discussione esplicita.**

- **D1 — Tre velocità di dato.** Distributore (quasi statico) / catalogo prodotti (lento) /
  prezzo (volatile). Solo il prezzo ha bisogno della macchina della freschezza.
- **D2 — Il prezzo è un'OSSERVAZIONE con timestamp, non un campo.** Non salvi
  `coca = 1.50`. Salvi "utente X ha riportato 1.50 il giorno Y, con GPS/foto". Il prezzo
  mostrato è **derivato** dalle osservazioni.
- **D3 — Prodotto canonico ≠ item.** `products` = entità globale condivisa
  ("Coca-Cola 33cl"). `items` = quel prodotto **in quel distributore** a quel prezzo.
  **Senza questa separazione il confronto prezzi tra distributori è impossibile.**
- **D4 — Il prezzo è una MODA PESATA, non una media.** Un distributore vende a UN prezzo
  alla volta: se passa da 1.50 a 1.80, la media darebbe 1.65 — un prezzo mai esistito.
- **D5 — `confidence = confidenceBase × freshness(now)`.** La parte strutturale
  (evidence × agreement) è scritta su Firestore; la parte temporale è calcolata **sul
  client al display**. Così la confidence "invecchia da sola" senza job server.
- **D6 — Verifica GPS di prossimità (~50 m).** Un report senza GPS pesa 0.3 invece di 1.0.
  Blocca lo spam da divano e alza la qualità.
- **D7 — Conferma a UN TOCCO.** "Coca ancora €1.50? [Sì]/[È cambiato]". *Confermare* è
  molto meno faticoso che *inserire*: è questo il meccanismo che tiene i dati freschi.
- **D8 — I campi derivati NON sono scrivibili dal client** (`currentPrice`,
  `confidenceBase`, `lastConfirmedAt`, `reportCount`, `reputation`, `validated`).
  Linea difensiva ribadita **sia nelle security rules sia nei model**.
- **D9 — `itemId == productId`.** Un distributore ha al massimo un item per prodotto:
  i duplicati diventano irrappresentabili per costruzione.
- **D10 — `priceReports` è append-only.** Un'osservazione non si modifica né si cancella.
- **D11 — MVP calcola lato client; il target è una Cloud Function.** ⚠️ Vedi §6.
- **D19 — Cooldown anti "consenso fabbricato".** UNA segnalazione (conferma O cambio) per
  utente, per item, ogni 24 h: senza, un utente da solo gonfia la confidence
  confermandosi. `nextAllowedReportTime()` (pura), applicata da `submitReport` PRIMA di
  ogni scrittura. Client-side nell'MVP (coerente con D11); nel target passa alla
  Cloud Function.
- **D12 — Cold start: seedare UN cluster denso**, non pin sparsi. Un pin isolato fa
  sembrare l'app rotta; una zona coperta al 100% (università/ospedale/stazione) dà valore
  immediato.
- **D13 — Gamification: MAI ingabbiare il valore core.** L'idea iniziale ("limite di
  visualizzazioni giornaliere, sbloccabile contribuendo") è stata **scartata**: premiare
  il *volume* di contributi incentiva a **inquinare il dataset**, e mettere un muro al
  lancio uccide l'adozione. → Si premiano solo i **contributi VALIDATI** (GPS/foto/accordo
  altrui) e si sbloccano **funzioni extra** (notifiche calo prezzo, storico, filtri),
  mai la ricerca del prezzo, che resta sempre gratis e illimitata.

---

## 6. ⚠️ Il bivio MVP / Target (fonte n.1 di confusione)

Il calcolo dei campi derivati può stare in due posti, e **le security rules devono essere
coerenti con la scelta**:

| | **MVP (oggi)** | **Target** |
|---|---|---|
| Chi calcola | il **client** (`price_calculator.dart`) | **Cloud Function** (trigger su nuovo report) |
| Regole su `items` | ramo *"MVP pura-client"* (controlla solo la **forma**) | ramo *"TARGET"* (`itemDerivedUnchanged()`) |
| Sicurezza | un client malevolo può mentire sul prezzo | inattaccabile |
| Costo | zero, nessun piano Blaze | richiede Blaze |

In `firestore.rules` c'è un commento **`>>> RIGA DEL BIVIO <<<`**: è lì che si commuta.
**Se le scritture vengono rifiutate senza motivo apparente, controlla PRIMA questo.**

**Correzione importante rispetto a un'ipotesi iniziale:** si era parlato di usare una
*transazione* Firestore lato client. **Non è possibile**: l'SDK mobile **non può fare query
su una collection dentro una transazione** (solo letture di singoli documenti per
riferimento). Siccome dobbiamo leggere *tutti* i report recenti, il pattern MVP è un
"leggi-poi-scrivi" **non perfettamente atomico**. Accettabile ora; risolto dalla Cloud
Function nel target.

---

## 7. Convenzioni di codice

- **Ogni model ha `fromDoc()` (leggi) + `createMap()` statico (scrivi in creazione).**
  Sono separati apposta: ciò che scrivi (senza campi derivati, con `serverTimestamp`,
  con valori forzati come `status:'active'`) **non è mai il semplice inverso** di ciò che leggi.
- **Timestamp**: SEMPRE `FieldValue.serverTimestamp()` in scrittura. Le rules impongono
  `timestamp == request.time`: un `DateTime.now()` dal client **viene rifiutato**. È voluto.
- **Soldi**: confrontare/raggruppare i prezzi in **centesimi interi** (`(p*100).round()`),
  mai in `double` (0.1 + 0.2 != 0.3).
- **Logica pura separata dall'I/O**: `computeDerived()` e `decideReportKind()` non toccano
  Firestore → testabili in isolamento e **riusabili tali e quali** nella futura Cloud
  Function (tradotte in TypeScript).
- **Gli Stream si creano UNA volta, mai dentro `build()`** (verrebbero ri-sottoscritti a
  ogni ridisegno).
- **Campo geo**: `geoflutterfire_plus` vuole un unico campo `geo: {geohash, geopoint}`,
  non due campi separati. Le rules controllano `incoming().geo.geopoint is latlng`.

---

## 8. Cosa NON fare (anti-goals dell'MVP)

- ❌ Reputazione, gamification, premi, notifiche, storico prezzi → **sono raffinamenti
  SOPRA il loop core.** Se il loop "vedo → contribuisco → il dato resta fresco" non gira,
  non hanno niente su cui poggiare.
- ❌ Riverpod / BLoC / architetture pesanti.
- ❌ Upload foto (dipende da Blaze). Il campo `photoUrl` è già nullable apposta: un report
  senza foto è **pienamente valido**, ha solo confidence più bassa.
- ❌ Costruire in orizzontale (prima tutta la mappa, poi tutti i prodotti...).
  → Costruire una **FETTA VERTICALE**: mappa → dettaglio → conferma prezzo, end-to-end.

---

## 9. Trappole note (fanno perdere ore)

1. **`AndroidManifest.xml`**: servono `INTERNET`, `ACCESS_FINE_LOCATION`,
   `ACCESS_COARSE_LOCATION`. ⚠️ Flutter aggiunge `INTERNET` **solo in debug**: in release
   la mappa resta **bianca** e Firestore muto, senza errori evidenti.
2. **PATH di `flutterfire`**: finisce in `%USERPROFILE%\AppData\Local\Pub\Cache\bin`, che
   **non è nel PATH di default**.
3. **`firebase login`** dietro proxy aziendale fallisce → farlo da casa. Se il browser resta
   appeso: `firebase login --no-localhost`.
4. **API di `geoflutterfire_plus`**: il nome del metodo di query è cambiato tra le versioni
   (`subscribeWithin`/`fetchWithin`/`within`). **Verificare sulla versione installata.**
5. **Region Firestore**: europea (`eur3`/`europe-west1`), e **non è più modificabile dopo**.
6. **Indici Firestore**: la query cross-distributore chiederà un indice composito +
   collection-group. Firestore fornisce il link per crearlo nel messaggio d'errore: è
   normale, non è un bug.
7. **Mai `controller.dispose()` subito dopo `await showDialog(...)`**: il Future si
   completa AL POP, ma il dialog resta montato durante l'animazione di chiusura →
   crash `'_dependents.isEmpty': is not true`. Regola: il controller lo possiede il
   widget (Stateful) che costruisce il TextField, e lo rilascia nel SUO `dispose()`.
   Vedi `_PriceDialog` in `machine_detail_screen.dart`.
8. **API che cambiano tra major version dei pacchetti geo**: già successo DUE volte
   (`geoflutterfire_plus`: nome del metodo di query; `geocoding` v5: da funzione
   top-level a metodo di `Geocoding()`). Prima di usare un esempio dal web, verificare
   l'API sulla versione installata in `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\`.

---

## 10. Documenti di riferimento

| File | Contenuto |
|---|---|
| `docs/01-DECISIONI.md` | **Ogni decisione con il PERCHÉ esteso** e le alternative scartate |
| `docs/02-MODELLO-DATI.md` | Schema Firestore campo per campo |
| `docs/03-ALGORITMO-PREZZI.md` | La matematica di `currentPrice` / `confidence` |
| `docs/04-SETUP.md` | Setup Windows + console Firebase, passo passo |
| `docs/05-ROADMAP.md` | Cosa viene dopo l'MVP |
