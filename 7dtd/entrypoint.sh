#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
word() { [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] && echo "$1" || echo "$2"; }
choice() {
  local value=$1 fallback=$2 option
  shift 2
  for option in "$@"; do
    [ "$value" = "$option" ] && { echo "$value"; return; }
  done
  echo "$fallback"
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

: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"
SERVER_PORT=$(num "${SERVER_PORT:-26900}" 26900)
TELNET_PORT=$(num "${TELNET_PORT:-8081}" 8081)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-8}" 8)
WORLD_SIZE=$(choice "${WORLD_SIZE:-6144}" 6144 6144 8192 10240)
VISIBILITY=$(choice "${VISIBILITY:-listed}" listed listed friends unlisted)
EAC_ENABLED=$(choice "${EAC_ENABLED:-true}" true true false)
GAME_WORLD=$(choice "${GAME_WORLD:-RWG}" RWG RWG Navezgane)
SAVE_NAME=$(word "${SAVE_NAME:-Clouder}" Clouder)
WORLD_SEED=$(word "${WORLD_SEED:-clouder}" clouder)
STEAM_BRANCH=$(word "${STEAM_BRANCH:-public}" public)
: "${SERVER_NAME:=7 Days to Die Server}"
: "${SERVER_DESCRIPTION:=}"
: "${SERVER_PASSWORD:=}"
: "${UPDATE_ON_START:=1}"
: "${VALIDATE_ON_START:=0}"
case "$VISIBILITY" in listed) visibility=2 ;; friends) visibility=1 ;; *) visibility=0 ;; esac

export HOME=/data
cd /data
mkdir -p steamcmd server userdata

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
    +app_update 294420 -beta "$STEAM_BRANCH" "$@" +quit
}

bin=server/7DaysToDieServer.x86_64
if [ ! -x "$bin" ] || [ "$UPDATE_ON_START" = "1" ]; then
  validate=()
  if [ "$VALIDATE_ON_START" = "1" ]; then
    validate=(validate)
  fi
  retry "downloading or updating 7 Days to Die" steam_update "${validate[@]}" \
    || { echo "[clouder] could not download the 7 Days to Die server" >&2; exit 1; }
fi
[ -x "$bin" ] || { echo "[clouder] the 7 Days to Die server is missing after install" >&2; exit 1; }

mkdir -p "$HOME/.steam/sdk64"
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true

[ -f serverconfig.xml ] || cp server/serverconfig.xml serverconfig.xml
setprop() {
  local count
  count=$(xmlstarlet sel -t -v "count(/ServerSettings/property[@name='$1'])" serverconfig.xml)
  if [ "$count" = "0" ]; then
    xmlstarlet ed -L -s /ServerSettings -t elem -n propertyNew -v "" \
      -i //propertyNew -t attr -n name -v "$1" -i //propertyNew -t attr -n value -v "$2" \
      -r //propertyNew -v property serverconfig.xml
  else
    xmlstarlet ed -L -u "/ServerSettings/property[@name='$1']/@value" -v "$2" serverconfig.xml
  fi
}
setprop ServerPort "$SERVER_PORT"
setprop ServerName "$SERVER_NAME"
setprop ServerDescription "$SERVER_DESCRIPTION"
setprop ServerPassword "$SERVER_PASSWORD"
setprop ServerMaxPlayerCount "$MAX_PLAYERS"
setprop ServerVisibility "$visibility"
setprop GameWorld "$GAME_WORLD"
setprop GameName "$SAVE_NAME"
setprop WorldGenSeed "$WORLD_SEED"
setprop WorldGenSize "$WORLD_SIZE"
setprop EACEnabled "$EAC_ENABLED"
setprop UserDataFolder /data/userdata
setprop TelnetEnabled true
setprop TelnetPort "$TELNET_PORT"
setprop TelnetPassword "$RCON_PASSWORD"
setprop TerminalWindowEnabled false

cd server
export LD_LIBRARY_PATH="$PWD:${LD_LIBRARY_PATH:-}"
echo "[clouder] starting 7 Days to Die"
./7DaysToDieServer.x86_64 -logfile /dev/stdout -quit -batchmode -nographics -dedicated -configfile=/data/serverconfig.xml &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking 7 Days to Die to save and shut down"
  console shutdown >/dev/null 2>&1 || kill -TERM "$game" 2>/dev/null || true
  { sleep 60; kill -TERM "$game" 2>/dev/null || true; } &
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
