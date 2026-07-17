"""Migrazione D20: porta i prodotti esistenti alla convenzione nuova del formato.

Convenzione D20 (docs/01-DECISIONI.md):
  - bibita: size = "(contenitore) [taglia]"   es. "(lattina) 33cl", "(bottiglia)"
  - snack / altro: size = taglia facoltativa   es. "45g", oppure ""
  - caffè: size = ""

Perche' serve uno script e non basta la console: `productName` e' DENORMALIZZATO
sugli item (e' il displayName fotografato alla creazione). Cambiare `size` sul
prodotto canonico senza allineare gli item lascerebbe i nomi vecchi in giro.
Lo script sfrutta D9 (itemId == productId): legge l'item direttamente per ID
in ogni distributore — niente query, niente indici, niente trappola n.6.

L'Admin SDK BYPASSA le security rules (come la console): e' lo strumento da
amministratore, va usato solo da te, mai distribuito con l'app.

USO (in ordine):
  1. Console Firebase -> Impostazioni progetto -> Account di servizio
     -> "Genera nuova chiave privata" -> salva come tools/serviceAccountKey.json
     (e' nel .gitignore: il repo e' pubblico, la chiave NON deve mai finirci)
  2. pip install firebase-admin
  3. python tools/migrate_d20.py            <- inventario: elenca i prodotti e i loro ID
  4. compila NEW_SIZE_BY_ID qui sotto con i size nuovi
  5. python tools/migrate_d20.py            <- dry-run: mostra cosa cambierebbe, non scrive
  6. python tools/migrate_d20.py --apply    <- esegue davvero
"""

import argparse
import sys
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore

# ============ DA COMPILARE: productId -> size nuovo ============
# Gli ID li stampa il passo 3 (inventario). Esempi:
#   "aB3xY...": "(lattina) 33cl",     # bibita: contenitore + taglia
#   "cD4zW...": "(bottiglia)",        # bibita: solo contenitore
#   "eF5vU...": "",                   # snack/caffe': formato rimosso
#   "gH6tS...": "45g",                # snack: taglia tenuta (facoltativa)
NEW_SIZE_BY_ID: dict[str, str] = {
  "19pd5fP83EIoW7NQbTNP": "(bottiglia) 50cl",  # bibita: contenitore + taglia
  "3F2ErbYswbp8pUlJmqBM": "70g",  # bibita: contenitore + taglia
  "3PX1TafnyMSKwEC69DGG": "(bottiglia) 50cl",  # bibita: solo contenitore
  "7AAMuZxWOOHf3hHrxGIg": "(vetro)",  # bibita: solo contenitore
  "EdOs6xTf7Bcxl4PQ8N8D": "40g",  # snack: taglia tenuta (facoltativa)
  "GaK8CyfjJSWVwfOhwbYT": "(lattina)",  # bibita: contenitore + taglia
  "Sf20W5a6JUJPT3nNivAr": "(lattina) 33cl",  # bibita: contenitore + taglia
  "TGbvsbnREZTPSldoDFGb": "(lattina) 33cl",  # bibita: contenitore + taglia
  "TIFkHC6vJ4fqQxyFDI2b": "25g",  # snack: taglia tenuta (facoltativa)
  "Tq9ohFpSjF4lAhz2SnrA": "(lattina) 33cl",  # bibita: contenitore + taglia
  "aRkgCuO6rxjyGzsygOPC": "25g",  # snack: taglia tenuta (facoltativa)
  "bD5TUa7P6kHo5lItqLYT": "70g",  # bibita: contenitore + taglia
  "e9trSvEXBj4eIPeQcJu0": "",  # caffè: contenitore + taglia
  "eYZVVWcjgAEwlwztVs1r": "(bottiglia) 50cl",  # bibita: solo contenitore
  "f42pjIs1B1tf3bVYdyaT": "",  # snack: formato rimosso
  "hcJCm76Ntk6jNgWwFSZ0": "(lattina) 33cl",  # bibita: contenitore + taglia
  "ie798cHVo3hi4cjK4bC8": "25g",
  "rnC4QjgyPW9w660DFSFl": "(lattina) 33cl",  # bibita: contenitore + taglia
  "uN6SK65sN9fulESazIMA": "(bottiglia) 50cl",  # bibita: contenitore + taglia
  "uhWEgIqF1Nnik2iD56nH": "(bottiglia) 50cl",  # bibita: contenitore + taglia
  "xtRdnLeFB6az1yDSUP78": "(lattina) 32cl",  # bibita: contenitore + taglia
}

KEY_PATH = Path(__file__).parent / "serviceAccountKey.json"


def normalize_size(raw: str) -> str:
    """Specchio di normalizeProductSize in product_matcher.dart:
    spazi ripuliti + tutto minuscolo (i contenitori vanno minuscoli)."""
    return " ".join(raw.split()).lower()


def display_name(name: str, size: str) -> str:
    """Specchio di Product.displayName: 'Coca-Cola (lattina) 33cl'."""
    return name if not size else f"{name} {size}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="esegue le scritture (senza: solo dry-run)")
    args = parser.parse_args()

    if not KEY_PATH.exists():
        sys.exit(f"Chiave non trovata: {KEY_PATH}\n"
                 "Scaricala da Console -> Impostazioni progetto -> Account di servizio.")

    firebase_admin.initialize_app(credentials.Certificate(str(KEY_PATH)))
    db = firestore.client()

    # ---- 1) Inventario del catalogo ----
    products = list(db.collection("products").stream())
    print(f"\n=== CATALOGO ({len(products)} prodotti) ===")
    for p in products:
        d = p.to_dict()
        nuovo = NEW_SIZE_BY_ID.get(p.id)
        stato = f'-> "{normalize_size(nuovo)}"' if nuovo is not None else "(non mappato)"
        print(f'  {p.id}  [{d.get("category", "?"):6}]  '
              f'{d.get("name", "?")!r}  size={d.get("size", "")!r}  {stato}')

    if not NEW_SIZE_BY_ID:
        print("\nNEW_SIZE_BY_ID e' vuoto: compila la mappa in cima allo script "
              "con gli ID qui sopra, poi rilancia.")
        return

    # ---- 2) Piano: prodotto + item denormalizzati (letti per ID, D9) ----
    machine_ids = [m.id for m in db.collection("machines").stream()]
    print(f"\n=== PIANO (su {len(machine_ids)} distributori) ===")

    updates: list[tuple[firestore.firestore.DocumentReference, dict]] = []
    by_id = {p.id: p.to_dict() for p in products}
    for pid, raw_size in NEW_SIZE_BY_ID.items():
        if pid not in by_id:
            print(f"  !! productId sconosciuto, salto: {pid}")
            continue
        d = by_id[pid]
        new_size = normalize_size(raw_size)
        new_name = display_name(d.get("name", ""), new_size)

        if d.get("size", "") != new_size:
            updates.append((db.collection("products").document(pid),
                            {"size": new_size}))
            print(f'  products/{pid}: size {d.get("size", "")!r} -> {new_size!r}')

        for mid in machine_ids:
            ref = (db.collection("machines").document(mid)
                     .collection("items").document(pid))
            snap = ref.get()
            if not snap.exists:
                continue
            old_name = snap.to_dict().get("productName", "")
            if old_name != new_name:
                updates.append((ref, {"productName": new_name}))
                print(f"  machines/{mid}/items/{pid}: "
                      f"productName {old_name!r} -> {new_name!r}")

    if not updates:
        print("  Niente da fare: tutto gia' allineato.")
        return

    # ---- 3) Esecuzione (solo con --apply) ----
    if not args.apply:
        print(f"\nDRY-RUN: {len(updates)} scritture previste. "
              "Rilancia con --apply per eseguirle.")
        return

    batch = db.batch()  # atomico fino a 500 scritture: qui ne bastano poche
    for ref, data in updates:
        batch.update(ref, data)
    batch.commit()
    print(f"\nFATTO: {len(updates)} documenti aggiornati.")


if __name__ == "__main__":
    main()
