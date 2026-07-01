#!/bin/bash

# Author: Giacomo Mattei <giacomo.mattei@grupposimtel.com>
# Merged version: 2026-07-01
# mp_manager.sh - gestione rele e ingressi digitali Modbus TCP
#
# Uso:
#   ./mp_manager.sh status          # leggi rele (default)
#   ./mp_manager.sh status -r       # leggi rele
#   ./mp_manager.sh status -d       # leggi ingressi digitali
#   ./mp_manager.sh on 2            # accendi rele 2
#   ./mp_manager.sh off 3           # spegni rele 3
#   ./mp_manager.sh all-on          # accendi tutti i rele
#   ./mp_manager.sh all-off         # spegni tutti i rele
#   ./mp_manager.sh toggle-all      # inverte tutti i rele
#   ./mp_manager.sh pulse 2 0.5     # impulso su rele 2 per 0.5 secondi
#   ./mp_manager.sh get-mode 2      # leggi modalita rele 2
#   ./mp_manager.sh set-mode 2 1    # imposta modalita rele 2
#   ./mp_manager.sh status 192.168.1.50
#   ./mp_manager.sh on 2 192.168.1.50

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/mp_manager.conf"

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
else
  echo -e "${RED}Errore: file di configurazione '$CONFIG_FILE' non trovato.${RESET}"
  exit 1
fi

if [[ -z "${PORT:-}" ]]; then
  echo -e "${RED}Errore: PORT deve essere definita in '$CONFIG_FILE'.${RESET}"
  exit 1
fi

if [[ -z "${MAX_RELAYS:-}" ]]; then
  echo -e "${RED}Errore: MAX_RELAYS deve essere definito in '$CONFIG_FILE'.${RESET}"
  exit 1
fi

#MAX_RELAYS=${MAX_RELAYS:-7}
MAX_IN=${MAX_IN:-7}
COIL_OFFSET_RELAYS=${COIL_OFFSET_RELAYS:-0}
COIL_OFFSET_INPUTS=${COIL_OFFSET_INPUTS:-0}
MODE_REG_BASE=${MODE_REG_BASE:-4096}

OFFSET_FLAG="-0"
PORT_FLAG="-p $PORT"
ALL_RELAYS=255
MODE_NAMES=("Normal" "Linkage" "Toggle" "Trigger")

is_ipv4() {
  local ip=$1 octet

  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  IFS='.' read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    (( octet >= 0 && octet <= 255 )) || return 1
  done
  return 0
}

find_modpoll() {
  if command -v modpoll >/dev/null 2>&1; then
    MODPOLL="modpoll"
    return
  fi

  local arch arch_dir
  arch=$(uname -m)

  case "$arch" in
    x86_64)    arch_dir="x86_64-linux-gnu" ;;
    i386|i686) arch_dir="i686-linux-gnu" ;;
    aarch64)   arch_dir="aarch64-linux-gnu" ;;
    armv7l)    arch_dir="arm-linux-gnueabihf" ;;
    armv6l)    arch_dir="armv6-rpi-linux-gnueabihf" ;;
    *)
      echo -e "${RED}Errore: architettura non supportata ($arch).${RESET}"
      exit 1
      ;;
  esac

  MODPOLL="$SCRIPT_DIR/bin/${arch_dir}/modpoll"

  if [[ ! -x "$MODPOLL" ]]; then
    echo -e "${RED}Errore: 'modpoll' non trovato nel PATH ne in ${MODPOLL}.${RESET}"
    exit 1
  fi
}

is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

validate_relay_num() {
  local num=$1

  if ! is_uint "$num" || (( num < 0 || num > MAX_RELAYS )); then
    echo -e "${RED}Rele non valido: ${num:-vuoto} (scegli 0-$MAX_RELAYS).${RESET}"
    exit 1
  fi
}

validate_mode() {
  local mode=$1

  if ! is_uint "$mode" || (( mode < 0 || mode > 3 )); then
    echo -e "${RED}Modalita non valida: ${mode:-vuoto} (0=Normal, 1=Linkage, 2=Toggle, 3=Trigger).${RESET}"
    exit 1
  fi
}

status_relays() {
  echo -e "${GREEN}Stato rele (coil $COIL_OFFSET_RELAYS..$((COIL_OFFSET_RELAYS + MAX_RELAYS)))${RESET}"
  "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$COIL_OFFSET_RELAYS" -c "$((MAX_RELAYS + 1))" -t 0 -1 "$TARGET_IP"
}

status_inputs() {
  echo -e "${GREEN}Stato ingressi digitali (input $COIL_OFFSET_INPUTS..$((COIL_OFFSET_INPUTS + MAX_IN)))${RESET}"
  "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$COIL_OFFSET_INPUTS" -c "$((MAX_IN + 1))" -t 1 -1 "$TARGET_IP"
}

set_relay() {
  local num=$1 action=$2 coil val

  validate_relay_num "$num"
  coil=$((COIL_OFFSET_RELAYS + num))
  val=$([[ "$action" == "on" ]] && echo 1 || echo 0)

  echo -e "${GREEN}Imposto rele $num -> $action${RESET}"
  "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$coil" -c 1 -t 0 "$TARGET_IP" "$val"
}

set_all_relays() {
  local action=$1 val
  val=$([[ "$action" == "on" ]] && echo 1 || echo 0)

  echo -e "${GREEN}Imposto TUTTI i rele -> $action${RESET}"
  "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$ALL_RELAYS" -c 1 -t 0 "$TARGET_IP" "$val"
}

toggle_all_relays() {
  local states i coil current_state new_state

  echo -e "${GREEN}Inverto tutti i rele (ON->OFF, OFF->ON)...${RESET}"
  mapfile -t states < <("$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$COIL_OFFSET_RELAYS" -c "$((MAX_RELAYS + 1))" -t 0 -1 "$TARGET_IP" \
    | grep -oE '\[[0-9]+\]:[[:space:]]*[01]' \
    | awk '{print $NF}')

  if (( ${#states[@]} < MAX_RELAYS + 1 )); then
    echo -e "${RED}Errore: impossibile leggere lo stato di tutti i rele.${RESET}"
    exit 1
  fi

  for (( i = 0; i <= MAX_RELAYS; i++ )); do
    coil=$((COIL_OFFSET_RELAYS + i))
    current_state="${states[$i]}"
    new_state=$((1 - current_state))
    echo -e "Rele $i: $current_state -> $new_state"
    "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$coil" -c 1 -t 0 "$TARGET_IP" "$new_state"
  done
}

pulse_relay() {
  local num=$1 duration=${2:-0.5}

  validate_relay_num "$num"
  echo -e "${YELLOW}Eseguo PULSE su rele $num (durata: ${duration}s)${RESET}"
  set_relay "$num" "on"
  sleep "$duration"
  set_relay "$num" "off"
}

get_mode() {
  local num=$1 reg

  validate_relay_num "$num"
  reg=$((MODE_REG_BASE + num))

  echo -e "${GREEN}Leggo modalita rele $num (registro $reg)${RESET}"
  "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$reg" -c 1 -t 4 -1 "$TARGET_IP"
}

set_mode() {
  local num=$1 mode=$2 reg mode_name

  validate_relay_num "$num"
  validate_mode "$mode"

  reg=$((MODE_REG_BASE + num))
  mode_name="${MODE_NAMES[$mode]}"

  echo -e "${GREEN}Imposto modalita rele $num -> $mode ($mode_name) [registro $reg]${RESET}"
  "$MODPOLL" -m tcp $PORT_FLAG $OFFSET_FLAG -r "$reg" -c 1 -t 4 "$TARGET_IP" "$mode"
}

usage() {
  cat <<EOF
Uso: $0 [-r|-d] comando [arg...] [IP]
  -r : operazioni su rele (default)
  -d : lettura ingressi digitali
  IP : opzionale come ultimo argomento; se presente sovrascrive IP del config

Comandi rele:
  status                     : leggi stato rele o ingressi
  on <0-$MAX_RELAYS>         : accendi rele
  off <0-$MAX_RELAYS>        : spegni rele
  all-on                     : accendi tutti i rele
  all-off                    : spegni tutti i rele
  toggle-all                 : inverte tutti i rele
  pulse <num> [duration]     : impulso rele (default 0.5s)

Comandi modalita:
  get-mode <num>             : leggi modalita rele
  set-mode <num> <0-3>       : imposta modalita rele
    0 = Normal   (controllo Modbus)
    1 = Linkage  (segue ingresso digitale)
    2 = Toggle   (cambia stato quando l'ingresso viene attivato)
    3 = Trigger  (cambia stato quando l'ingresso cambia stato)
EOF
}

TARGET_IP="${IP:-}"
if (( $# > 0 )); then
  LAST_ARG="${@: -1}"
  if is_ipv4 "$LAST_ARG"; then
    TARGET_IP="$LAST_ARG"
    set -- "${@:1:$(($# - 1))}"
  fi
fi

if [[ -z "$TARGET_IP" ]]; then
  echo -e "${RED}Errore: IP deve essere definito in '$CONFIG_FILE' oppure passato come ultimo argomento.${RESET}"
  exit 1
fi

find_modpoll

MODE="relays"
CMD=""
ARGS=()

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

case "$CMD" in
  status)
    if [[ "$MODE" == "relays" ]]; then
      status_relays
    else
      status_inputs
    fi
    ;;
  on|off)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED}Il comando '$CMD <num>' funziona solo sui rele.${RESET}"
      exit 1
    fi
    if [[ ${#ARGS[@]} -lt 1 ]]; then
      echo -e "${RED}Usa: $0 on|off <relay_num>${RESET}"
      exit 1
    fi
    set_relay "${ARGS[0]}" "$CMD"
    ;;
  all-on)
    [[ "$MODE" == "relays" ]] || { echo -e "${RED}Il comando '$CMD' funziona solo sui rele.${RESET}"; exit 1; }
    set_all_relays "on"
    ;;
  all-off)
    [[ "$MODE" == "relays" ]] || { echo -e "${RED}Il comando '$CMD' funziona solo sui rele.${RESET}"; exit 1; }
    set_all_relays "off"
    ;;
  toggle-all)
    [[ "$MODE" == "relays" ]] || { echo -e "${RED}Il comando '$CMD' funziona solo sui rele.${RESET}"; exit 1; }
    toggle_all_relays
    ;;
  pulse)
    if [[ "$MODE" != "relays" ]]; then
      echo -e "${RED}Il comando '$CMD <num> [duration]' funziona solo sui rele.${RESET}"
      exit 1
    fi
    if [[ ${#ARGS[@]} -lt 1 ]]; then
      echo -e "${RED}Usa: $0 pulse <relay_num> [duration]${RESET}"
      exit 1
    fi
    pulse_relay "${ARGS[0]}" "${ARGS[1]:-0.5}"
    ;;
  get-mode)
    if [[ ${#ARGS[@]} -lt 1 ]]; then
      echo -e "${RED}Usa: $0 get-mode <relay_num>${RESET}"
      exit 1
    fi
    get_mode "${ARGS[0]}"
    ;;
  set-mode)
    if [[ ${#ARGS[@]} -lt 2 ]]; then
      echo -e "${RED}Usa: $0 set-mode <relay_num> <0-3>${RESET}"
      exit 1
    fi
    set_mode "${ARGS[0]}" "${ARGS[1]}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
