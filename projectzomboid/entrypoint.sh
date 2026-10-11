#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
text() {
  local re='^[A-Za-z0-9 _.,!#()-]*$'
  [[ "$1" =~ $re ]] && echo "$1" || echo "$2"
}
ident() {
  local re='^[A-Za-z0-9_-]{1,40}$'
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

SERVER_PORT=$(num "${SERVER_PORT:-16261}" 16261)
UDP_PORT=$(num "${UDP_PORT:-16262}" 16262)
STEAM_PORT1=$(num "${STEAM_PORT1:-8766}" 8766)
STEAM_PORT2=$(num "${STEAM_PORT2:-8767}" 8767)
SERVER_NAME=$(ident "${SERVER_NAME:-servertest}" servertest)
PUBLIC_NAME=$(text "${PUBLIC_NAME:-Project Zomboid Server}" "Project Zomboid Server")
SERVER_PASSWORD=$(text "${SERVER_PASSWORD:-}" "")
ADMIN_PASSWORD=$(text "${ADMIN_PASSWORD:-}" "")
MAX_PLAYERS=$(num "${MAX_PLAYERS:-16}" 16)
PUBLIC=$(pick "${PUBLIC:-false}" false true false)
PVP=$(pick "${PVP:-true}" true true false)
XMX=${XMX:-}
[[ "$XMX" =~ ^[0-9]+[mMgG]$ ]] || XMX=4g
case "${STEAM_BRANCH:-public}" in unstable | legacy41) branch=$STEAM_BRANCH ;; *) branch=public ;; esac
: "${UPDATE_ON_START:=1}"

export HOME=/data
cd /data
mkdir -p steamcmd server Zomboid/Server

if [ -z "$ADMIN_PASSWORD" ]; then
  if [ ! -s .admin-password ]; then
    (umask 077 && head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' >.admin-password)
  fi
  ADMIN_PASSWORD=$(cat .admin-password)
  echo "[clouder] no ADMIN_PASSWORD set, the admin account password is $ADMIN_PASSWORD (kept in /data/.admin-password)"
fi

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
    +app_update 380870 -beta "$branch" +quit
}

if [ ! -x server/start-server.sh ] || [ "$UPDATE_ON_START" = "1" ]; then
  retry "downloading or updating Project Zomboid, branch $branch" steam_update \
    || { echo "[clouder] could not download the Project Zomboid server" >&2; exit 1; }
fi
[ -f server/start-server.sh ] || { echo "[clouder] start-server.sh is missing after install" >&2; exit 1; }
chmod +x server/start-server.sh server/ProjectZomboid64 2>/dev/null || true

mkdir -p "$HOME/.steam/sdk64"
ln -sf /data/steamcmd/linux64/steamclient.so "$HOME/.steam/sdk64/steamclient.so" 2>/dev/null || true

vmargs=server/ProjectZomboid64.json
if [ -f "$vmargs" ]; then
  sed -i -E "s~-Xmx[0-9]+[mMgG]~-Xmx$XMX~" "$vmargs"
fi

ini=Zomboid/Server/$SERVER_NAME.ini
touch "$ini"
set_ini() {
  if grep -q "^$1=" "$ini"; then
    sed -i "s~^$1=.*~$1=$2~" "$ini"
  else
    printf '%s=%s\n' "$1" "$2" >>"$ini"
  fi
}
set_ini PublicName "$PUBLIC_NAME"
set_ini Public "$PUBLIC"
set_ini Password "$SERVER_PASSWORD"
set_ini MaxPlayers "$MAX_PLAYERS"
set_ini PVP "$PVP"
set_ini DefaultPort "$SERVER_PORT"
set_ini UDPPort "$UDP_PORT"
set_ini SteamPort1 "$STEAM_PORT1"
set_ini SteamPort2 "$STEAM_PORT2"

fifo=/data/.console
rm -f "$fifo"
mkfifo "$fifo"
exec 3<>"$fifo"

cd server
echo "[clouder] starting Project Zomboid"
./start-server.sh -cachedir=/data/Zomboid -servername "$SERVER_NAME" -adminpassword "$ADMIN_PASSWORD" \
  -port "$SERVER_PORT" -udpport "$UDP_PORT" -steamvac true <&3 &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving the world"
  printf 'quit\n' >&3
  for _ in $(seq 1 150); do
    kill -0 "$game" 2>/dev/null || return 0
    sleep 1
  done
  kill -TERM "$game" 2>/dev/null || true
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
