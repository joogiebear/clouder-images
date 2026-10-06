#!/usr/bin/env bash
# Installs or updates the Satisfactory dedicated server with SteamCMD, then runs it.
# Everything is configured through environment variables; the panel sets them. The launch
# arguments follow the community wolveix/satisfactory-server image, which refuses to run as
# any user but uid 1000 and so cannot be started the way ClouderNode's agent runs servers.
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }

SERVER_PORT=$(num "${SERVER_PORT:-7777}" 7777)
RELIABLE_PORT=$(num "${RELIABLE_PORT:-8888}" 8888)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-4}" 4)
AUTOSAVE_COUNT=$(num "${AUTOSAVE_COUNT:-5}" 5)
: "${UPDATE_ON_START:=1}"
# public, or experimental for the early-access branch.
case "${STEAM_BRANCH:-public}" in experimental) branch=experimental ;; *) branch=public ;; esac

export HOME=/data
cd /data
mkdir -p steamcmd server

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

install_game() {
  # SteamCMD fails now and then for network reasons, so retry a few times.
  for attempt in 1 2 3; do
    echo "[clouder] downloading or updating Satisfactory, branch $branch (attempt $attempt)"
    if steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
        +app_update 1690800 -beta "$branch" validate +quit; then
      return 0
    fi
    sleep 5
  done
  return 1
}

if [ ! -x server/FactoryServer.sh ] || [ "$UPDATE_ON_START" = "1" ]; then
  install_game || { echo "[clouder] could not download the Satisfactory server" >&2; exit 1; }
fi
[ -x server/FactoryServer.sh ] || { echo "[clouder] FactoryServer.sh is missing after install" >&2; exit 1; }

# The game keeps its Steam client libraries here and complains loudly if they are missing.
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

echo "[clouder] starting Satisfactory"
cd server
# FactoryServer.sh starts the game as a child without exec, so a stop signal sent to it would kill
# the script and never reach the game, which would then not save or shut down cleanly. Run the game
# binary itself and hand it the stop signal.
bin=Engine/Binaries/Linux/FactoryServer-Linux-Shipping
chmod +x "$bin"
[ -f Engine/Binaries/Linux/crashpad_handler ] && chmod +x Engine/Binaries/Linux/crashpad_handler
"$bin" FactoryGame "${args[@]}" &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking Satisfactory to shut down"
  kill -INT "$game" 2>/dev/null || true
}
trap stop TERM INT
# wait returns early when a trapped signal arrives, so keep waiting until the game is really gone.
rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
# A shutdown we asked for is not a failure, whatever code the game exits with after the signal.
[ "$stopping" = 1 ] && exit 0
exit "$rc"
