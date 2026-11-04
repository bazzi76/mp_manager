#!/usr/bin/env python3
"""
mp_manager_win.py — GUI Windows per controllo relè Waveshare Modbus TCP.
Addon multipiattaforma di mp_manager.sh (versione Linux/bash).

Supporta multipli dispositivi via file JSON (devices.json).
Fallback a singolo dispositivo via mp_manager.conf se devices.json assente.

Avvio:  python mp_manager_win.py
Richiede:  pip install pyModbusTCP
Config:    win/devices.json (multi-dispositivo) oppure win/mp_manager.conf (singolo)

Autore: Giacomo Mattei <giacomo.mattei@grupposimtel.com>
"""

import os
import sys
import json
import tkinter as tk
from tkinter import ttk, messagebox

try:
    from pyModbusTCP.client import ModbusClient
except ImportError:
    root = tk.Tk()
    root.withdraw()
    messagebox.showerror(
        "Dipendenza mancante",
        "Installare pyModbusTCP:\n\n    pip install pyModbusTCP\n\n"
        "poi riavviare l'app.",
    )
    sys.exit(1)


# ─── Config ───────────────────────────────────────────────────────────

DEFAULTS = {
    "ip": "192.168.1.100",
    "port": 502,
    "max_relays": 7,
    "max_in": 7,
    "coil_offset_relays": 0,
    "coil_offset_inputs": 0,
    "mode_reg_base": 4096,
}

ALL_RELAYS_COIL = 255  # coil broadcast Waveshare: scrive tutti i relè


def load_devices_json(path):
    """Legge devices.json e ritorna una lista di dict dispositivo."""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    devices = data.get("devices", [])
    result = []
    for d in devices:
        dev = dict(DEFAULTS)
        dev.update(d)
        # relays: lista di nomi (può essere vuota o parziale)
        dev.setdefault("relays", [])
        result.append(dev)
    return result


def load_legacy_conf(path):
    """Legge mp_manager.conf (formato KEY=value) — singolo dispositivo."""
    cfg = dict(DEFAULTS)
    found = os.path.isfile(path)
    if not found:
        cfg["name"] = "Dispositivo"
        cfg["relays"] = []
        return cfg, False
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                key = key.strip().lower()
                val = val.strip()
                if "#" in val:
                    val = val.split("#")[0].strip()
                # conversioni tipo
                if key in ("port", "max_relays", "max_in",
                           "coil_offset_relays", "coil_offset_inputs",
                           "mode_reg_base"):
                    try:
                        val = int(val)
                    except ValueError:
                        pass
                if key:
                    cfg[key] = val
    cfg.setdefault("name", f"{cfg['ip']}:{cfg['port']}")
    cfg.setdefault("relays", [])
    return cfg, True


# ─── Colori ───────────────────────────────────────────────────────────

ON_BG = "#1e8e3e"
ON_FG = "#ffffff"
OFF_BG = "#3c4043"
OFF_FG = "#9aa0a6"
UNKNOWN_BG = "#5f6368"
UNKNOWN_FG = "#cccccc"
HDR_CONN = "#1e8e3e"
HDR_DISC = "#cc3333"
HDR_WARN = "#cc9933"


# ─── DevicePanel ──────────────────────────────────────────────────────

class DevicePanel(ttk.Frame):
    """Pannello relè per un singolo dispositivo Modbus TCP."""

    def __init__(self, parent, device_cfg):
        super().__init__(parent)
        self.root = parent.winfo_toplevel()  # riferimento alla Tk root per after()
        self.ip = device_cfg["ip"]
        self.port = int(device_cfg["port"])
        self.max_relays = int(device_cfg["max_relays"])
        self.coil_offset = int(device_cfg.get("coil_offset_relays", 0))
        self.num_relays = self.max_relays + 1  # 0-based
        self.dev_name = device_cfg.get("name", f"{self.ip}:{self.port}")

        # Nomi relè: usa quelli forniti, fallback a R0, R1, ...
        relay_names = device_cfg.get("relays", [])
        self.relay_labels = []
        for i in range(self.num_relays):
            if i < len(relay_names) and relay_names[i].strip():
                self.relay_labels.append(relay_names[i].strip())
            else:
                self.relay_labels.append(f"R{i}")

        self.client = None
        self.relay_states = [None] * self.num_relays
        self.auto_refresh = tk.BooleanVar(value=False)
        self.pulse_mode = tk.BooleanVar(value=False)
        self.pulse_duration = tk.StringVar(value="2.0")
        self._refresh_job = None
        self._pulsing = set()

        self._build_ui()
        self._connect()
        self._refresh_status()

    # ── UI ────────────────────────────────────────────────────────────

    def _build_ui(self):
        # Header
        header = ttk.Frame(self, padding=10)
        header.grid(row=0, column=0, sticky="ew")

        ttk.Label(header, text="Dispositivo:").grid(row=0, column=0, sticky="w")
        self.lbl_device = ttk.Label(
            header, text=f"{self.ip}:{self.port}",
            font=("Segoe UI", 10, "bold")
        )
        self.lbl_device.grid(row=0, column=1, sticky="w", padx=(4, 16))

        self.btn_refresh = ttk.Button(header, text="Aggiorna", width=10,
                                      command=self._refresh_status)
        self.btn_refresh.grid(row=0, column=2)

        self.lbl_status = ttk.Label(header, text="● Disconnesso",
                                    foreground=HDR_DISC)
        self.lbl_status.grid(row=0, column=3, padx=(16, 0))

        # Relè
        relay_frame = ttk.LabelFrame(self, text="Relè", padding=10)
        relay_frame.grid(row=1, column=0, sticky="nsew", padx=10, pady=(0, 10))

        self.relay_buttons = []
        cols = 4
        for i in range(self.num_relays):
            r, c = divmod(i, cols)
            btn = tk.Button(
                relay_frame,
                text=f"{self.relay_labels[i]}\n???",
                width=10,
                height=2,
                font=("Consolas", 9, "bold"),
                relief="flat",
                bd=0,
                highlightthickness=0,
                command=lambda n=i: self._handle_relay_click(n),
            )
            btn.grid(row=r, column=c, padx=4, pady=4)
            self.relay_buttons.append(btn)

        # Bottom bar
        bottom = ttk.Frame(self, padding=(10, 0, 10, 10))
        bottom.grid(row=2, column=0, sticky="ew")

        ttk.Button(bottom, text="Tutti ON", command=self._all_on).grid(row=0, column=0, padx=4)
        ttk.Button(bottom, text="Tutti OFF", command=self._all_off).grid(row=0, column=1, padx=4)
        ttk.Checkbutton(bottom, text="Auto-refresh (2s)",
                        variable=self.auto_refresh,
                        command=self._toggle_auto_refresh).grid(row=0, column=2, padx=(20, 0))

        ttk.Checkbutton(bottom, text="Pulse mode",
                        variable=self.pulse_mode).grid(row=0, column=3, padx=(20, 0))
        ttk.Label(bottom, text="Durata (s):").grid(row=0, column=4, padx=(8, 2))
        pulse_entry = ttk.Entry(bottom, textvariable=self.pulse_duration, width=5)
        pulse_entry.grid(row=0, column=5)

    # ── Modbus ────────────────────────────────────────────────────────

    def _connect(self):
        try:
            if self.client:
                self.client.close()
            self.client = ModbusClient(host=self.ip, port=self.port, timeout=5)
            ok = self.client.open()
            if ok:
                self.lbl_status.config(text="● Connesso", foreground=HDR_CONN)
            else:
                self.lbl_status.config(text="● Errore connessione", foreground=HDR_DISC)
            return ok
        except Exception as e:
            self.lbl_status.config(text=f"● Errore: {e}", foreground=HDR_DISC)
            return False

    def _refresh_status(self):
        if not self.client or not self.client.is_open:
            if not self._connect():
                return
        try:
            bits = self.client.read_coils(self.coil_offset, self.num_relays)
            if bits is None:
                if not self._connect():
                    return
                bits = self.client.read_coils(self.coil_offset, self.num_relays)
            if bits is not None:
                self.relay_states = list(bits)
                self._update_button_colors()
                self.lbl_status.config(text="● Connesso", foreground=HDR_CONN)
            else:
                self.lbl_status.config(text="● Nessuna risposta", foreground=HDR_WARN)
        except Exception as e:
            self.lbl_status.config(text=f"● Errore: {e}", foreground=HDR_DISC)

    def _update_button_colors(self):
        for i, state in enumerate(self.relay_states):
            btn = self.relay_buttons[i]
            label = self.relay_labels[i]
            if state is None:
                btn.config(text=f"{label}\n???", bg=UNKNOWN_BG, fg=UNKNOWN_FG,
                           activebackground=UNKNOWN_BG)
            elif state:
                btn.config(text=f"{label}\nON", bg=ON_BG, fg=ON_FG,
                           activebackground=ON_BG)
            else:
                btn.config(text=f"{label}\nOFF", bg=OFF_BG, fg=OFF_FG,
                           activebackground=OFF_BG)

    def _toggle_relay(self, num):
        if not self.client or not self.client.is_open:
            if not self._connect():
                return
        coil = self.coil_offset + num
        current = self.relay_states[num] if num < len(self.relay_states) else None
        new_state = not current if current is not None else True
        try:
            ok = self.client.write_single_coil(coil, bool(new_state))
            if ok:
                self.relay_states[num] = new_state
                self._update_button_colors()
            else:
                messagebox.showerror("Errore", f"Impossibile scrivere il relè {num}.")
        except Exception as e:
            messagebox.showerror("Errore", f"Errore scrittura relè {num}:\n{e}")

    def _handle_relay_click(self, num):
        if num in self._pulsing:
            return
        if self.pulse_mode.get():
            self._pulse_relay(num)
        else:
            self._toggle_relay(num)

    def _get_pulse_duration(self):
        try:
            duration = float(self.pulse_duration.get().replace(",", "."))
        except ValueError:
            messagebox.showerror("Errore", "Durata pulse non valida.\nUsa un numero (es. 2.0).")
            return None
        if duration <= 0 or duration > 60:
            messagebox.showerror("Errore", "Durata pulse non valida (0–60 secondi).")
            return None
        return duration

    def _pulse_relay(self, num):
        duration = self._get_pulse_duration()
        if duration is None:
            return
        if not self.client or not self.client.is_open:
            if not self._connect():
                return
        coil = self.coil_offset + num
        # Stato attuale → inverti per il pulse, poi ripristina
        original_state = self.relay_states[num] if num < len(self.relay_states) else None
        pulse_state = not original_state if original_state is not None else True
        try:
            ok = self.client.write_single_coil(coil, bool(pulse_state))
            if not ok:
                messagebox.showerror("Errore", f"Impossibile attivare il pulse sul relè {num}.")
                return
            self.relay_states[num] = pulse_state
            self._pulsing.add(num)
            self.relay_buttons[num].config(state="disabled", text=f"{self.relay_labels[num]}\nPULSE")
            self._update_button_colors()
            # Dopo la durata, ripristina lo stato originale
            self.root.after(int(duration * 1000),
                            lambda: self._pulse_revert(num, coil, original_state))
        except Exception as e:
            messagebox.showerror("Errore", f"Errore pulse relè {num}:\n{e}")
            self._pulsing.discard(num)

    def _pulse_revert(self, num, coil, original_state):
        """Ripristina lo stato originale del relè dopo il pulse."""
        revert_state = original_state if original_state is not None else False
        try:
            self.client.write_single_coil(coil, bool(revert_state))
            self.relay_states[num] = revert_state
        except Exception:
            pass
        finally:
            self._pulsing.discard(num)
            self.relay_buttons[num].config(state="normal")
            self._update_button_colors()

    def _all_on(self):
        self._write_all(True)

    def _all_off(self):
        self._write_all(False)

    def _write_all(self, state):
        if not self.client or not self.client.is_open:
            if not self._connect():
                return
        try:
            ok = self.client.write_single_coil(ALL_RELAYS_COIL, bool(state))
            if ok:
                self._refresh_status()
            else:
                messagebox.showerror("Errore", "Impossibile impostare tutti i relè.")
        except Exception as e:
            messagebox.showerror("Errore", f"Errore:\n{e}")

    # ── Auto-refresh ──────────────────────────────────────────────────

    def _toggle_auto_refresh(self):
        if self.auto_refresh.get():
            self._auto_refresh_loop()
        elif self._refresh_job:
            self.root.after_cancel(self._refresh_job)
            self._refresh_job = None

    def _auto_refresh_loop(self):
        if self.auto_refresh.get():
            self._refresh_status()
            self._refresh_job = self.root.after(2000, self._auto_refresh_loop)

    def cleanup(self):
        """Chiude connessione e ferma auto-refresh."""
        if self._refresh_job:
            try:
                self.root.after_cancel(self._refresh_job)
            except Exception:
                pass
            self._refresh_job = None
        if self.client:
            self.client.close()


# ─── MultiDeviceApp ───────────────────────────────────────────────────

class MultiDeviceApp:
    """App principale: legge la config, crea tab per ogni dispositivo."""

    def __init__(self, root, devices):
        self.root = root
        self.panels = []

        root.title("MP Manager — Waveshare Modbus Relay")
        root.resizable(False, False)

        style = ttk.Style()
        try:
            style.theme_use("vista")
        except tk.TclError:
            pass

        self.notebook = ttk.Notebook(root)
        self.notebook.grid(row=0, column=0, sticky="nsew")

        for dev in devices:
            panel = DevicePanel(self.notebook, dev)
            self.notebook.add(panel, text=dev.get("name", f"{dev['ip']}:{dev['port']}"))
            self.panels.append(panel)

    def on_close(self):
        for p in self.panels:
            p.cleanup()
        self.root.destroy()


# ─── Main ─────────────────────────────────────────────────────────────

def main():
    script_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    devices_json = os.path.join(script_dir, "devices.json")
    legacy_conf = os.path.join(script_dir, "mp_manager.conf")

    devices = []
    config_source = None

    if os.path.isfile(devices_json):
        try:
            devices = load_devices_json(devices_json)
            config_source = "devices.json"
        except (json.JSONDecodeError, KeyError) as e:
            messagebox.showerror(
                "Errore config",
                f"Errore lettura devices.json:\n{e}\n\n"
                f"Verifica la sintassi JSON.",
            )
            sys.exit(1)
    elif os.path.isfile(legacy_conf):
        cfg, _ = load_legacy_conf(legacy_conf)
        devices = [cfg]
        config_source = "mp_manager.conf"
    else:
        # Nessun config: usa default singolo dispositivo
        cfg = dict(DEFAULTS)
        cfg["name"] = "Dispositivo (default)"
        cfg["relays"] = []
        devices = [cfg]
        config_source = "default"

    if not devices:
        messagebox.showerror(
            "Nessun dispositivo",
            "Nessun dispositivo configurato in devices.json.",
        )
        sys.exit(1)

    root = tk.Tk()
    app = MultiDeviceApp(root, devices)

    if config_source == "default":
        messagebox.showwarning(
            "Config non trovato",
            "Nessun devices.json o mp_manager.conf trovato.\n"
            "Uso valori di default (192.168.1.100:502).\n"
            "Copia devices.example.json come devices.json e configura i tuoi dispositivi.",
        )

    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
