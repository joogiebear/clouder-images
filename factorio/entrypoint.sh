#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
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
SERVER_PORT=$(num "${SERVER_PORT:-34197}" 34197)
RCON_PORT=$(num "${RCON_PORT:-27015}" 27015)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-0}" 0)
AUTOSAVE_INTERVAL=$(num "${AUTOSAVE_INTERVAL:-10}" 10)
VISIBILITY=$(choice "${VISIBILITY:-lan}" lan lan public)
AUTO_PAUSE=$(choice "${AUTO_PAUSE:-true}" true true false)
ALLOW_COMMANDS=$(choice "${ALLOW_COMMANDS:-admins-only}" admins-only true false admins-only)
FACTORIO_VERSION=${FACTORIO_VERSION:-stable}
[[ "$FACTORIO_VERSION" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+)$ ]] || FACTORIO_VERSION=stable
: "${SERVER_NAME:=Factorio Server}"
: "${SERVER_DESCRIPTION:=}"
: "${GAME_PASSWORD:=}"
: "${FACTORIO_USERNAME:=}"
: "${FACTORIO_TOKEN:=}"
: "${UPDATE_ON_START:=1}"

export HOME=/data
cd /data
mkdir -p saves mods config

installed=$(cat server/.version 2>/dev/null || true)
fetch_server() {
  local version=$FACTORIO_VERSION url tmp=/data/server.tmp
  url="https://factorio.com/get-download/$version/headless/linux64"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    version=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$url" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | tail -1)
    [ -n "$version" ] || return 1
  fi
  if [ "$version" = "$installed" ] && [ -x server/bin/x64/factorio ]; then
    echo "[clouder] Factorio $version is already installed"
    return 0
  fi
  rm -rf "$tmp"
  mkdir -p "$tmp"
  if curl -fsSL "$url" | tar -xJ -C "$tmp" --strip-components=1 && [ -x "$tmp/bin/x64/factorio" ]; then
    echo "$version" >"$tmp/.version"
    rm -rf server
    mv "$tmp" server
    echo "[clouder] Factorio $version installed"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

if [ ! -x server/bin/x64/factorio ] || [ "$UPDATE_ON_START" = "1" ]; then
  if ! retry "downloading Factorio $FACTORIO_VERSION" fetch_server; then
    [ -x server/bin/x64/factorio ] || { echo "[clouder] could not download the Factorio server" >&2; exit 1; }
    echo "[clouder] could not update Factorio; using the installed copy" >&2
  fi
fi
[ -x server/bin/x64/factorio ] || { echo "[clouder] the factorio binary is missing after install" >&2; exit 1; }

printf '[path]\nread-data=/data/server/data\nwrite-data=/data\n' >config/config.ini
factorio=(server/bin/x64/factorio --config /data/config/config.ini)

[ -f config/server-adminlist.json ] || echo '[]' >config/server-adminlist.json
[ -f config/server-settings.json ] || cp server/data/server-settings.example.json config/server-settings.json
settings=$(mktemp /data/settings-XXXXXX.json)
jq --arg name "$SERVER_NAME" --arg description "$SERVER_DESCRIPTION" --arg password "$GAME_PASSWORD" \
   --arg username "$FACTORIO_USERNAME" --arg token "$FACTORIO_TOKEN" --arg visibility "$VISIBILITY" \
   --arg commands "$ALLOW_COMMANDS" --argjson players "$MAX_PLAYERS" --argjson autosave "$AUTOSAVE_INTERVAL" \
   --argjson pause "$AUTO_PAUSE" \
   '.name = $name | .description = $description | .game_password = $password | .username = $username
    | .token = $token | .max_players = $players | .autosave_interval = $autosave | .auto_pause = $pause
    | .allow_commands = $commands | .visibility = {public: ($visibility == "public"), lan: true}' \
   config/server-settings.json >"$settings"
mv "$settings" config/server-settings.json

if ! compgen -G "saves/*.zip" >/dev/null; then
  echo "[clouder] creating a new map"
  "${factorio[@]}" --create saves/world.zip
fi

args=(
  --start-server-load-latest --server-settings config/server-settings.json
  --server-adminlist config/server-adminlist.json --mod-directory mods
  --port "$SERVER_PORT" --rcon-bind "127.0.0.1:$RCON_PORT" --rcon-password "$RCON_PASSWORD"
)

echo "[clouder] starting Factorio"
"${factorio[@]}" "${args[@]}" &
game=$!
stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving and shutting down Factorio"
  console /save >/dev/null 2>&1 || true
  kill -TERM "$game" 2>/dev/null || true
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ "$stopping" = 1 ] && exit 0
exit "$rc"
