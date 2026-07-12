# 05 — Roadmap

## Principio: FETTA VERTICALE, non feature in orizzontale (D17)

❌ Non: "prima tutta la mappa, poi tutti i prodotti, poi tutti i prezzi".
✅ Ma: **un unico percorso completo end-to-end.**

```
apri la mappa
   → vedi i distributori vicino a te      (seedati a mano, UN cluster denso)
   → tocchi un distributore
   → vedi prodotti + prezzi + freschezza  (🟢🟡⚪)
   → confermi/aggiungi un prezzo          (verifica GPS)
   → il dato torna fresco
```

**Quando questo giro funziona davvero, hai l'MVP.** Tutto il resto è iterazione su una base
che gira.

---

## Fase 0 — Ambiente (bloccante)
- [x] Setup Windows completo → `flutter doctor` senza problemi (2026-07-11)
- [x] Progetto Firebase `app-distributori` + rules pubblicate (ramo MVP attivo)
- [x] `flutter run` funziona (2026-07-11, primo avvio su telefono reale) → **Fase 0 COMPLETATA**

## Fase 1 — Il loop core (l'MVP vero)
- [x] Model + servizi + `map_screen`
- [x] `main.dart`: init Firebase + **login anonimo automatico** + crea `users/{uid}` se assente
- [x] **`machine_detail_screen.dart`**
      - `StreamBuilder` su `itemsForMachine(machineId)`
      - riga prodotto: nome, prezzo, **pallino colorato di confidence** + "confermato N giorni fa"
      - se GPS verificato → **conferma a un tocco** (D7): *"Ancora €1.50? [Sì] [È cambiato]"*
        (il "È cambiato" apre un dialog inline: niente schermata separata per i prezzi esistenti)
- [x] `add_report_screen.dart`: autocomplete su `products` (spinge a **scegliere**, non creare) → prezzo → invio
      → **FASE 1 COMPLETA (2026-07-11): il loop core è tutto scritto. Ora: seeding sul campo (Fase 2).**
- [x] Aggiunta di un nuovo distributore dalla mappa (long-press → form, `add_machine_screen.dart`)
- [x] Test unitari su `computeDerived()` → `test/price_calculator_test.dart` (6 test, tutti verdi)
- [x] Cooldown anti-spam (D19): 1 segnalazione per utente/item/24h, con test

## Fase 2 — Il cold start (D12)
- [ ] Scegliere **UN cluster denso** ad alto passaggio (università / ospedale / stazione / palestra)
- [ ] Mapparlo **al 100%** a mano
- [ ] Farlo provare a 5-10 persone reali → **guardarle usarlo senza aiutarle**

## Fase 3 — Il valore che distingue l'app
- [ ] **Query cross-distributore**: "il prodotto X più economico entro 2 km"
      → `collectionGroup` su `items` + `productId` + range `geohash` (indice richiesto)
- [ ] Ricerca prodotto globale
- [ ] Ri-query quando la mappa viene spostata (oggi lo stream è agganciato alla posizione **iniziale**)

## Fase 4 — Affidabilità "da prodotto"
- [ ] **Cloud Function**: sposta `computeDerived` server-side (D11)
      → commuta le rules sul ramo **TARGET**, e `submitPriceReport` si limita ad aggiungere il report
      → e il cooldown D19 (`nextAllowedReportTime`) diventa enforcement server-side
        (oggi è solo client-side: un client malevolo può aggirarlo)
- [ ] Piano **Blaze** + **Storage** → foto dell'etichetta (peso 1.4)
- [ ] Sconto immediato sui report `kind = "change"` (§Estensioni di `03-ALGORITMO-PREZZI.md`)
- [ ] Flag "distributore non c'è più" (`goneVotes`) con soglia di rimozione
- [ ] Merge/rinomina prodotti (typo e doppioni sfuggiti al fuzzy): strumento admin
      server-side — deve sistemare anche `productName`/`category` denormalizzati
      sugli item e travasare i report (itemId == productId, D9)

## Fase 5 — Crescita (solo se il loop funziona)
- [ ] **Reputazione** (`w_rep`) — entra solo lì, nient'altro da toccare
- [ ] Contributi **validati** → punti (D13)
- [ ] Funzioni extra sbloccabili: notifiche calo prezzo, storico, filtri, raggio esteso
- [ ] Upgrade anonimo → Google mantenendo l'`uid` (D14)
- [ ] Provider di tile alternativo a OSM (D18)

---

## ⚠️ Il muro vero non è tecnico

Per il **portfolio** hai già tutto: architettura geospaziale, sistema di confidence, pipeline
di validazione — roba che si racconta bene in un colloquio.

Per il **prodotto reale**, il muro è **motivazionale**: *perché* un utente dovrebbe
contribuire? Non esiste risposta magica. Le leve realistiche:
1. **attrito bassissimo** → il tap di conferma (D7);
2. gamification leggera (punti, badge, "top contributor di Battipaglia");
3. reciprocità sociale.

⛔ **Non bloccare la visione dei prezzi a chi non contribuisce** (D13): uccide l'adozione
proprio quando serve di più.
