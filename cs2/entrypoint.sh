#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
word() { [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] && echo "$1" || echo "$2"; }
secret() { [[ "$1" =~ ^[A-Za-z0-9_.-]*$ ]] && echo "$1" || echo ""; }

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
SERVER_PORT=$(num "${SERVER_PORT:-27015}" 27015)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-10}" 10)
MAP=$(word "${MAP:-de_dust2}" de_dust2)
STEAM_BRANCH=$(word "${STEAM_BRANCH:-public}" public)
SERVER_PASSWORD=$(secret "${SERVER_PASSWORD:-}")
STEAM_TOKEN=$(secret "${STEAM_TOKEN:-}")
: "${SERVER_NAME:=Counter-Strike 2 Server}"
: "${UPDATE_ON_START:=1}"
: "${VALIDATE_ON_START:=0}"

case "${GAME_MODE:-competitive}" in
  casual) game_type=0 game_mode=0 ;;
  wingman) game_type=0 game_mode=2 ;;
  armsrace) game_type=1 game_mode=0 ;;
  demolition) game_type=1 game_mode=1 ;;
  deathmatch) game_type=1 game_mode=2 ;;
  *) game_type=0 game_mode=1 ;;
esac

export HOME=/data
cd /data
mkdir -p steamcmd server

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
    +app_update 730 -beta "$STEAM_BRANCH" "$@" +quit
}

bin_rel=game/bin/linuxsteamrt64/cs2
bin=server/$bin_rel
if [ ! -x "$bin" ] || [ "$UPDATE_ON_START" = "1" ]; then
  validate=()
  if [ "$VALIDATE_ON_START" = "1" ]; then
    validate=(validate)
  fi
  retry "downloading or updating Counter-Strike 2" steam_update "${validate[@]}" \
    || { echo "[clouder] could not download the Counter-Strike 2 server" >&2; exit 1; }
fi
[ -x "$bin" ] || { echo "[clouder] the cs2 binary is missing after install" >&2; exit 1; }

mkdir -p "$HOME/.steam/sdk64" server/game/csgo/cfg
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true
[ -f server/game/csgo/cfg/server.cfg ] || echo "// Runs on every map load" > server/game/csgo/cfg/server.cfg

args=(
  -dedicated -usercon -ip 0.0.0.0 -port "$SERVER_PORT" -maxplayers "$MAX_PLAYERS"
  +game_type "$game_type" +game_mode "$game_mode" +mapgroup mg_active +map "$MAP"
  +hostname "$SERVER_NAME" +rcon_password "$RCON_PASSWORD" +sv_lan 0
)
[ -z "$SERVER_PASSWORD" ] || args+=(+sv_password "$SERVER_PASSWORD")
[ -z "$STEAM_TOKEN" ] || args+=(+sv_setsteamaccount "$STEAM_TOKEN")

cd server
echo "[clouder] starting Counter-Strike 2"
"./$bin_rel" "${args[@]}" &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking Counter-Strike 2 to quit"
  console quit >/dev/null 2>&1 || kill -TERM "$game" 2>/dev/null || true
  { sleep 20; kill -TERM "$game" 2>/dev/null || true; } &
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
