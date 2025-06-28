#!/bin/bash
#

# Author Giacomo Mattei <giacomo.mattei@grupposimtel.com>
# Date 2025-06-28
# Version 1.0
# mp_manager.sh – gestione relè o ingressi digitali Modbus TCP
# Uso:
#   ./mp_manager.sh status         # leggi relè (default)
#   ./mp_manager.sh status -r      # leggi relè
#   ./mp_manager.sh status -d      # leggi ingressi digitali
#   ./mp_manager.sh on 2           # accendi relè 2
#   ./mp_manager.sh off 3          # spegni relè 3
#   ./mp_manager.sh all-on         # accendi tutti relè
#   ./mp_manager.sh all-off        # spegni tutti relè

CONFIG_FILE="./mp_manager.conf"
RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

# carica config e se non esiste mostra errore
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo -e "${RED}Errore: file di configurazione '$CONFIG_FILE' non trovato.${RESET}"
  exit 1
fi

# verifica modpoll se è nel path, altrimenti utilizza quello nel pacchetto in basse alla architettura
command -v modpoll >/dev/null 2>&1 || {
  echo -e "${RED}Errore: 'modpoll' non trovato. Installa ed assicurati che sia in PATH.${RESET}"
  exit 1
}

OFFSET_FLAG="-0"  # zero-based
PORT_FLAG="-p $PORT"
ALL_RELAYS=255

# coil base per relè e ingressi digitali (da configurare se diverso)
COIL_OFFSET_RELAYS=${COIL_OFFSET_RELAYS:-0}
COIL_OFFSET_INPUTS=${COIL_OFFSET_INPUTS:-0}

# Funzioni
function status_relays {
  echo -e "${GREEN} Stato relè (coil $COIL_OFFSET_RELAYS..$((COIL_OFFSET_RELAYS+7)))${RESET}"
  modpoll -m tcp $PORT_FLAG $OFFSET_FLAG -r $COIL_OFFSET_RELAYS -c 8 -t 0 -1 $IP
}

function status_inputs {
  echo -e "${GREEN} Stato ingressi digitali (coil $COIL_OFFSET_INPUTS..$((COIL_OFFSET_INPUTS+7)))${RESET}"
  modpoll -m tcp $PORT_FLAG $OFFSET_FLAG -r $COIL_OFFSET_INPUTS -c 8 -t 1 -1 $IP
}

function set_relay {
  echo "parametri= $@"
  local num=$1 action=$2
  local coil=$((COIL_OFFSET_RELAYS + num))
  if [[ $num -lt 0 || $num -gt 7 ]]; then
    echo -e "${RED} Relè invalido: $num (scegli 0‑7)${RESET}"
    exit 1
  fi
  local val=$([[ $action == "on" ]] && echo 1 || echo 0)
  echo -e "${GREEN} Imposto relè $num → $action${RESET}"
  modpoll -m tcp $PORT_FLAG $OFFSET_FLAG -r $coil -c 1 -t 0 $IP $val
}

function set_all_relays {
  echo "Parametro= $1"
  local action=$1
  local val=$([[ $action == "on" ]] && echo 1 || echo 0)
  echo "Valore= $val"
  echo -e "${GREEN} Imposto TUTTI i relè → $action${RESET}"
  modpoll -m tcp $PORT_FLAG $OFFSET_FLAG -r $ALL_RELAYS -c 1 -t 0 $IP $val
}

# Parsing parametri
#MODE="relays"
#CMD="$2"
#shift || true

# controllo opzioni
# se il primo argomento non inizia con '-', assume che sia un comando
# altrimenti considera il primo argomento come modalità (relays o inputs)
# e il secondo come comando
# se il primo argomento è '-r' o '-d', cambia modalità
# se il primo argomento è un comando, lo usa come tale
# se il primo argomento è un comando e non è '-r' o '-d',
# assume che sia un comando per relè (default)

#debug
echo "parametri= $@"
if [[ "$1" != -* ]]; then
    MODE="relays"
    CMD="$1"
else
    MODE="$1"
    CMD="$2"
    
fi


while [[ "$1" == -* ]]; do
  case "$1" in
    -r) MODE="relays"; shift ;;
    -d) MODE="inputs"; shift ;;
    *) echo -e "${RED}Opzione sconosciuta $1${RESET}"; exit 1 ;;
  esac
done

#debug
echo "MODE= $MODE"
echo "CMD= $CMD"

# Comandi
case "$CMD" in
  status)
    if [[ "$MODE" == "relays" ]]; then status_relays; else status_inputs; fi
    ;;
  on|off)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED} Il comando '$CMD <num>' funziona solo su relè.${RESET}"
      exit 1
    fi
    if [[ -z "$2" ]]; then
      echo -e "${RED} Usa: $0 on|off <relay_num>${RESET}"
      exit 1
    fi
    set_relay "$2" "$CMD"
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
  *)
    echo "Uso: $0 [-r|-d] comando [arg]"
    echo "  -r : operazioni su relè (default)"
    echo "  -d : lettura ingressi digitali"
    echo "Comandi possibili:"
    echo "  status          : leggi stato relè o ingressi"
    echo "  on <0‑7>        : accendi relè"
    echo "  off <0‑7>       : spegni relè"
    echo "  all-on          : accendi tutti i relè"
    echo "  all-off         : spegni tutti i relè"
    exit 1
    ;;
esac

