#!/usr/bin/env python3
"""
setup_wizard.py — Wizard interattivo per creare devices.json.

Guida l'utente nella configurazione di uno o più dispositivi Waveshare
Modbus TCP e salva il file devices.json nella stessa directory.

Avvio:  python setup_wizard.py
"""

import json
import os
import sys


DEFAULT_PORT = 502
DEFAULT_MAX_RELAYS = 7   # 0-based, significa 8 relè
DEFAULT_MAX_IN = 7       # 0-based, significa 8 ingressi


def ask(prompt, default=None, allow_empty=False):
    """Prompt con valore di default opzionale."""
    suffix = f" [{default}]" if default is not None else ""
    while True:
        val = input(f"{prompt}{suffix}: ").strip()
        if not val and default is not None:
            return default
        if not val and allow_empty:
            return ""
        if val:
            return val
        print("  Valore obbligatorio. Riprova.")


def ask_int(prompt, default=None, min_val=0, max_val=9999):
    """Prompt per intero con validazione range."""
    while True:
        val = ask(prompt, default=str(default) if default is not None else None)
        try:
            n = int(val)
        except ValueError:
            print("  Inserisci un numero intero valido.")
            continue
        if n < min_val or n > max_val:
            print(f"  Valore fuori range ({min_val}–{max_val}).")
            continue
        return n


def ask_ip(prompt, default=None):
    """Prompt per indirizzo IP con validazione base."""
    while True:
        val = ask(prompt, default=default)
        parts = val.split(".")
        if len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
            return val
        print("  IP non valido. Usa formato xxx.xxx.xxx.xxx (es. 192.168.1.100)")


def configure_device(index):
    """Configura un singolo dispositivo e ritorna il dict."""
    print(f"\n{'-'*50}")
    print(f"  Dispositivo {index}")
    print(f"{'-'*50}")

    name = ask("  Nome dispositivo (es. 'Quadro Luci')", default=f"Dispositivo {index}")
    ip = ask_ip("  Indirizzo IP", default="192.168.1.100")
    port = ask_int("  Porta", default=DEFAULT_PORT, min_val=1, max_val=65535)
    max_relays = ask_int("  Max relè (0-based, 7 = 8 relè)", default=DEFAULT_MAX_RELAYS, min_val=0, max_val=255)
    max_in = ask_int("  Max ingressi (0-based, 7 = 8 ingressi)", default=DEFAULT_MAX_IN, min_val=0, max_val=255)

    num_relays = max_relays + 1
    print(f"\n  Nomi relè (lascia vuoto per etichetta automatica R0, R1, ...)")
    print(f"  Relè disponibili: {num_relays}")
    do_names = input("  Vuoi assegnare nomi custom ai relè? [s/N]: ").strip().lower()

    relays = []
    if do_names in ("s", "si", "sì", "y", "yes"):
        for i in range(num_relays):
            label = ask(f"    Relè {i}", default=f"R{i}")
            relays.append(label if label else f"R{i}")
    # else: relays resta vuoto → fallback automatico nel GUI

    return {
        "name": name,
        "ip": ip,
        "port": port,
        "max_relays": max_relays,
        "max_in": max_in,
        "relays": relays,
    }


def main():
    script_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    out_path = os.path.join(script_dir, "devices.json")

    print("=" * 50)
    print("  MP Manager — Setup Wizard")
    print("  Configurazione dispositivi Waveshare Modbus TCP")
    print("=" * 50)

    # Se esiste già, chiedi conferma
    if os.path.isfile(out_path):
        print(f"\n  Esiste già un file devices.json in:")
        print(f"  {out_path}")
        overwrite = input("\n  Sovrascrivere? [s/N]: ").strip().lower()
        if overwrite not in ("s", "si", "sì", "y", "yes"):
            print("\n  Operazione annullata. Config esistente non modificato.")
            return

    n_devices = ask_int("\n  Quanti dispositivi vuoi configurare?", default=1, min_val=1, max_val=50)

    devices = []
    for i in range(1, n_devices + 1):
        devices.append(configure_device(i))

    data = {"devices": devices}

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"\n{'='*50}")
    print(f"  [OK] devices.json creato: {out_path}")
    print(f"  Dispositivi configurati: {len(devices)}")
    for d in devices:
        relays_info = f"{d['max_relays']+1} rele" if not d["relays"] else f"{len(d['relays'])} rele con nomi custom"
        print(f"    - {d['name']} - {d['ip']}:{d['port']} - {relays_info}")
    print(f"\n  Puoi ora avviare l'app con:  start.bat")
    print(f"{'='*50}")


if __name__ == "__main__":
    main()
