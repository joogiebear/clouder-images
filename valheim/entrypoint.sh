#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
text() {
  local re='^[A-Za-z0-9 _.,!#()-]+$'
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

SERVER_PORT=$(num "${SERVER_PORT:-2456}" 2456)
SERVER_NAME=$(text "${SERVER_NAME:-Valheim Server}" "Valheim Server")
WORLD_NAME=$(text "${WORLD_NAME:-Dedicated}" "Dedicated")
SAVE_INTERVAL=$(num "${SAVE_INTERVAL:-1800}" 1800)
BACKUPS=$(num "${BACKUPS:-4}" 4)
PUBLIC=$(pick "${PUBLIC:-false}" false true false)
CROSSPLAY=$(pick "${CROSSPLAY:-false}" false true false)
PRESET=$(pick "${PRESET:-normal}" normal normal casual easy hard hardcore immersive hammer)
: "${UPDATE_ON_START:=1}"
: "${SERVER_PASSWORD:=}"

if [ -n "$SERVER_PASSWORD" ]; then
  if [ "${#SERVER_PASSWORD}" -lt 5 ]; then
    echo "[clouder] SERVER_PASSWORD must be empty or at least 5 characters long" >&2
    exit 1
  fi
  if [[ "${SERVER_NAME,,}" == *"${SERVER_PASSWORD,,}"* ]]; then
    echo "[clouder] SERVER_PASSWORD must not be part of the server name" >&2
    exit 1
  fi
fi

export HOME=/data
cd /data
mkdir -p steamcmd server saves

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous +app_update 896660 +quit
}

if [ ! -x server/valheim_server.x86_64 ] || [ "$UPDATE_ON_START" = "1" ]; then
  retry "downloading or updating Valheim" steam_update \
    || { echo "[clouder] could not download the Valheim server" >&2; exit 1; }
fi
[ -x server/valheim_server.x86_64 ] || { echo "[clouder] valheim_server.x86_64 is missing after install" >&2; exit 1; }

mkdir -p "$HOME/.steam/sdk64"
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true

args=(
  -nographics -batchmode
  -name "$SERVER_NAME" -port "$SERVER_PORT" -world "$WORLD_NAME" -password "$SERVER_PASSWORD"
  -savedir /data/saves -public "$([ "$PUBLIC" = true ] && echo 1 || echo 0)"
  -saveinterval "$SAVE_INTERVAL" -backups "$BACKUPS" -preset "$PRESET"
)
[ "$CROSSPLAY" = true ] && args+=(-crossplay)

cd server
export LD_LIBRARY_PATH="./linux64:${LD_LIBRARY_PATH:-}"
export SteamAppId=892970

echo "[clouder] starting Valheim"
./valheim_server.x86_64 "${args[@]}" &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking Valheim to save and shut down"
  kill -INT "$game" 2>/dev/null || true
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
