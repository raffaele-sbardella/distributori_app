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
- [ ] `flutter run` funziona

## Fase 1 — Il loop core (l'MVP vero)
- [x] Model + servizi + `map_screen`
- [x] `main.dart`: init Firebase + **login anonimo automatico** + crea `users/{uid}` se assente
- [x] **`machine_detail_screen.dart`**
      - `StreamBuilder` su `itemsForMachine(machineId)`
      - riga prodotto: nome, prezzo, **pallino colorato di confidence** + "confermato N giorni fa"
      - se GPS verificato → **conferma a un tocco** (D7): *"Ancora €1.50? [Sì] [È cambiato]"*
        (il "È cambiato" apre un dialog inline: niente schermata separata per i prezzi esistenti)
- [ ] `add_report_screen.dart` ← prossimo pezzo: autocomplete su `products` (spinge a **scegliere**, non creare) → prezzo → invio
- [ ] Aggiunta di un nuovo distributore dalla mappa (long-press → form)
- [x] Test unitari su `computeDerived()` → `test/price_calculator_test.dart` (6 test, tutti verdi)

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
- [ ] Piano **Blaze** + **Storage** → foto dell'etichetta (peso 1.4)
- [ ] Sconto immediato sui report `kind = "change"` (§Estensioni di `03-ALGORITMO-PREZZI.md`)
- [ ] Flag "distributore non c'è più" (`goneVotes`) con soglia di rimozione

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
