# 02 — Modello dati Firestore

Struttura ad albero:

```
machines/{machineId}
  └── items/{itemId}                    (itemId == productId, vedi D9)
        └── priceReports/{reportId}     (append-only)
products/{productId}                    (catalogo canonico globale)
users/{userId}
```

Le tre "velocità" (D1): `machines` = quasi statico · `products` = lento · `items`/`priceReports` = volatile.

---

## `machines/{machineId}` — il distributore

| Campo | Tipo | Note |
|---|---|---|
| `geo` | map | **`{geohash: string, geopoint: GeoPoint}`** — formato richiesto da `geoflutterfire_plus` |
| `label` | string | es. "Distributore atrio Ingegneria" |
| `type` | string | `snack` \| `drink` \| `coffee` \| `combo` |
| `operator` | string? | gestore, se noto (IVS, Argenta…) |
| `address` | string | |
| `photoUrl` | string? | rimandato (Storage/Blaze) |
| `status` | string | `active` \| `empty` \| `removed` |
| `goneVotes` | number | ⛔ derivato — contatore "non c'è più" |
| `createdBy` | string | userId |
| `createdAt` / `updatedAt` | timestamp | `serverTimestamp()` |

> ⚠️ **`geo` è UN campo, non due.** All'inizio si era ipotizzato `geopoint` + `geohash`
> separati: `geoflutterfire_plus` vuole invece un unico campo annidato, e le query filtrano
> su `geo.geohash`. Le rules controllano `incoming().geo.geopoint is latlng`.

`status` + `goneVotes` gestiscono i **"fantasmi"**: quando abbastanza utenti segnalano che il
distributore non c'è più, passa a `removed` e sparisce dalla mappa.

---

## `products/{productId}` — il catalogo canonico (globale, condiviso)

| Campo | Tipo | Note |
|---|---|---|
| `name` | string | "Coca-Cola" |
| `brand` | string? | |
| `size` | string | "33cl" |
| `category` | string | `bibita` \| `snack` \| `caffè` … |
| `imageUrl` | string? | |
| `verified` | bool | ⛔ derivato — nasce **sempre** `false` |
| `createdBy` | string | |
| `createdAt` | timestamp | |

**È il punto delicato del crowdsourcing** (D3): se ognuno crea il suo "coca cola",
"CocaCola", "Coca Cola", il catalogo esplode in duplicati e **il confronto prezzi si rompe**.
→ MVP: autocomplete che spinge a **scegliere** invece di **creare**.

---

## `machines/{id}/items/{itemId}` — cosa vende QUESTO distributore

| Campo | Tipo | Note |
|---|---|---|
| `machineId` | string | denormalizzato → per risalire dai risultati di una collectionGroup query |
| `productId` | string | → `products/{productId}` |
| `productName` | string | denormalizzato → evita di leggere il canonico a ogni riga |
| `currentPrice` | number | ⛔ **DERIVATO** (moda pesata) |
| `currency` | string | `EUR` |
| `confidenceBase` | number | ⛔ **DERIVATO** — `evidence × agreement` (parte NON temporale) |
| `lastConfirmedAt` | timestamp | ⛔ **DERIVATO** — il cuore dell'indicatore di freschezza |
| `reportCount` | number | ⛔ **DERIVATO** |
| `status` | string | `available` \| `soldout` |
| `geohash` | string | denormalizzato dal machine → per la futura query cross-distributore |
| `createdAt` | timestamp | |

> ⛔ = **il client non lo scrive mai a mano** (D8). Lo produce `submitPriceReport()`
> leggendo i report. Anche l'item appena creato nasce **senza** questi campi: li popola il
> primo report, passando dallo stesso identico percorso di calcolo di tutti gli altri.

**La confidence NON è un campo.** Si calcola al display:
`confidence = confidenceBase × freshness(now)` (D5) → `VendingItem.confidence(now)`.

---

## `…/items/{itemId}/priceReports/{reportId}` — le osservazioni grezze

| Campo | Tipo | Note |
|---|---|---|
| `price` | number | |
| `userId` | string | deve essere `request.auth.uid` |
| `timestamp` | timestamp | **`serverTimestamp()` obbligatorio** (rules: `== request.time`) |
| `photoUrl` | string? | etichetta prezzo — rimandato |
| `gpsVerified` | bool | entro ~50 m? → peso 1.0 vs 0.3 |
| `distanceMeters` | number? | |
| `kind` | string | `new` \| `confirm` \| `change` |
| `validated` | bool | ⛔ derivato — nasce **sempre** `false`, lo decide il server |

**Append-only** (D10): niente `update`, niente `delete`.

---

## `users/{userId}` — segnaposto per la reputazione

| Campo | Tipo | Note |
|---|---|---|
| `displayName` | string | |
| `reputation` | number | ⛔ derivato — **sempre 0** alla creazione |
| `validatedContributions` | number | ⛔ derivato — **sempre 0** alla creazione |
| `createdAt` | timestamp | |

Minimale adesso, ma i campi **esistono già**: quando aggiungerai il sistema di fiducia
**non dovrai migrare nulla**. La reputazione entrerà nel calcolo **solo** dentro `w_rep`
(vedi `03-ALGORITMO-PREZZI.md`), senza toccare nient'altro.

---

## Indici (per dopo)

La query **"prodotto X più economico entro 2 km"** sarà una `collectionGroup` query su
`items`, filtrata per `productId` + range di `geohash`. Richiederà:
- un **indice composito**,
- abilitato come **collection-group index**.

Firestore fornisce il link per crearlo **direttamente nel messaggio d'errore** alla prima
esecuzione: è normale, non è un bug. Il campo `geohash` è già denormalizzato sugli item
apposta per questo.
