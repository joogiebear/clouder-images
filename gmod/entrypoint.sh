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
MAX_PLAYERS=$(num "${MAX_PLAYERS:-16}" 16)
TICKRATE=$(num "${TICKRATE:-66}" 66)
MAP=$(word "${MAP:-gm_construct}" gm_construct)
GAMEMODE=$(word "${GAMEMODE:-sandbox}" sandbox)
STEAM_BRANCH=$(word "${STEAM_BRANCH:-public}" public)
SERVER_PASSWORD=$(secret "${SERVER_PASSWORD:-}")
STEAM_TOKEN=$(secret "${STEAM_TOKEN:-}")
WORKSHOP_COLLECTION=$(num "${WORKSHOP_COLLECTION:-}" "")
WORKSHOP_AUTHKEY=$(secret "${WORKSHOP_AUTHKEY:-}")
[ -n "${SERVER_NAME:-}" ] || SERVER_NAME="Garry's Mod Server"
: "${UPDATE_ON_START:=1}"
: "${VALIDATE_ON_START:=0}"
: "${MOUNT_CSS:=1}"

export HOME=/data
cd /data
mkdir -p steamcmd server

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  local dir=$1 app=$2
  shift 2
  steamcmd/steamcmd.sh +force_install_dir "$dir" +login anonymous +app_update "$app" "$@" +quit
}

validate=()
if [ "$VALIDATE_ON_START" = "1" ]; then
  validate=(validate)
fi

bin=server/srcds_linux
if [ ! -x "$bin" ] || [ "$UPDATE_ON_START" = "1" ]; then
  retry "downloading or updating Garry's Mod" steam_update /data/server 4020 -beta "$STEAM_BRANCH" "${validate[@]}" \
    || { echo "[clouder] could not download the Garry's Mod server" >&2; exit 1; }
fi
[ -x "$bin" ] || { echo "[clouder] srcds_linux is missing after install" >&2; exit 1; }

cfg=server/garrysmod/cfg
mkdir -p "$cfg" "$HOME/.steam/sdk32"
ln -sf /data/steamcmd/linux32/steamclient.so "$HOME/.steam/sdk32/steamclient.so" 2>/dev/null || true
[ -f "$cfg/server.cfg" ] || echo "// Runs on every map load" >"$cfg/server.cfg"

if [ "$MOUNT_CSS" = "1" ]; then
  if [ ! -d css/cstrike ] || [ "$UPDATE_ON_START" = "1" ]; then
    retry "downloading Counter-Strike: Source content" steam_update /data/css 232330 \
      || echo "[clouder] could not download the Counter-Strike: Source content, maps that need it will show errors" >&2
  fi
  if [ -d css/cstrike ]; then
    printf '"mountcfg"\n{\n\t"cstrike"\t"/data/css/cstrike"\n}\n' >"$cfg/mount.cfg"
  fi
fi

args=(
  -game garrysmod -console -condebug -usercon -port "$SERVER_PORT" -tickrate "$TICKRATE"
  +ip 0.0.0.0 +maxplayers "$MAX_PLAYERS" +gamemode "$GAMEMODE" +map "$MAP"
  +hostname "\"$SERVER_NAME\"" +rcon_password "$RCON_PASSWORD" +sv_lan 0
)
[ -z "$SERVER_PASSWORD" ] || args+=(+sv_password "$SERVER_PASSWORD")
[ -z "$STEAM_TOKEN" ] || args+=(+sv_setsteamaccount "$STEAM_TOKEN")
if [ -n "$WORKSHOP_COLLECTION" ] && [ -n "$WORKSHOP_AUTHKEY" ]; then
  args+=(-authkey "$WORKSHOP_AUTHKEY" +host_workshop_collection "$WORKSHOP_COLLECTION")
fi

cd server
export LD_LIBRARY_PATH=".:bin:${LD_LIBRARY_PATH:-}"
log=garrysmod/console.log
: >"$log"
tail -n 0 -F "$log" &
logtail=$!
echo "[clouder] starting Garry's Mod"
./srcds_linux "${args[@]}" </dev/null &
game=$!
{
  until rcon "$SERVER_PORT" status >/dev/null 2>&1; do
    kill -0 "$game" 2>/dev/null || exit 0
    sleep 3
  done
  echo "[clouder] Garry's Mod is accepting connections"
} &
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, asking Garry's Mod to quit"
  console quit >/dev/null 2>&1 || kill -TERM "$game" 2>/dev/null || true
  { sleep 20; kill -TERM "$game" 2>/dev/null || true; } &
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
kill "$logtail" 2>/dev/null || true
[ "$stopping" = 1 ] && exit 0
exit "$rc"
