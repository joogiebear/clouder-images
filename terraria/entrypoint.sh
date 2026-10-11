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

SERVER_PORT=$(num "${SERVER_PORT:-7777}" 7777)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-8}" 8)
WORLD_NAME=$(text "${WORLD_NAME:-World}" "World")
[ -n "$WORLD_NAME" ] || WORLD_NAME=World
WORLD_SIZE=$(pick "${WORLD_SIZE:-2}" 2 1 2 3)
DIFFICULTY=$(pick "${DIFFICULTY:-0}" 0 0 1 2 3)
SEED=$(text "${SEED:-}" "")
SERVER_PASSWORD=$(text "${SERVER_PASSWORD:-}" "")
MOTD=$(text "${MOTD:-Welcome!}" "Welcome!")
TERRARIA_VERSION=$(num "${TERRARIA_VERSION:-1458}" 1458)

export HOME=/data
cd /data
mkdir -p server worlds

dir=server/$TERRARIA_VERSION
bin=$dir/Linux/TerrariaServer.bin.x86_64
if [ ! -f "$bin" ]; then
  download() {
    rm -rf "$dir.tmp" && mkdir -p "$dir.tmp" \
      && curl -fsSL -o "$dir.tmp/server.zip" "https://terraria.org/api/download/pc-dedicated-server/terraria-server-$TERRARIA_VERSION.zip" \
      && unzip -q -o "$dir.tmp/server.zip" -d "$dir.tmp" \
      && rm -f "$dir.tmp/server.zip" \
      && rm -rf "$dir" && mv "$dir.tmp/$TERRARIA_VERSION" "$dir"
  }
  retry "downloading Terraria $TERRARIA_VERSION" download \
    || { echo "[clouder] could not download Terraria $TERRARIA_VERSION" >&2; rm -rf "$dir.tmp"; exit 1; }
  rm -rf "$dir.tmp"
fi
[ -f "$bin" ] || { echo "[clouder] TerrariaServer.bin.x86_64 is missing after install" >&2; exit 1; }
chmod +x "$bin"

cat >serverconfig.txt <<EOF
worldpath=/data/worlds
world=/data/worlds/$WORLD_NAME.wld
autocreate=$WORLD_SIZE
worldname=$WORLD_NAME
difficulty=$DIFFICULTY
maxplayers=$MAX_PLAYERS
port=$SERVER_PORT
password=$SERVER_PASSWORD
motd=$MOTD
seed=$SEED
secure=1
upnp=0
language=en-US
banlist=/data/banlist.txt
EOF

fifo=/data/.console
rm -f "$fifo"
mkfifo "$fifo"
exec 3<>"$fifo"

echo "[clouder] starting Terraria $TERRARIA_VERSION"
"$bin" -config /data/serverconfig.txt <&3 &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving the world"
  printf 'exit\n' >&3
  for _ in $(seq 1 100); do
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
