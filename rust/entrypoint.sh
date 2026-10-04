#!/usr/bin/env bash
# Installs or updates the Rust dedicated server with SteamCMD, then runs it.
# Everything is configured through environment variables; the panel sets them.
set -euo pipefail

: "${SERVER_PORT:=28015}"
: "${QUERY_PORT:=28017}"
: "${RCON_PORT:=28016}"
: "${APP_PORT:=28082}"
: "${RCON_PASSWORD:?RCON_PASSWORD must be set}"
: "${IDENTITY:=clouder}"
: "${SERVER_NAME:=Rust Server}"
: "${SERVER_DESCRIPTION:=}"
: "${SERVER_URL:=}"
: "${LEVEL:=Procedural Map}"
: "${WORLD_SIZE:=3000}"
: "${SEED:=12345}"
: "${MAX_PLAYERS:=50}"
: "${SAVE_INTERVAL:=600}"
: "${UPDATE_ON_START:=1}"
: "${STEAM_BRANCH:=public}"
: "${RUST_PLUS:=false}"
# vanilla runs the game as Valve ships it. carbon adds the Carbon plugin framework
# (https://github.com/CarbonCommunity/Carbon), which loads .cs plugins from server/carbon/plugins.
: "${FRAMEWORK:=vanilla}"
# Carbon publishes one build per Rust branch; production_build matches the public branch.
: "${CARBON_BUILD:=production_build}"

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
    echo "[clouder] downloading or updating Rust (attempt $attempt)"
    if steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
        +app_update 258550 -beta "$STEAM_BRANCH" +quit; then
      return 0
    fi
    sleep 5
  done
  return 1
}

if [ ! -x server/RustDedicated ] || [ "$UPDATE_ON_START" = "1" ]; then
  install_game || { echo "[clouder] could not download the Rust server" >&2; exit 1; }
fi
[ -x server/RustDedicated ] || { echo "[clouder] RustDedicated is missing after install" >&2; exit 1; }

install_carbon() {
  local url="https://github.com/CarbonCommunity/Carbon/releases/download/${CARBON_BUILD}/Carbon.Linux.Release.tar.gz"
  local tmp
  tmp=$(mktemp /data/carbon-XXXXXX.tar.gz)
  for attempt in 1 2 3; do
    echo "[clouder] downloading Carbon (attempt $attempt)"
    # Download to a file first, so a failed download never leaves half a framework behind.
    if curl -fsSL -o "$tmp" "$url" && tar -tzf "$tmp" >/dev/null 2>&1; then
      tar -xzf "$tmp" -C /data/server
      rm -f "$tmp"
      return 0
    fi
    sleep 5
  done
  rm -f "$tmp"
  return 1
}

if [ "$FRAMEWORK" = "carbon" ]; then
  if [ ! -f server/carbon/tools/environment.sh ] || [ "$UPDATE_ON_START" = "1" ]; then
    if ! install_carbon; then
      # An installed copy is better than none, but a server that never had Carbon cannot start with it.
      [ -f server/carbon/tools/environment.sh ] || { echo "[clouder] could not download Carbon" >&2; exit 1; }
      echo "[clouder] could not update Carbon; using the installed copy" >&2
    fi
  fi
fi

# Rust+ makes the server test a connection to its own public address. Behind a router that
# does not allow that, the game runtime aborts, so Rust+ is off unless explicitly enabled.
if [ "$RUST_PLUS" = "true" ]; then
  APP_ARG=("$APP_PORT")
else
  APP_ARG=(-1)
fi

cd server
export LD_LIBRARY_PATH="$PWD/RustDedicated_Data/Plugins/x86_64:${LD_LIBRARY_PATH:-}"

if [ "$FRAMEWORK" = "carbon" ]; then
  echo "[clouder] Carbon is on"
  # shellcheck disable=SC1091
  source carbon/tools/environment.sh
fi

echo "[clouder] starting Rust"
exec ./RustDedicated -batchmode -nographics \
  +server.identity "$IDENTITY" \
  +server.port "$SERVER_PORT" \
  +server.queryport "$QUERY_PORT" \
  +rcon.port "$RCON_PORT" +rcon.web 1 +rcon.password "$RCON_PASSWORD" \
  +app.port "${APP_ARG[0]}" \
  +server.hostname "$SERVER_NAME" \
  +server.description "$SERVER_DESCRIPTION" \
  +server.url "$SERVER_URL" \
  +server.level "$LEVEL" \
  +server.worldsize "$WORLD_SIZE" \
  +server.seed "$SEED" \
  +server.maxplayers "$MAX_PLAYERS" \
  +server.saveinterval "$SAVE_INTERVAL"
