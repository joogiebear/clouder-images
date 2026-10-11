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

SERVER_PORT=$(num "${SERVER_PORT:-19132}" 19132)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-10}" 10)
VIEW_DISTANCE=$(num "${VIEW_DISTANCE:-32}" 32)
SERVER_NAME=$(text "${SERVER_NAME:-Bedrock Server}" "Bedrock Server")
LEVEL_NAME=$(text "${LEVEL_NAME:-Bedrock level}" "Bedrock level")
LEVEL_SEED=$(text "${LEVEL_SEED:-}" "")
GAMEMODE=$(pick "${GAMEMODE:-survival}" survival survival creative adventure)
DIFFICULTY=$(pick "${DIFFICULTY:-easy}" easy peaceful easy normal hard)
ALLOW_CHEATS=$(pick "${ALLOW_CHEATS:-false}" false true false)
ONLINE_MODE=$(pick "${ONLINE_MODE:-true}" true true false)
ALLOW_LIST=$(pick "${ALLOW_LIST:-false}" false true false)
BEDROCK_VERSION=${BEDROCK_VERSION:-latest}
re='^(latest|[0-9]+(\.[0-9]+){2,3})$'
[[ "$BEDROCK_VERSION" =~ $re ]] || BEDROCK_VERSION=latest

export HOME=/data
cd /data
mkdir -p server
dir=/data/server
bin=$dir/bedrock_server

resolve_latest() {
  curl -fsSL https://net-secondary.web.minecraft-services.net/api/v1.0/download/links \
    | grep -o 'https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-[0-9.]*\.zip' | head -n 1
}

install() {
  local url=$1 zip=$dir/.server.zip
  rm -f "$zip" \
    && curl -fsSL -A "Mozilla/5.0" -o "$zip" "$url" \
    && unzip -q -o "$zip" -x server.properties allowlist.json permissions.json 'worlds/*' -d "$dir" \
    && { [ -f "$dir/server.properties" ] || unzip -q -o "$zip" server.properties -d "$dir"; } \
    && rm -f "$zip"
}

installed=$(cat "$dir/.version" 2>/dev/null || echo none)
if [ "$BEDROCK_VERSION" = latest ]; then
  url=$(resolve_latest || true)
  if [ -n "$url" ]; then
    want=$(basename "$url" .zip)
    want=${want#bedrock-server-}
  elif [ -x "$bin" ]; then
    echo "[clouder] the version lookup failed, starting the installed server"
    want=$installed
  else
    echo "[clouder] could not look up the current Bedrock server version" >&2
    exit 1
  fi
else
  want=$BEDROCK_VERSION
  url=https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-$want.zip
fi

if [ ! -x "$bin" ] || [ "$installed" != "$want" ]; then
  retry "downloading Bedrock server $want" install "$url" \
    || { echo "[clouder] could not download Bedrock server $want" >&2; rm -f "$dir/.server.zip"; exit 1; }
  echo "$want" >"$dir/.version"
fi
[ -f "$bin" ] || { echo "[clouder] bedrock_server is missing after install" >&2; exit 1; }
chmod +x "$bin"

props=$dir/server.properties
[ -f "$props" ] || : >"$props"
setprop() {
  local tmp=$props.tmp
  awk -v k="$1" -v v="$2" 'BEGIN { done = 0 }
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' "$props" >"$tmp"
  mv "$tmp" "$props"
}
setprop server-name "$SERVER_NAME"
setprop level-name "$LEVEL_NAME"
setprop level-seed "$LEVEL_SEED"
setprop gamemode "$GAMEMODE"
setprop difficulty "$DIFFICULTY"
setprop allow-cheats "$ALLOW_CHEATS"
setprop max-players "$MAX_PLAYERS"
setprop view-distance "$VIEW_DISTANCE"
setprop online-mode "$ONLINE_MODE"
setprop allow-list "$ALLOW_LIST"
setprop server-port "$SERVER_PORT"
setprop server-portv6 "$((SERVER_PORT + 1))"
setprop transport raknet

fifo=/data/.console
rm -f "$fifo"
mkfifo "$fifo"
exec 3<>"$fifo"

cd "$dir"
export LD_LIBRARY_PATH=.
echo "[clouder] starting Bedrock server $want"
"$bin" <&3 &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving the world"
  printf 'stop\n' >&3
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
