#!/usr/bin/env python3
"""
mp_manager_win.py — GUI Windows per controllo relè Waveshare Modbus TCP.
Addon multipiattaforma di mp_manager.sh (versione Linux/bash).

Avvio:  python mp_manager_win.py
Richiede:  pip install pyModbusTCP
Config:    legge mp_manager.conf nella stessa directory dello script

Autore: Giacomo Mattei <giacomo.mattei@grupposimtel.com>
"""

import os
import sys
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
    "IP": "192.168.1.100",
    "PORT": "502",
    "MAX_RELAYS": "7",
    "MAX_IN": "7",
    "COIL_OFFSET_RELAYS": "0",
    "COIL_OFFSET_INPUTS": "0",
    "MODE_REG_BASE": "4096",
}

ALL_RELAYS_COIL = 255  # coil broadcast Waveshare: scrive tutti i relè


def load_config(conf_path):
    """Legge mp_manager.conf (formato KEY=value, # = commento)."""
    cfg = dict(DEFAULTS)
    found = os.path.isfile(conf_path)
    if not found:
        return cfg, False
    with open(conf_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip()
                # rimuove commenti inline
                if "#" in val:
                    val = val.split("#")[0].strip()
                if key:
                    cfg[key] = val
    return cfg, True


# ─── GUI ──────────────────────────────────────────────────────────────

# Colori
ON_BG = "#1e8e3e"        # verde acceso
ON_FG = "#ffffff"
OFF_BG = "#3c4043"       # grigio scuro
OFF_FG = "#9aa0a6"
UNKNOWN_BG = "#5f6368"   # grigio medio
UNKNOWN_FG = "#cccccc"
HDR_CONN = "#1e8e3e"
HDR_DISC = "#cc3333"
HDR_WARN = "#cc9933"


class RelayApp:
    def __init__(self, root, conf_path):
        self.root = root
        self.conf_path = conf_path
        self.cfg, conf_found = load_config(conf_path)

        self.ip = self.cfg["IP"]
        self.port = int(self.cfg["PORT"])
        self.max_relays = int(self.cfg["MAX_RELAYS"])
        self.coil_offset = int(self.cfg["COIL_OFFSET_RELAYS"])
        self.num_relays = self.max_relays + 1  # 0-based

        self.client = None
        self.relay_states = [None] * self.num_relays
        self.auto_refresh = tk.BooleanVar(value=False)
        self.pulse_mode = tk.BooleanVar(value=False)
        self.pulse_duration = tk.StringVar(value="2.0")
        self._refresh_job = None
        self._pulsing = set()  # relè attualmente in pulse (bottoni disabilitati)

        self._build_ui()

        if not conf_found:
            messagebox.showwarning(
                "Config non trovato",
                f"File '{os.path.basename(conf_path)}' non trovato.\n"
                f"Uso valori di default (IP {self.ip}:{self.port}).\n"
                f"Copia mp_manager.conf nella stessa cartella dello script.",
            )

        self._connect()
        self._refresh_status()

    # ── UI ────────────────────────────────────────────────────────────

    def _build_ui(self):
        self.root.title("MP Manager — Waveshare Modbus Relay")
        self.root.resizable(False, False)

        style = ttk.Style()
        try:
            style.theme_use("vista")
        except tk.TclError:
            pass

        # Header
        header = ttk.Frame(self.root, padding=10)
        header.grid(row=0, column=0, sticky="ew")

        ttk.Label(header, text="Dispositivo:").grid(row=0, column=0, sticky="w")
        self.lbl_device = ttk.Label(
            header, text=f"{self.ip}:{self.port}", font=("Segoe UI", 10, "bold")
        )
        self.lbl_device.grid(row=0, column=1, sticky="w", padx=(4, 16))

        self.btn_refresh = ttk.Button(header, text="Aggiorna", width=10,
                                      command=self._refresh_status)
        self.btn_refresh.grid(row=0, column=2)

        self.lbl_status = ttk.Label(header, text="● Disconnesso",
                                    foreground=HDR_DISC)
        self.lbl_status.grid(row=0, column=3, padx=(16, 0))

        # Relè
        relay_frame = ttk.LabelFrame(self.root, text="Relè", padding=10)
        relay_frame.grid(row=1, column=0, sticky="nsew", padx=10, pady=(0, 10))

        self.relay_buttons = []
        cols = 4
        for i in range(self.num_relays):
            r, c = divmod(i, cols)
            btn = tk.Button(
                relay_frame,
                text=f"R{i}\n???",
                width=8,
                height=2,
                font=("Consolas", 10, "bold"),
                relief="flat",
                bd=0,
                highlightthickness=0,
                command=lambda n=i: self._handle_relay_click(n),
            )
            btn.grid(row=r, column=c, padx=4, pady=4)
            self.relay_buttons.append(btn)

        # Bottom bar
        bottom = ttk.Frame(self.root, padding=(10, 0, 10, 10))
        bottom.grid(row=2, column=0, sticky="ew")

        ttk.Button(bottom, text="Tutti ON", command=self._all_on).grid(row=0, column=0, padx=4)
        ttk.Button(bottom, text="Tutti OFF", command=self._all_off).grid(row=0, column=1, padx=4)
        ttk.Checkbutton(bottom, text="Auto-refresh (2s)",
                        variable=self.auto_refresh,
                        command=self._toggle_auto_refresh).grid(row=0, column=2, padx=(20, 0))

        # Pulse mode
        ttk.Checkbutton(bottom, text="Pulse mode",
                        variable=self.pulse_mode).grid(row=0, column=3, padx=(20, 0))
        ttk.Label(bottom, text="Durata (s):").grid(row=0, column=4, padx=(8, 2))
        pulse_entry = ttk.Entry(bottom, textvariable=self.pulse_duration, width=5)
        pulse_entry.grid(row=0, column=5)

    # ── Modbus ────────────────────────────────────────────────────────

    def _connect(self):
        """Apre la connessione Modbus TCP."""
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
        """Legge lo stato di tutti i relè dal dispositivo."""
        if not self.client or not self.client.is_open:
            if not self._connect():
                return
        try:
            bits = self.client.read_coils(self.coil_offset, self.num_relays)
            if bits is None:
                # un retry
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
            if state is None:
                btn.config(text=f"R{i}\n???", bg=UNKNOWN_BG, fg=UNKNOWN_FG,
                           activebackground=UNKNOWN_BG)
            elif state:
                btn.config(text=f"R{i}\nON", bg=ON_BG, fg=ON_FG,
                           activebackground=ON_BG)
            else:
                btn.config(text=f"R{i}\nOFF", bg=OFF_BG, fg=OFF_FG,
                           activebackground=OFF_BG)

    def _toggle_relay(self, num):
        """Inverte on/off del relè num."""
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
        """Gestisce il click su un relè: toggle o pulse in base alla modalità."""
        if num in self._pulsing:
            return  # pulse già in corso su questo relè
        if self.pulse_mode.get():
            self._pulse_relay(num)
        else:
            self._toggle_relay(num)

    def _get_pulse_duration(self):
        """Legge e valida la durata pulse dal campo di testo. Ritorna float o None."""
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
        """Invia un pulse al relè num: ON, attende durata, OFF. Non bloccante."""
        duration = self._get_pulse_duration()
        if duration is None:
            return
        if not self.client or not self.client.is_open:
            if not self._connect():
                return
        coil = self.coil_offset + num
        try:
            ok = self.client.write_single_coil(coil, True)
            if not ok:
                messagebox.showerror("Errore", f"Impossibile attivare il pulse sul relè {num}.")
                return
            # Stato ON + disabilita il bottone durante il pulse
            self.relay_states[num] = True
            self._pulsing.add(num)
            self.relay_buttons[num].config(state="disabled", text=f"R{num}\nPULSE")
            self._update_button_colors()
            # Schedula lo spegnimento
            self.root.after(int(duration * 1000),
                            lambda: self._pulse_off(num, coil))
        except Exception as e:
            messagebox.showerror("Errore", f"Errore pulse relè {num}:\n{e}")
            self._pulsing.discard(num)

    def _pulse_off(self, num, coil):
        """Seconda fase del pulse: spegne il relè e riabilita il bottone."""
        try:
            self.client.write_single_coil(coil, False)
            self.relay_states[num] = False
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

    def on_close(self):
        if self._refresh_job:
            self.root.after_cancel(self._refresh_job)
        if self.client:
            self.client.close()
        self.root.destroy()


# ─── Main ─────────────────────────────────────────────────────────────

def main():
    script_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    conf_path = os.path.join(script_dir, "mp_manager.conf")

    root = tk.Tk()
    app = RelayApp(root, conf_path)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
