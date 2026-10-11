#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }

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

SERVER_PORT=$(num "${SERVER_PORT:-7777}" 7777)
RELIABLE_PORT=$(num "${RELIABLE_PORT:-8888}" 8888)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-4}" 4)
AUTOSAVE_COUNT=$(num "${AUTOSAVE_COUNT:-5}" 5)
: "${UPDATE_ON_START:=1}"
: "${VALIDATE_ON_START:=0}"
case "${STEAM_BRANCH:-public}" in experimental) branch=experimental ;; *) branch=public ;; esac

export HOME=/data
cd /data
mkdir -p steamcmd server

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
    +app_update 1690800 -beta "$branch" "$@" +quit
}

if [ ! -x server/FactoryServer.sh ] || [ "$UPDATE_ON_START" = "1" ]; then
  validate=()
  if [ "$VALIDATE_ON_START" = "1" ]; then
    validate=(validate)
  fi
  retry "downloading or updating Satisfactory, branch $branch" steam_update "${validate[@]}" \
    || { echo "[clouder] could not download the Satisfactory server" >&2; exit 1; }
fi
[ -x server/FactoryServer.sh ] || { echo "[clouder] FactoryServer.sh is missing after install" >&2; exit 1; }

mkdir -p "$HOME/.steam/sdk64"
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true

args=(
  "-Port=$SERVER_PORT" "-ReliablePort=$RELIABLE_PORT" "-ExternalReliablePort=$RELIABLE_PORT"
  "-ini:Engine:[/Script/FactoryGame.FGSaveSession]:mNumRotatingAutosaves=$AUTOSAVE_COUNT"
  "-ini:Game:[/Script/Engine.GameSession]:MaxPlayers=$MAX_PLAYERS"
  "-ini:GameUserSettings:[/Script/Engine.GameSession]:MaxPlayers=$MAX_PLAYERS"
  "-multihome=::" -unattended -log
)
[ "${DISABLE_SEASONAL_EVENTS:-false}" = "true" ] && args+=("-DisableSeasonalEvents")

cd server
# FactoryServer.sh does not exec the game, so a stop signal would end the script and never reach it.
bin=Engine/Binaries/Linux/FactoryServer-Linux-Shipping
chmod +x "$bin"
[ -f Engine/Binaries/Linux/crashpad_handler ] && chmod +x Engine/Binaries/Linux/crashpad_handler

echo "[clouder] starting Satisfactory"
"$bin" FactoryGame "${args[@]}" &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking Satisfactory to shut down"
  kill -INT "$game" 2>/dev/null || true
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
