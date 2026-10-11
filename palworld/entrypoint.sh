#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
text() {
  local re='^[A-Za-z0-9 _.,!#()-]*$'
  [[ "$1" =~ $re ]] && echo "$1" || echo "$2"
}
pick() {
  local v=$1 d=$2 o
  shift 2
  for o in "$@"; do [ "$v" = "$o" ] && { echo "$v"; return; }; done
  echo "$d"
}

retry() {
  local label=$1 attempt
  shift
  for attempt in 1 2 3; do
    echo "[clouder] $label (attempt $attempt)"
    "$@" && return 0
    sleep 5
  done
  return 1
}

SERVER_PORT=$(num "${SERVER_PORT:-8211}" 8211)
QUERY_PORT=$(num "${QUERY_PORT:-27015}" 27015)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-16}" 16)
SERVER_NAME=$(text "${SERVER_NAME:-Palworld Server}" "Palworld Server")
SERVER_DESCRIPTION=$(text "${SERVER_DESCRIPTION:-}" "")
SERVER_PASSWORD=$(text "${SERVER_PASSWORD:-}" "")
ADMIN_PASSWORD=$(text "${ADMIN_PASSWORD:-}" "")
PVP=$(pick "${PVP:-false}" false true false)
DEATH_PENALTY=$(pick "${DEATH_PENALTY:-All}" All None Item ItemAndEquipment All)
EXP_RATE=$(pick "${EXP_RATE:-1}" 1 0.5 1 2 3 5 10)
PUBLIC_LOBBY=$(pick "${PUBLIC_LOBBY:-false}" false true false)
: "${UPDATE_ON_START:=1}"
: "${VALIDATE_ON_START:=0}"

export HOME=/data
cd /data
mkdir -p steamcmd server

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous +app_update 2394010 "$@" +quit
}

bin=server/Pal/Binaries/Linux/PalServer-Linux-Shipping
if [ ! -x "$bin" ] || [ "$UPDATE_ON_START" = "1" ]; then
  validate=()
  if [ "$VALIDATE_ON_START" = "1" ]; then
    validate=(validate)
  fi
  retry "downloading or updating Palworld" steam_update "${validate[@]}" \
    || { echo "[clouder] could not download the Palworld server" >&2; exit 1; }
fi
[ -f "$bin" ] || { echo "[clouder] PalServer-Linux-Shipping is missing after install" >&2; exit 1; }
chmod +x "$bin"

mkdir -p "$HOME/.steam/sdk64"
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true

cfgdir=server/Pal/Saved/Config/LinuxServer
ini=$cfgdir/PalWorldSettings.ini
mkdir -p "$cfgdir"
if [ ! -s "$ini" ]; then
  cp server/DefaultPalWorldSettings.ini "$ini"
fi

set_opt() {
  sed -i -E "s~([(,])$1=(\"[^\"]*\"|[^,)]*)~\1$1=$2~" "$ini"
}
set_opt ServerName "\"$SERVER_NAME\""
set_opt ServerDescription "\"$SERVER_DESCRIPTION\""
set_opt ServerPassword "\"$SERVER_PASSWORD\""
set_opt AdminPassword "\"$ADMIN_PASSWORD\""
set_opt ServerPlayerMaxNum "$MAX_PLAYERS"
set_opt PublicPort "$SERVER_PORT"
set_opt bIsPvP "$([ "$PVP" = true ] && echo True || echo False)"
set_opt DeathPenalty "$DEATH_PENALTY"
set_opt ExpRate "$EXP_RATE"
set_opt RCONEnabled False
set_opt RESTAPIEnabled False

args=(
  Pal "-port=$SERVER_PORT" "-queryport=$QUERY_PORT" "-players=$MAX_PLAYERS"
  -useperfthreads -NoAsyncLoadingThread -UseMultithreadForDS -log
)
[ "$PUBLIC_LOBBY" = true ] && args+=(-publiclobby)

listening() {
  local hex
  hex=$(printf '%04X' "$1")
  grep -qi ":$hex " /proc/net/udp /proc/net/udp6 2>/dev/null
}

echo "[clouder] starting Palworld"
"$bin" "${args[@]}" &
game=$!

(
  until listening "$SERVER_PORT"; do
    kill -0 "$game" 2>/dev/null || exit 0
    sleep 2
  done
  echo "[clouder] Palworld is ready"
) &

stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking Palworld to save and shut down"
  kill -TERM "$game" 2>/dev/null || true
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
