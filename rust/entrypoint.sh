#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
word() { [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] && echo "$1" || echo "$2"; }

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
SERVER_PORT=$(num "${SERVER_PORT:-28015}" 28015)
QUERY_PORT=$(num "${QUERY_PORT:-28017}" 28017)
RCON_PORT=$(num "${RCON_PORT:-28016}" 28016)
APP_PORT=$(num "${APP_PORT:-28082}" 28082)
WORLD_SIZE=$(num "${WORLD_SIZE:-3000}" 3000)
SEED=$(num "${SEED:-12345}" 12345)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-50}" 50)
SAVE_INTERVAL=$(num "${SAVE_INTERVAL:-600}" 600)
IDENTITY=$(word "${IDENTITY:-clouder}" clouder)
STEAM_BRANCH=$(word "${STEAM_BRANCH:-public}" public)
CARBON_BUILD=$(word "${CARBON_BUILD:-production_build}" production_build)
OXIDE_BUILD=$(word "${OXIDE_BUILD:-latest}" latest)
: "${SERVER_NAME:=Rust Server}"
: "${SERVER_DESCRIPTION:=}"
: "${SERVER_URL:=}"
: "${LEVEL:=Procedural Map}"
: "${UPDATE_ON_START:=1}"
: "${RUST_PLUS:=false}"
: "${FRAMEWORK:=vanilla}"

case "$FRAMEWORK" in
  vanilla|carbon|oxide) ;;
  *) echo "[clouder] unknown FRAMEWORK '$FRAMEWORK' (use vanilla, carbon or oxide)" >&2; exit 1 ;;
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
    +app_update 258550 -beta "$STEAM_BRANCH" "$@" +quit
}

fetch_carbon() {
  local tmp
  tmp=$(mktemp /data/carbon-XXXXXX.tar.gz)
  if curl -fsSL -o "$tmp" "https://github.com/CarbonCommunity/Carbon/releases/download/${CARBON_BUILD}/Carbon.Linux.Release.tar.gz" \
      && tar -tzf "$tmp" >/dev/null 2>&1 \
      && tar -xzf "$tmp" -C /data/server; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

fetch_oxide() {
  local base="https://github.com/OxideMod/Oxide.Rust/releases" url tmp
  if [ "$OXIDE_BUILD" = "latest" ]; then
    url="$base/latest/download/Oxide.Rust-linux.zip"
  else
    url="$base/download/${OXIDE_BUILD}/Oxide.Rust-linux.zip"
  fi
  tmp=$(mktemp /data/oxide-XXXXXX.zip)
  if curl -fsSL -o "$tmp" "$url" && unzip -tq "$tmp" >/dev/null 2>&1; then
    # Recorded before the game files are overwritten, so an interrupted install is still known to be Oxide's.
    echo oxide > /data/.framework
    unzip -qo "$tmp" -d /data/server
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Oxide patches Assembly-CSharp.dll in place and SteamCMD does not notice files it did not write,
# so leaving Oxide needs a validate to put Valve's file back.
if [ "$(cat /data/.framework 2>/dev/null || true)" = "oxide" ] && [ "$FRAMEWORK" != "oxide" ] && [ -x server/RustDedicated ]; then
  echo "[clouder] leaving Oxide: restoring the vanilla game files"
  retry "validating Rust" steam_update validate || { echo "[clouder] could not validate the Rust server" >&2; exit 1; }
  rm -f server/RustDedicated_Data/Managed/Oxide.*
elif [ ! -x server/RustDedicated ] || [ "$UPDATE_ON_START" = "1" ]; then
  retry "downloading or updating Rust" steam_update || { echo "[clouder] could not download the Rust server" >&2; exit 1; }
fi
[ -x server/RustDedicated ] || { echo "[clouder] RustDedicated is missing after install" >&2; exit 1; }

if [ "$FRAMEWORK" = "carbon" ]; then
  if [ ! -f server/carbon/tools/environment.sh ] || [ "$UPDATE_ON_START" = "1" ]; then
    if ! retry "downloading Carbon" fetch_carbon; then
      [ -f server/carbon/tools/environment.sh ] || { echo "[clouder] could not download Carbon" >&2; exit 1; }
      echo "[clouder] could not update Carbon; using the installed copy" >&2
    fi
  fi
fi

if [ "$FRAMEWORK" = "oxide" ]; then
  # A game update restores Valve's Assembly-CSharp.dll, so Oxide is reinstalled after every update.
  if [ ! -f server/RustDedicated_Data/Managed/Oxide.Core.dll ] || [ "$UPDATE_ON_START" = "1" ]; then
    if retry "downloading Oxide" fetch_oxide; then
      tag=$OXIDE_BUILD
      if [ "$tag" = "latest" ]; then
        tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/OxideMod/Oxide.Rust/releases/latest | sed 's|.*/||' || true)
      fi
      echo "[clouder] Oxide ${tag:-latest} installed"
    else
      [ -f server/RustDedicated_Data/Managed/Oxide.Core.dll ] || { echo "[clouder] could not download Oxide" >&2; exit 1; }
      echo "[clouder] could not update Oxide; using the installed copy" >&2
    fi
  fi
fi
echo "$FRAMEWORK" > /data/.framework

# The game aborts at startup when Rust+ cannot reach its own public address, so it stays off unless enabled.
app_port=-1
if [ "$RUST_PLUS" = "true" ]; then
  app_port=$APP_PORT
fi

cd server
export LD_LIBRARY_PATH="$PWD/RustDedicated_Data/Plugins/x86_64:${LD_LIBRARY_PATH:-}"

if [ "$FRAMEWORK" = "carbon" ]; then
  echo "[clouder] Carbon is on"
  # shellcheck disable=SC1091
  source carbon/tools/environment.sh
fi

if [ "$FRAMEWORK" = "oxide" ]; then
  echo "[clouder] Oxide is on"
fi

# See keepstdin.c. A container started without stdin gets /dev/null so descriptor 0 is still taken.
[ -e /proc/self/fd/0 ] || exec 0</dev/null
export LD_PRELOAD="/usr/local/lib/keepstdin.so${LD_PRELOAD:+:$LD_PRELOAD}"

echo "[clouder] starting Rust"
exec ./RustDedicated -batchmode -nographics \
  +server.identity "$IDENTITY" \
  +server.port "$SERVER_PORT" \
  +server.queryport "$QUERY_PORT" \
  +rcon.port "$RCON_PORT" +rcon.web 1 +rcon.password "$RCON_PASSWORD" \
  +app.port "$app_port" \
  +server.hostname "$SERVER_NAME" \
  +server.description "$SERVER_DESCRIPTION" \
  +server.url "$SERVER_URL" \
  +server.level "$LEVEL" \
  +server.worldsize "$WORLD_SIZE" \
  +server.seed "$SEED" \
  +server.maxplayers "$MAX_PLAYERS" \
  +server.saveinterval "$SAVE_INTERVAL"
