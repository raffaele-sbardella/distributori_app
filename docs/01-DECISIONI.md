# 01 — Decisioni di design (e il PERCHÉ)

> Formato: **decisione → perché → alternativa scartata (e perché scartata)**.
> È il documento più importante del progetto: il codice si riscrive, il ragionamento no.

---

## D0 — Principio fondativo: l'affidabilità è *dichiarata*, non *promessa*

**Decisione.** Non si cerca di avere prezzi sempre esatti. Si rende **sempre visibile quanto
un prezzo è affidabile** (quando è stato confermato l'ultima volta, con quanta evidenza).

**Perché.** "Prezzi molto affidabili" + "dati crowdsourced" sono in tensione: solo gli utenti
conoscono i prezzi, ma aggiornano di rado. Le app dei prezzi carburante risolvono così: non
promettono il valore esatto, dicono "segnalato 2 ore fa" e lasciano decidere l'utente.

> **Un prezzo vecchio non è un bug se è dichiarato vecchio. Diventa un tradimento solo se lo
> spacci per attuale.**

**Alternativa scartata.** Mostrare un prezzo secco senza indicatore di freschezza: dà una
falsa sensazione di certezza e, alla prima delusione, distrugge la fiducia nell'app.

---

## D1 — Separare i dati per "velocità di cambiamento"

**Decisione.** Tre livelli distinti: **distributore** (quasi statico: posizione, tipo,
gestore) / **catalogo prodotti** (cambia lentamente) / **prezzo** (volatile).

**Perché.** Solo il livello volatile ha bisogno di tutta la macchina della freschezza
(osservazioni, decadimento, confidence). Su distributori e catalogo basta il crowdsourcing
"una tantum + moderazione".

**Alternativa scartata.** Trattare "distributore + prodotti + prezzi" come un blocco unico:
avrebbe applicato complessità inutile a dati che non ne hanno bisogno.

---

## D2 — Il prezzo è un'OSSERVAZIONE con timestamp, non un campo

**Decisione.** Non si salva `coca = 1.50`. Si salva: *"l'utente X ha riportato 1.50 il
2026-07-01, GPS verificato, con foto"*. Il prezzo mostrato è **derivato** dalle osservazioni
recenti. Collection `priceReports`, **append-only**.

**Perché.** È la decisione da cui discende tutto il resto:
- consente di calcolare **da quanto tempo** un prezzo è confermato → la freschezza;
- consente di **pesare** le fonti (chi era sul posto vale più di chi era sul divano);
- conserva la storia (in futuro: grafico dell'andamento prezzi);
- rende il dato **auditabile**: si può sempre risalire a chi ha detto cosa e quando.

**Alternativa scartata.** Un campo `price` sovrascritto a ogni segnalazione: perde la storia,
non permette di pesare le fonti, e l'ultimo che scrive (magari uno spammer) vince sempre.

---

## D3 — Prodotto canonico ≠ item del distributore

**Decisione.** Due entità separate:
- `products/{productId}` — l'entità **globale condivisa**: "Coca-Cola 33cl".
- `machines/{id}/items/{itemId}` — il fatto che **questo** distributore vende **quel**
  prodotto a **quel** prezzo.

**Perché.** **Senza identità di prodotto condivisa, il confronto prezzi tra distributori è
impossibile.** Avresti solo tante stringhe scritte a mano ("coca cola", "CocaCola", "Coca
Cola 33") che non si parlano tra loro, e la query "dov'è la Coca più economica?" non avrebbe
niente su cui aggregare. È la ragion d'essere dell'app.

**Rischio noto.** Il crowdsourcing tende a creare duplicati nel catalogo canonico.
**Mitigazione MVP:** quando l'utente aggiunge un prodotto, mostrare prima un **autocomplete**
sui `products` esistenti e spingerlo a **scegliere** invece di **creare**; la creazione di un
nuovo canonico resta possibile ma è l'ultima spiaggia. Deduplica fine: dopo.

---

## D4 — `currentPrice` è una MODA PESATA, non una media

**Decisione.** Si raggruppano i report **per valore di prezzo** e si sceglie il valore col
punteggio pesato più alto (argmax), non la media dei valori.

**Perché.** Un distributore vende a **un** prezzo alla volta. Il prezzo nel tempo è una
**funzione a gradini**, non una grandezza rumorosa come la temperatura. Se passa da 1.50 a
1.80, la media dà **1.65: un prezzo che non è mai esistito**.

La moda pesata gestisce correttamente entrambi i casi critici:
- **cambio di prezzo** → i report recenti sul valore nuovo superano per peso i vecchi;
- **report sbagliato/malevolo** → un singolo report ha punteggio basso e non ribalta nulla.

**Alternativa scartata.** Media / mediana dei prezzi: produce valori inesistenti e reagisce
male ai cambi di prezzo.

---

## D5 — `confidence = confidenceBase × freshness(now)`

**Decisione.** Spezzare la confidence in due:
- **parte strutturale** (`evidence × agreement`) → cambia **solo** quando arrivano nuovi
  report → **calcolata alla scrittura e salvata** come `confidenceBase`;
- **parte temporale** (`freshness`) → dipende da `now` → **calcolata sul client al display**
  a partire da `lastConfirmedAt`.

**Perché.** La confidence deve **invecchiare da sola** anche senza nuovi report. Se fosse un
unico campo salvato, servirebbe un job server che ricalcola *tutti* i documenti a intervalli
regolari — costoso e inutile. Così: **zero lavoro server per il passare del tempo**, e la
freschezza mostrata è sempre attuale.

---

## D6 — Verifica GPS di prossimità (soglia ~50 m)

**Decisione.** Un report è `gpsVerified` solo se l'utente è entro ~50 m dal distributore. Un
report **non** verificato pesa **0.3** invece di 1.0.

**Perché.** Fa due cose insieme:
1. **alza la qualità** — chi conferma ha la verità davanti agli occhi;
2. **blocca lo spam da divano** — un report remoto non riesce, da solo, a spostare il prezzo.

**Perché 50 m e non 10.** Il GPS urbano sbaglia facilmente di 10–30 m: una soglia troppo
stretta darebbe falsi "sei lontano" a gente che è davvero davanti al distributore.

**Raffinamento futuro.** Confrontare la distanza con `soglia + position.accuracy` invece che
con una soglia fissa, per non penalizzare chi ha segnale scarso (tipico al chiuso, dove
spesso stanno i distributori).

---

## D7 — Il motore della freschezza è la CONFERMA A UN TOCCO

**Decisione.** Quando l'utente è fisicamente al distributore (GPS verificato), gli si mostra:
*"Coca-Cola è ancora €1.50?"* → **[Sì] / [È cambiato]**. Il "Sì" aggiorna `lastConfirmedAt`
con **un tap**; "È cambiato" apre l'inserimento.

**Perché.** **Inserire** un prezzo da zero è faticoso; **confermare** uno esistente no. Il
collo di bottiglia del crowdsourcing non è la buona volontà, è l'**attrito**. Questo è il
meccanismo che tiene i dati freschi — più di qualunque sistema di punti.

---

## D8 — I campi derivati non sono scrivibili dal client

**Decisione.** `currentPrice`, `confidenceBase`, `lastConfirmedAt`, `reportCount`,
`reputation`, `validated`, `verified`, `goneVotes` → **mai** scritti "a mano" dal client.
Linea difensiva ribadita **due volte**: nelle security rules **e** nei `createMap()` dei model.

**Perché.** Sono il cuore del sistema di affidabilità: se un client può scriverli
direttamente, l'intero modello di fiducia (e la futura reputazione) è aggirabile con una
singola scrittura.

> **Segnale d'allarme:** se ti ritrovi a scrivere uno di questi campi in un `createMap()`,
> stai bucando il tuo stesso modello di affidabilità.

⚠️ In fase **MVP** il calcolo è lato client, quindi le rules devono *temporaneamente*
lasciar passare la scrittura di quei campi (controllandone solo la **forma**). Vedi D11.

---

## D9 — `itemId == productId`

**Decisione.** L'id del documento `item` **è** il `productId`.

**Perché.**
- Un distributore vende un prodotto a **un prezzo alla volta** → "due item diversi per la
  Coca nello stesso distributore" diventa **irrappresentabile per costruzione**;
- verificare "questo distributore ha già questo prodotto?" è una **lettura diretta** del
  documento `items/{productId}`, non una query;
- meno codice, meno casi limite.

---

## D10 — `priceReports` è append-only

**Decisione.** Le rules vietano `update` e `delete` sui report: si possono solo creare.

**Perché.** Un'osservazione storica **non si riscrive**: "l'utente X ha detto 1.50 il giorno
Y" è un fatto avvenuto. Poterlo modificare a posteriori distruggerebbe l'auditabilità e
aprirebbe un vettore di manipolazione.

---

## D11 — MVP calcola sul client, il target è una Cloud Function

**Decisione.** Partire col calcolo lato client (nessuna Cloud Function, nessun piano Blaze,
si parte subito). Spostarlo in una Cloud Function quando il progetto matura.

**Perché.** Sblocca lo sviluppo immediato. **Lo schema dati non cambia tra i due mondi**:
cambia solo **CHI** scrive i campi derivati. E la funzione pura `computeDerived()` è
riusabile tale e quale (tradotta in TypeScript).

**⚠️ Correzione a un'ipotesi iniziale.** Si era detto "transazione Firestore lato client".
**Non è possibile:** l'SDK mobile **non può eseguire query su una collection dentro una
transazione** (solo letture di singoli documenti per riferimento). Dovendo leggere *tutti* i
report recenti, il pattern MVP è un **"leggi-poi-scrivi" non perfettamente atomico**.
Accettabile ora; risolto dalla Cloud Function nel target.

**Costo pratico.** Non serve rileggere tutta la storia a ogni scrittura: oltre ~6 mesi il
peso di un report è ≈ 0 per via del decadimento → si legge solo la finestra recente.

---

## D12 — Cold start: seedare UN cluster denso, non pin sparsi

**Decisione.** Il seeding manuale iniziale va **concentrato** su una zona sola ad alto
passaggio (università, ospedale, stazione, palestra), mappata **al 100%**.

**Perché.** **Un pin isolato in una città vuota fa sembrare l'app rotta.** Se invece i primi
utenti aprono l'app in una zona con copertura totale, percepiscono valore immediato — e da lì
il crowdsourcing si espande a macchia d'olio.

---

## D13 — Gamification: MAI ingabbiare il valore core ⚠️

**Idea iniziale (SCARTATA).** *"L'utente ha un numero limitato di visualizzazioni di
prezzi al giorno; contribuendo, il limite aumenta."*

**Perché è stata scartata — tre problemi:**

1. **Distrugge la qualità dei dati (il più grave).** Se leghi una ricompensa al *contribuire*,
   stai **pagando per il volume**, e quando paghi per il volume **ottieni volume, non verità**.
   L'utente che vuole sbloccare le visualizzazioni non ha incentivo a essere accurato: ha
   incentivo a *sembrare attivo* → conferme a caso, prodotti inventati, micro-modifiche per
   far girare il contatore. È **l'opposto** dell'obiettivo n.1 dichiarato (affidabilità).
   Costruirebbe una macchina che **incentiva l'inquinamento del dataset**.
2. **Uccide il cold start.** Al lancio servono utenti che girino liberi e percepiscano valore.
   Un muro proprio lì fa sbattere il nuovo utente **prima** che abbia capito perché dovrebbe
   contribuire.
3. **Framing per sottrazione.** "Hai un tot, se non contribuisci lo perdi" genera fastidio.
   Lo stesso meccanismo formulato come *guadagno* ("contribuendo sblocchi funzioni extra") dà
   una sensazione opposta, a parità di matematica.

**Decisione adottata al suo posto — due regole:**

1. **Il valore core resta SEMPRE gratis e illimitato.** "Qual è la Coca più economica vicino a
   me" è la promessa dell'app: ingabbiarla uccide l'adozione. Dietro il contributo si mettono
   solo **funzioni premium/potere**: notifiche di calo prezzo, storico dei prezzi, filtri
   avanzati, raggio esteso, badge e status.
2. **Contano solo i contributi VALIDATI, mai quelli grezzi.** Un contributo accredita punti
   **solo dopo** essere stato corroborato (GPS di prossimità, foto dell'etichetta, accordo di
   un secondo utente). Così **l'unico modo per farmare la ricompensa è inserire dati veri**:
   l'incentivo viene finalmente **allineato** all'affidabilità invece di essere in conflitto.
   È lo stesso pipeline della confidence che decide se un contributo "conta" (campo
   `validated`).

---

## D14 — Auth: anonimo + Google insieme

**Decisione.** Abilitati entrambi. Ingresso in anonimo, upgrade a Google opzionale.

**Perché.** L'anonimo dà **zero attrito** (nessuna schermata di login prima di vedere il
valore); Google serve a mettere in sicurezza i contributi. Firebase permette di **promuovere
un utente anonimo a Google mantenendo lo STESSO `uid`** (`linkWithCredential`): l'utente non
perde reputazione né segnalazioni. **Non trattarli come due mondi separati.**

---

## D15 — Storage (foto) rimandato

**Decisione.** MVP **senza upload foto**. `photoUrl` resta `nullable` ovunque.

**Perché.** Cloud Storage richiede il piano **Blaze** (carta di credito). Le foto sono un
**raffinamento della confidence**, non il cuore del loop: un report senza foto è pienamente
valido, ha solo peso 1.0 invece di 1.4. Si può sviluppare tutto il resto — mappa,
distributori, prodotti, prezzi, conferma GPS — senza toccare Storage.

**Nota su Blaze.** Non è un abbonamento: include lo stesso free tier di Spark e si paga solo
l'eccedenza. In fase MVP il costo reale è **zero**. Consigliato impostare un **budget alert**
(es. 1 €) su Google Cloud come rete di sicurezza.

---

## D16 — Niente state management, `StreamBuilder` puro

**Decisione.** Nessun Riverpod/BLoC/Provider nell'MVP. Un sottile layer `services/` +
`StreamBuilder` piantati direttamente sugli stream Firestore.

**Perché.** Su un MVP fatto da una persona sola, un'architettura di state management è
**complessità prematura**. Si aggiunge **quando** si sente che manca, non prima.

---

## D17 — Costruire una FETTA VERTICALE, non feature in orizzontale

**Decisione.** Non "prima tutta la mappa, poi tutti i prodotti, poi tutti i prezzi", ma **un
unico percorso completo end-to-end**:

> mappa → distributori vicini → tap → prodotti+prezzi con freschezza → conferma/aggiungi
> prezzo con verifica GPS

**Perché.** Quando questo singolo giro funziona **davvero**, hai l'MVP; tutto il resto è
iterazione su una base che gira. Costruire in orizzontale porta ad avere tre metà di feature
e zero flussi funzionanti.

---

## D18 — Tile OpenStreetMap: OK ora, non per sempre

**Decisione.** Usare il tile server pubblico di OSM per l'MVP.

**Perché ora.** Gratis, zero API key, zero configurazione.

**⚠️ Limite noto.** La **tile usage policy** di OSM è pensata per volumi modesti e **vieta il
traffico da app in scala**. Se l'app crescesse davvero, serve passare a un provider di tile
(MapTiler, Thunderforest...) **cambiando solo l'`urlTemplate`**. È una riga, non un problema
architetturale — ma va saputo fin d'ora.
