#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
word() { [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] && echo "$1" || echo "$2"; }
secret() { [[ "$1" =~ ^[A-Za-z0-9_.-]*$ ]] && echo "$1" || echo ""; }
text() { [[ "$1" =~ ^[A-Za-z0-9\ _.,!#()-]*$ ]] && echo "$1" || echo "$2"; }

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

: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"
SERVER_PORT=$(num "${SERVER_PORT:-7777}" 7777)
QUERY_PORT=$(num "${QUERY_PORT:-27015}" 27015)
RCON_PORT=$(num "${RCON_PORT:-27020}" 27020)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-20}" 20)
MAP=$(word "${MAP:-TheIsland}" TheIsland)
STEAM_BRANCH=$(word "${STEAM_BRANCH:-public}" public)
SERVER_NAME=$(text "${SERVER_NAME:-ARK Server}" "ARK Server")
SERVER_PASSWORD=$(secret "${SERVER_PASSWORD:-}")
ADMIN_PASSWORD=$(secret "${ADMIN_PASSWORD:-}")
ADMIN_PASSWORD=${ADMIN_PASSWORD:-$RCON_PASSWORD}
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
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
    +app_update 376030 -beta "$STEAM_BRANCH" "$@" +quit
}

bin=server/ShooterGame/Binaries/Linux/ShooterGameServer
if [ ! -x "$bin" ] || [ "$UPDATE_ON_START" = "1" ]; then
  validate=()
  if [ "$VALIDATE_ON_START" = "1" ]; then
    validate=(validate)
  fi
  retry "downloading or updating ARK: Survival Evolved" steam_update "${validate[@]}" \
    || { echo "[clouder] could not download the ARK server" >&2; exit 1; }
fi
[ -x "$bin" ] || { echo "[clouder] ShooterGameServer is missing after install" >&2; exit 1; }

mkdir -p "$HOME/.steam/sdk64" "$HOME/.steam/sdk32"
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true
ln -sf /data/steamcmd/linux32/steamclient.so "$HOME/.steam/sdk32/steamclient.so" 2>/dev/null || true
ulimit -n 100000 2>/dev/null || true

url="$MAP?listen?SessionName=$SERVER_NAME?Port=$SERVER_PORT?QueryPort=$QUERY_PORT"
url="$url?RCONEnabled=True?RCONPort=$RCON_PORT?ServerAdminPassword=$ADMIN_PASSWORD?MaxPlayers=$MAX_PLAYERS"
[ -z "$SERVER_PASSWORD" ] || url="$url?ServerPassword=$SERVER_PASSWORD"

cd server
export LD_LIBRARY_PATH="$PWD/linux64:${LD_LIBRARY_PATH:-}"
echo "[clouder] starting ARK: Survival Evolved"
./ShooterGame/Binaries/Linux/ShooterGameServer "$url" -server -log -NoBattlEye &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving the world and shutting down ARK"
  { console saveworld && console DoExit; } >/dev/null 2>&1 || kill -TERM "$game" 2>/dev/null || true
  { sleep 90; kill -TERM "$game" 2>/dev/null || true; } &
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
