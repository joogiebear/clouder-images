#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
text() {
  local re='^[A-Za-z0-9 _.!#()-]*$'
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

SERVER_PORT=$(num "${SERVER_PORT:-42420}" 42420)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-16}" 16)
SERVER_NAME=$(text "${SERVER_NAME:-Vintage Story Server}" "Vintage Story Server")
SERVER_DESCRIPTION=$(text "${SERVER_DESCRIPTION:-}" "")
SERVER_PASSWORD=$(text "${SERVER_PASSWORD:-}" "")
WORLD_SEED=$(text "${WORLD_SEED:-}" "")
ADVERTISE=$(pick "${ADVERTISE:-false}" false true false)
WHITELIST=$(pick "${WHITELIST:-false}" false true false)
ALLOW_PVP=$(pick "${ALLOW_PVP:-true}" true true false)
PASS_TIME_WHEN_EMPTY=$(pick "${PASS_TIME_WHEN_EMPTY:-false}" false true false)
VS_VERSION=${VS_VERSION:-latest}
re='^(latest|[0-9]+\.[0-9]+\.[0-9]+)$'
[[ "$VS_VERSION" =~ $re ]] || VS_VERSION=latest

export HOME=/data
cd /data
mkdir -p data
dir=/data/server
installed=$(cat "$dir/.version" 2>/dev/null || echo none)

if [ "$VS_VERSION" = latest ]; then
  want=$(curl -fsSL https://api.vintagestory.at/lateststable.txt | tr -d '[:space:]' || true)
  if ! [[ "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    [ -f "$dir/VintagestoryServer.dll" ] || { echo "[clouder] could not look up the current Vintage Story version" >&2; exit 1; }
    echo "[clouder] the version lookup failed, starting the installed server"
    want=$installed
  fi
else
  want=$VS_VERSION
fi

install() {
  rm -rf "$dir.tmp" && mkdir -p "$dir.tmp" \
    && curl -fsSL "https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_$want.tar.gz" | tar -xz -C "$dir.tmp" \
    && [ -f "$dir.tmp/VintagestoryServer.dll" ] \
    && rm -rf "$dir" && mv "$dir.tmp" "$dir"
}

if [ ! -f "$dir/VintagestoryServer.dll" ] || [ "$installed" != "$want" ]; then
  retry "downloading Vintage Story $want" install \
    || { echo "[clouder] could not download Vintage Story $want" >&2; rm -rf "$dir.tmp"; exit 1; }
  echo "$want" >"$dir/.version"
fi

setconfig=$(jq -nc --arg name "$SERVER_NAME" --arg desc "$SERVER_DESCRIPTION" \
  --arg pass "$SERVER_PASSWORD" --arg seed "$WORLD_SEED" \
  --argjson port "$SERVER_PORT" --argjson max "$MAX_PLAYERS" --argjson advertise "$ADVERTISE" \
  --argjson whitelist "$([ "$WHITELIST" = true ] && echo 1 || echo 0)" \
  --argjson pvp "$ALLOW_PVP" --argjson pass_time "$PASS_TIME_WHEN_EMPTY" '
  {
    ServerName: $name,
    ServerDescription: $desc,
    Password: (if $pass == "" then null else $pass end),
    Port: $port,
    MaxClients: $max,
    AdvertiseServer: $advertise,
    WhitelistMode: $whitelist,
    AllowPvP: $pvp,
    PassTimeWhenEmpty: $pass_time
  } + (if $seed == "" then {} else {WorldConfig: {Seed: $seed}} end)')

cd "$dir"
# --setconfig writes the settings and exits, so it runs before the server proper
dotnet VintagestoryServer.dll --dataPath /data/data --setconfig "$setconfig" >/dev/null 2>&1 || true

fifo=/data/.console
rm -f "$fifo"
mkfifo "$fifo"
exec 3<>"$fifo"

echo "[clouder] starting Vintage Story $want"
dotnet VintagestoryServer.dll --dataPath /data/data <&3 &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving the world"
  printf '/stop\n' >&3
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
