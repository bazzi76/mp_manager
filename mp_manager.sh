#!/bin/bash
#
# mp_manager.sh – gestione relè Modbus TCP via modpoll
# Uso:
#   ./mp_manager.sh status
#   ./mp_manager.sh on 2        # accendi relè 2
#   ./mp_manager.sh off 3       # spegni relè 3
#   ./mp_manager.sh all-on
#   ./mp_manager.sh all-off

#IP="10.2.0.5"
#PORT=502
RED="\e[31m"
GREEN="\e[32m"
RESET="\e[0m"

# Percorso del file di configurazione
CONFIG_FILE="./mp_manager.conf"

# Se esiste il file, lo carica
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo -e "${RED} Errore: file di configurazione '$CONFIG_FILE' non trovato.${RESET}"
  exit 1
fi

# Controlla che IP e PORT siano stati definiti
if [[ -z "$IP" || -z "$PORT" ]]; then
  echo -e "${RED} Errore: IP o PORT mancano nel file di configurazione.${RESET}"
  exit 1
fi


OFFSET_FLAG="-0"

command -v modpoll >/dev/null 2>&1 || {
  echo -e "${RED} Errore: il comando 'modpoll' non è stato trovato. Assicurati che sia installato ed accessibile.${RESET}"
  exit 1
}

# Verifica se l'IP è raggiungibile
ping -c 1 $IP >/dev/null 2>&1 || {
  echo -e "${RED} Errore: l'IP $IP non è raggiungibile.${RESET}"
  exit 1
}

function status {
  echo -e "${GREEN}Leggo lo stato di tutti i relè...${RESET}"
  modpoll -m tcp -p $PORT $OFFSET_FLAG -r 0 -c 8 -t 0 -1 $IP
}

function set_relay {
  local num=$1 action=$2
  #local coil=$((num-1)) <-- Modpoll usa indici da 0 a 7 per i relè
  # Attivando la variabile sopora, si usa indici da 1 a 8
  local coil=$num
  if [[ $coil -lt 0 || $coil -gt 7 ]]; then
    echo "❗ Relè invalido: $num (scegli da 0 a 7)"
    exit 1
  fi
  local val=$( [[ $action == "on" ]] && echo 1 || echo 0 )
  echo -e "${GREEN}Imposto relè $num → $action${RESET}"
  modpoll -m tcp -p $PORT $OFFSET_FLAG -r $coil -c 1 -t 0 $IP $val
}

function set_all {
  local action=$1
  local val=$( [[ $action == "on" ]] && echo 1 || echo 0 )
  echo -e "${GREEN}Imposto TUTTI i relè → $action${RESET}"
  modpoll -m tcp -p $PORT $OFFSET_FLAG -r 0 -c 8 -t 0 $IP $val $val $val $val $val $val $val $val
}

case "$1" in
  status)
    status
    ;;
  on|off)
    if [ -z "$2" ]; then
      echo "❗ Usa: $0 on|off <relay_num>"
      exit 1
    fi
    set_relay "$2" "$1"
    ;;
  all-on)
    set_all on
    ;;
  all-off)
    set_all off
    ;;
  *)
    echo "Gestione relè Modbus TCP"
    echo "Uso:"
    echo "  $0 status        # leggi stato relè"
    echo "  $0 on  <0‑7>     # accendi relè (da 0 a 7)"
    echo "  $0 off <0‑7>     # spegni relè (da 0 a 7)"
    echo "  $0 all-on        # accendi tutti"
    echo "  $0 all-off       # spegni tutti"
    exit 1
    ;;
esac
