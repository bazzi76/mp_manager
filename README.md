# mp_manager.sh

Gestione relè e ingressi digitali via **Modbus TCP**, basato su [`modpoll`](https://www.modbusdriver.com/modpoll.html).

Supporta più architetture Linux e permette di specificare l'IP del dispositivo sia da file di configurazione che direttamente da riga di comando.

---

## Requisiti

- Bash 4.0+
- `modpoll` — installato nel PATH di sistema **oppure** presente nella cartella `bin/<arch>/` relativa allo script

### Architetture supportate

| Architettura | Cartella `bin/`             |
|--------------|-----------------------------|
| x86_64       | `x86_64-linux-gnu`          |
| i386 / i686  | `i686-linux-gnu`            |
| aarch64      | `aarch64-linux-gnu`         |
| armv7l       | `arm-linux-gnueabihf`       |
| armv6l       | `armv6-rpi-linux-gnueabihf` |

---

## Configurazione

Lo script cerca il file `mp_manager.conf` nella stessa directory dello script.

Esempio di configurazione minima:

```ini
IP=192.168.1.100       # IP del dispositivo Modbus TCP
PORT=502               # Porta Modbus TCP
MAX_RELAYS=7           # Numero di relè (0-based, quindi 8 relè = 7)
MAX_IN=7               # Numero di ingressi digitali (0-based)
```

Parametri opzionali (se non presenti, vengono usati i valori di default):

```ini
COIL_OFFSET_RELAYS=0   # Offset coil relè          (default: 0)
COIL_OFFSET_INPUTS=0   # Offset ingressi digitali  (default: 0)
MODE_REG_BASE=4096     # Base registro modalità    (default: 4096)
```

> `PORT` e `MAX_RELAYS` sono **obbligatori**: lo script esce con errore se non sono definiti.

---

## Utilizzo

```bash
./mp_manager.sh [-r|-d] <comando> [argomenti] [IP]
```

| Flag | Significato                              |
|------|------------------------------------------|
| `-r` | Operazioni su relè *(default)*           |
| `-d` | Lettura ingressi digitali                |
| `IP` | IP opzionale come ultimo argomento: sovrascrive il valore nel config |

---

## Comandi

### Stato

```bash
./mp_manager.sh status          # Leggi stato relè (default)
./mp_manager.sh status -r       # Leggi stato relè
./mp_manager.sh status -d       # Leggi ingressi digitali
```

### Controllo relè

```bash
./mp_manager.sh on 2            # Accendi relè 2
./mp_manager.sh off 3           # Spegni relè 3
./mp_manager.sh all-on          # Accendi tutti i relè
./mp_manager.sh all-off         # Spegni tutti i relè
./mp_manager.sh toggle-all      # Inverti tutti i relè (ON→OFF, OFF→ON)
```

### Pulse

```bash
./mp_manager.sh pulse 2         # Impulso su relè 2 (durata default: 0.5s)
./mp_manager.sh pulse 2 1.5     # Impulso su relè 2 per 1.5 secondi
```

### Modalità operativa

Ogni relè supporta 4 modalità operative, configurabili via registro holding Modbus:

| Valore | Modalità  | Comportamento                                                  |
|--------|-----------|----------------------------------------------------------------|
| 0      | Normal    | Controllo diretto via comando Modbus                           |
| 1      | Linkage   | Segue lo stato dell'ingresso digitale corrispondente           |
| 2      | Toggle    | Cambia stato quando l'ingresso digitale viene attivato         |
| 3      | Trigger   | Cambia stato quando l'ingresso digitale corrispondente cambia  |

```bash
./mp_manager.sh get-mode 2      # Leggi modalità relè 2
./mp_manager.sh set-mode 2 1    # Imposta relè 2 in modalità Linkage
```

### IP da riga di comando

L'IP può essere passato come ultimo argomento, sovrascrivendo quello nel config:

```bash
./mp_manager.sh status 192.168.1.50
./mp_manager.sh on 2 192.168.1.50
./mp_manager.sh set-mode 2 1 192.168.1.50
```

---

## Struttura del progetto

```
mp_manager.sh
mp_manager.conf
bin/
  x86_64-linux-gnu/modpoll
  aarch64-linux-gnu/modpoll
  arm-linux-gnueabihf/modpoll
  ...
```

---

## Autore

Giacomo Mattei — [giacomo.mattei@grupposimtel.com](mailto:giacomo.mattei@grupposimtel.com)

