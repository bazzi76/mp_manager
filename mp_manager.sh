#!/bin/bash
#

# Author Giacomo Mattei <giacomo.mattei@grupposimtel.com>
# Date 2025-06-28
# Version 1.1
# mp_manager.sh – gestione relè o ingressi digitali Modbus TCP
# Uso:
#   ./mp_manager.sh status         # leggi relè (default)
#   ./mp_manager.sh status -r      # leggi relè
#   ./mp_manager.sh status -d      # leggi ingressi digitali
#   ./mp_manager.sh on 2           # accendi relè 2
#   ./mp_manager.sh off 3          # spegni relè 3
#   ./mp_manager.sh all-on         # accendi tutti relè
#   ./mp_manager.sh all-off        # spegni tutti relè
#   ./mp_manager.sh get-mode 2     # leggi modalità relè 2 (0=Normal,1=Linkage,2=FlashON,3=FlashOFF)
#   ./mp_manager.sh set-mode 2 1   # imposta modalità relè 2 → Linkage
#   LAST UPDATE 24-03-2026 G.Mattei

CONFIG_FILE="./mp_manager.conf"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

# carica config e se non esiste mostra errore
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo -e "${RED}Errore: file di configurazione '$CONFIG_FILE' non trovato.${RESET}"
  exit 1
fi

# Inizializza MODPOLL con il comando globale se esiste
if command -v modpoll >/dev/null 2>&1; then
    MODPOLL="modpoll"
else
    # Rileva architettura
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)   ARCH_DIR="x86_64-linux-gnu" ;;
        i386|i686) ARCH_DIR="i686-linux-gnu" ;;
        aarch64)  ARCH_DIR="aarch64-linux-gnu" ;;
        armv7l)   ARCH_DIR="arm-linux-gnueabihf" ;;
        armv6l)   ARCH_DIR="armv6-rpi-linux-gnueabihf" ;;
        *)
            echo -e "${RED}Errore: architettura non supportata ($ARCH).${RESET}"
            exit 1
            ;;
    esac

    MODPOLL="./bin/${ARCH_DIR}/modpoll"

    if [[ ! -x "$MODPOLL" ]]; then
        echo -e "${RED}Errore: 'modpoll' non trovato nel PATH né in ${MODPOLL}.${RESET}"
        exit 1
    fi
fi

OFFSET_FLAG="-0"  # zero-based
PORT_FLAG="-p $PORT"
ALL_RELAYS=255

# Offset coil per relè e ingressi digitali
# Se non impostati nel .conf assume 0 come default
COIL_OFFSET_RELAYS=${COIL_OFFSET_RELAYS:-0}
COIL_OFFSET_INPUTS=${COIL_OFFSET_INPUTS:-0}

# Indirizzo base registro modalità (4x1000 → indirizzo decimale 4096)
# Registro holding: 4x1000+N per relè N (zero-based)
MODE_REG_BASE=${MODE_REG_BASE:-4096}

# Nomi modalità per output leggibile
MODE_NAMES=("Normal" "Linkage" "FlashON" "FlashOFF")

# ---------- Funzioni ----------

function status_relays {
  echo -e "${GREEN} Stato relè (coil $COIL_OFFSET_RELAYS..$((COIL_OFFSET_RELAYS+MAX_RELAYS)))${RESET}"
  $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $COIL_OFFSET_RELAYS -c $((MAX_RELAYS+1)) -t 0 -1 $IP
}

function status_inputs {
  echo -e "${GREEN} Stato ingressi digitali (input $COIL_OFFSET_INPUTS..$((COIL_OFFSET_INPUTS+MAX_IN)))${RESET}"
  $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $COIL_OFFSET_INPUTS -c $((MAX_IN+1)) -t 1 -1 $IP
}

function toggle_all_relays {
  echo -e "${GREEN}Toggling all relays (ON→OFF, OFF→ON)...${RESET}"
  mapfile -t states < <($MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $COIL_OFFSET_RELAYS -c $((MAX_RELAYS+1)) -t 0 -1 $IP | grep -oE '\[[0-9]+\]:[[:space:]]*[01]' | awk '{print $NF}')
  for (( i=0; i<=MAX_RELAYS; i++ )); do
    local coil=$((COIL_OFFSET_RELAYS + i))
    local current_state="${states[$i]}"
    local new_state=$(( ! current_state ))
    echo -e "Relay $i: $current_state → $new_state"
    $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $coil -c 1 -t 0 $IP $new_state
  done
}

function set_relay {
  local num=$1 action=$2
  local coil=$((COIL_OFFSET_RELAYS + num))
  if [[ $num -lt 0 || $num -gt $MAX_RELAYS ]]; then
    echo -e "${RED} Relè invalido: $num (scegli 0‑$MAX_RELAYS)${RESET}"
    exit 1
  fi
  local val=$([[ $action == "on" ]] && echo 1 || echo 0)
  echo -e "${GREEN} Imposto relè $num → $action${RESET}"
  $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $coil -c 1 -t 0 $IP $val
}

function set_all_relays {
  local action=$1
  local val=$([[ $action == "on" ]] && echo 1 || echo 0)
  echo -e "${GREEN} Imposto TUTTI i relè → $action${RESET}"
  $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $ALL_RELAYS -c 1 -t 0 $IP $val
}

function pulse_relay {
  local num=$1
  local duration=${2:-0.5}
  echo -e "${YELLOW} Eseguo PULSE su relè $num (durata: ${duration}s)${RESET}"
  set_relay "$num" "on"
  sleep "$duration"
  set_relay "$num" "off"
}

function get_mode {
  # Legge la modalità operativa di un relè (registro holding 4x, FC3)
  # Indirizzo: MODE_REG_BASE + num  (es. 4096 + 0 = 4096 per relè 0)
  local num=$1
  if [[ $num -lt 0 || $num -gt $MAX_RELAYS ]]; then
    echo -e "${RED} Relè invalido: $num (scegli 0‑$MAX_RELAYS)${RESET}"
    exit 1
  fi
  local reg=$((MODE_REG_BASE + num))
  echo -e "${GREEN} Leggo modalità relè $num (registro $reg)${RESET}"
  # -t 4 = Holding Register (FC3), -c 1 = un solo registro, -1 = singola lettura
  $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $reg -c 1 -t 4 -1 $IP
}

function set_mode {
  # Imposta la modalità operativa di un relè (registro holding 4x, FC6)
  # Valori: 0=Normal, 1=Linkage, 2=FlashON, 3=FlashOFF
  local num=$1 mode=$2
  if [[ $num -lt 0 || $num -gt $MAX_RELAYS ]]; then
    echo -e "${RED} Relè invalido: $num (scegli 0‑$MAX_RELAYS)${RESET}"
    exit 1
  fi
  if [[ $mode -lt 0 || $mode -gt 3 ]]; then
    echo -e "${RED} Modalità non valida: $mode (0=Normal, 1=Linkage, 2=FlashON, 3=FlashOFF)${RESET}"
    exit 1
  fi
  local reg=$((MODE_REG_BASE + num))
  local mode_name="${MODE_NAMES[$mode]}"
  echo -e "${GREEN} Imposto modalità relè $num → $mode ($mode_name) [registro $reg]${RESET}"
  # -t 4 = Holding Register (FC6 per scrittura singola)
  $MODPOLL -m tcp $PORT_FLAG $OFFSET_FLAG -r $reg -c 1 -t 4 $IP $mode
}

# ---------- Parsing parametri ----------
# Gestisce qualsiasi ordine di flag e argomenti:
#   status -d  oppure  -d status
#   on 2  oppure  set-mode 2 1  ecc.

MODE="relays"
CMD=""
ARGS=()   # argomenti posizionali (numeri relay, durate, ecc.)

for arg in "$@"; do
  case "$arg" in
    -r) MODE="relays" ;;
    -d) MODE="inputs" ;;
    *)
      if [[ -z "$CMD" ]]; then
        CMD="$arg"
      else
        ARGS+=("$arg")
      fi
      ;;
  esac
done

# ---------- Comandi ----------
case "$CMD" in
  status)
    if [[ "$MODE" == "relays" ]]; then status_relays; else status_inputs; fi
    ;;
  on|off)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED} Il comando '$CMD <num>' funziona solo su relè.${RESET}"
      exit 1
    fi
    if [[ ${#ARGS[@]} -eq 0 ]]; then
      echo -e "${RED} Usa: $0 on|off <relay_num>${RESET}"
      exit 1
    fi
    set_relay "${ARGS[0]}" "$CMD"
    ;;
  all-on)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED} Il comando '$CMD' è solo per relè.${RESET}"
      exit 1
    fi
    set_all_relays "on"
    ;;
  all-off)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED} Il comando '$CMD' è solo per relè.${RESET}"
      exit 1
    fi
    set_all_relays "off"
    ;;
  toggle-all)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED} 'toggle-all' funziona solo su relè.${RESET}"
      exit 1
    fi
    toggle_all_relays
    ;;
  pulse)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED} Il comando '$CMD <num> [duration]' è solo per relè.${RESET}"
      exit 1
    fi
    if [[ ${#ARGS[@]} -eq 0 ]]; then
      echo -e "${RED} Usa: $0 pulse <relay_num> [duration]${RESET}"
      exit 1
    fi
    pulse_relay "${ARGS[0]}" "${ARGS[1]:-0.5}"
    ;;
  get-mode)
    if [[ ${#ARGS[@]} -eq 0 ]]; then
      echo -e "${RED} Usa: $0 get-mode <relay_num>${RESET}"
      exit 1
    fi
    get_mode "${ARGS[0]}"
    ;;
  set-mode)
    if [[ ${#ARGS[@]} -lt 2 ]]; then
      echo -e "${RED} Usa: $0 set-mode <relay_num> <0-3>${RESET}"
      echo -e "  0 = Normal   (controllo via comando Modbus)"
      echo -e "  1 = Linkage  (segue ingresso digitale corrispondente)"
      echo -e "  2 = FlashON  (accensione temporizzata)"
      echo -e "  3 = FlashOFF (spegnimento temporizzato)"
      exit 1
    fi
    set_mode "${ARGS[0]}" "${ARGS[1]}"
    ;;
  *)
    echo "Uso: $0 [-r|-d] comando [arg...]"
    echo "  -r : operazioni su relè (default)"
    echo "  -d : lettura ingressi digitali"
    echo ""
    echo "Comandi relè:"
    echo "  status                       : leggi stato relè o ingressi"
    echo "  on <0‑$MAX_RELAYS>                   : accendi relè"
    echo "  off <0‑$MAX_RELAYS>                  : spegni relè"
    echo "  all-on                       : accendi tutti i relè"
    echo "  all-off                      : spegni tutti i relè"
    echo "  toggle-all                   : inverte tutti i relè"
    echo "  pulse <num> [duration]       : pulse relè (default 0.5s)"
    echo ""
    echo "Comandi modalità:"
    echo "  get-mode <num>               : leggi modalità relè"
    echo "  set-mode <num> <0-3>         : imposta modalità relè"
    echo "    0 = Normal   (controllo Modbus)"
    echo "    1 = Linkage  (segue ingresso digitale)"
    echo "    2 = FlashON  (accensione temporizzata)"
    echo "    3 = FlashOFF (spegnimento temporizzato)"
    exit 1
    ;;
esac
