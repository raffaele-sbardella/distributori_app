# 03 — Algoritmo: da osservazioni a prezzo + confidence

Implementato in `lib/services/price_calculator.dart` → funzione **pura** `computeDerived()`.
Nessun Firestore dentro: input (lista di report) → output (campi derivati). Testabile in
isolamento e **riusabile tale e quale** nella futura Cloud Function (tradotta in TypeScript).

---

## Il concetto chiave: MODA PESATA, non media (D4)

Un distributore vende a **un prezzo alla volta**: il prezzo nel tempo è una **funzione a
gradini**, non una grandezza rumorosa. Se passa da 1.50 a 1.80, la media dà **1.65 — un
prezzo mai esistito**.

→ Non si mediano i *valori*. Si **raggruppano i report per valore di prezzo** e si sceglie il
valore che raccoglie più "voti pesati".

---

## Peso di un singolo report

```
recency(r) = 0.5 ^ (etàInGiorni / H)          # decadimento esponenziale

trust(r)   = w_gps × w_photo × w_rep
             w_gps   = gpsVerified ? 1.0 : 0.3     ← chiave anti-abuso
             w_photo = foto        ? 1.4 : 1.0
             w_rep   = 1.0 per ora  (futuro: scala con la reputazione, ~0.5..1.5)

weight(r)  = recency(r) × trust(r)
```

**Perché `w_gps = 0.3`:** un report "da divano" vale poco più di niente → **non riesce a
spostare il prezzo da solo**. È il moltiplicatore che protegge il dataset (D6).

---

## `currentPrice` — argmax del punteggio

```
score(p)     = Σ weight(r)   per tutti gli r con prezzo == p
currentPrice = il p con score massimo
```

⚠️ **Raggruppare in CENTESIMI INTERI**, mai confrontando `double`: in floating point
`0.1 + 0.2 != 0.3`, quindi il raggruppamento su `double` è fragile. → `(price * 100).round()`.
Trucco standard quando si maneggiano soldi.

---

## `lastConfirmedAt` — la sottigliezza che rende onesta la UI

```
lastConfirmedAt = max(r.timestamp)   tra gli r con prezzo == currentPrice
```

**NON** il report più recente in assoluto, ma **il più recente CHE CONCORDA col prezzo
vincente**. Se ieri qualcuno ha segnalato un prezzo sbagliato ma il prezzo vero è stato
confermato una settimana fa, l'utente **deve leggere "una settimana fa"**.

---

## `confidence` — tre domande, tre fattori

```
freshness  = 0.5 ^ ((now − lastConfirmedAt) / H_conf)    # è fresco?
evidence   = support / (support + k)                     # c'è abbastanza evidenza?
             dove support = score(currentPrice)
agreement  = score(currentPrice) / Σ_p score(p)          # gli utenti sono d'accordo?

confidence = freshness × evidence × agreement
```

- **`evidence`** satura (rendimenti decrescenti): **un solo report**, anche con foto e GPS,
  **non arriva mai a "certezza"** (peso ≈1.4 → `1.4/(1.4+2)` ≈ **0.41**). Servono più conferme
  indipendenti per salire.
- **`agreement`** crolla quando il prezzo è **conteso** (due dicono 1.50, due dicono 1.80):
  giusto, perché in quel caso **davvero non sai** quale sia.

### Lo split scritto/calcolato (D5)

```
# scritto su Firestore quando arriva un report:
item.currentPrice    = argmax score
item.confidenceBase  = evidence × agreement      ← parte STRUTTURALE
item.lastConfirmedAt = …

# calcolato sul CLIENT al display, sempre "live":
freshness  = 0.5 ^ ((now − item.lastConfirmedAt) / H_conf)
confidence = item.confidenceBase × freshness
```

→ La confidence **invecchia da sola**, con **zero lavoro server**.
Implementato in `VendingItem.confidence(now)`.

---

## Verifiche di sanità (usarle come test)

| Scenario | Confidence attesa | UI |
|---|---|---|
| 1 report fresco, GPS + foto | ≈ **0.41** | 🟡 "segnalato ora, una sola fonte" |
| 3 conferme fresche concordi | ≈ **0.6** | 🟢 |
| le stesse 3, ma vecchie di 2 mesi | ≈ **0.07** | ⚪ "da confermare" |

Sono i **primi test unitari da scrivere** su `computeDerived()`.

---

## Costanti di partenza (da tarare sul campo)

| Costante | Valore | Significato |
|---|---|---|
| `H` | **30 giorni** | emivita per la selezione del prezzo |
| `H_conf` | **21 giorni** | emivita della freschezza |
| `k` | **2** | saturazione dell'evidenza |
| soglia GPS | **50 m** | prossimità |

### Soglie UI
- `confidence > 0.6` → 🟢 verde "confermato di recente"
- `0.3 – 0.6` → 🟡 giallo
- `< 0.3` → ⚪ grigio "da confermare"

**Sempre**, accanto al prezzo, `lastConfirmedAt` in forma umana ("2 giorni fa"). È il
mantenimento della promessa di D0.

---

## Nota di costo

Non serve rileggere tutta la storia a ogni scrittura: oltre **~6 mesi** il peso è ≈ 0 per il
decadimento. → Si legge solo la finestra recente (ultimi 180 giorni / ~50 report) e il
risultato **non cambia**.

---

## Estensioni previste (NON nell'MVP)

1. **Sconto immediato sul `change`.** Oggi il campo `kind` viene **registrato ma non usato
   nella matematica** — ed è voluto: un `confirm` rinforza naturalmente il suo prezzo senza
   trattamenti speciali. Quando un report `kind = "change"` arriva, però, l'utente sta
   **dichiarando che il vecchio prezzo è morto**: si potranno scontare **subito** i report del
   prezzo vecchio invece di aspettare i 30 giorni di emivita → il cambio si propaga
   all'istante. Si attiva modificando **solo** `computeDerived()`: né lo schema né i servizi.
2. **Reputazione.** Entra **tutta e sola** dentro `w_rep`. Nient'altro da toccare — motivo per
   cui il campo `reputation` è già nello schema.
