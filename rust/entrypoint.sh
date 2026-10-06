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
# oxide adds the uMod Oxide framework (https://github.com/OxideMod/Oxide.Rust), which loads .cs
# plugins from server/oxide/plugins.
: "${FRAMEWORK:=vanilla}"
# Carbon publishes one build per Rust branch; production_build matches the public branch.
: "${CARBON_BUILD:=production_build}"
# Oxide release tag, or "latest" for the newest release.
: "${OXIDE_BUILD:=latest}"

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

install_game() {
  # An optional first argument "validate" makes SteamCMD check every file and restore the ones
  # that differ from Valve's copy.
  local validate=()
  [ "${1:-}" = "validate" ] && validate=(validate)
  # SteamCMD fails now and then for network reasons, so retry a few times.
  for attempt in 1 2 3; do
    echo "[clouder] downloading or updating Rust (attempt $attempt)"
    if steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous \
        +app_update 258550 -beta "$STEAM_BRANCH" "${validate[@]}" +quit; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# Oxide patches the game's own Assembly-CSharp.dll on disk, and a plain SteamCMD update does not
# notice a file it did not change itself. So when a server leaves Oxide, the game is validated
# once to put Valve's files back. /data/.framework remembers which framework the files are for.
PREV_FRAMEWORK=$(cat /data/.framework 2>/dev/null || true)
FORCE_VALIDATE=0
if [ "$PREV_FRAMEWORK" = "oxide" ] && [ "$FRAMEWORK" != "oxide" ] && [ -x server/RustDedicated ]; then
  echo "[clouder] leaving Oxide: validating the game files to restore the vanilla ones"
  FORCE_VALIDATE=1
fi

if [ "$FORCE_VALIDATE" = "1" ]; then
  install_game validate || { echo "[clouder] could not validate the Rust server" >&2; exit 1; }
  # The Oxide libraries are not part of the game; remove them so nothing can load them.
  rm -f server/RustDedicated_Data/Managed/Oxide.*
elif [ ! -x server/RustDedicated ] || [ "$UPDATE_ON_START" = "1" ]; then
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

install_oxide() {
  local base="https://github.com/OxideMod/Oxide.Rust/releases"
  local url
  if [ "$OXIDE_BUILD" = "latest" ]; then
    url="$base/latest/download/Oxide.Rust-linux.zip"
  else
    url="$base/download/${OXIDE_BUILD}/Oxide.Rust-linux.zip"
  fi
  local tmp
  tmp=$(mktemp /data/oxide-XXXXXX.zip)
  for attempt in 1 2 3; do
    echo "[clouder] downloading Oxide (attempt $attempt)"
    # Download to a file first, so a failed download never leaves half a framework behind.
    # The zip holds RustDedicated_Data/Managed/..., so it extracts straight over the server folder.
    if curl -fsSL -o "$tmp" "$url" && unzip -tq "$tmp" >/dev/null 2>&1; then
      # Record Oxide before touching the game files: if this is cut short, the next start
      # still knows the files may be patched.
      echo oxide > /data/.framework
      unzip -qo "$tmp" -d /data/server
      rm -f "$tmp"
      return 0
    fi
    sleep 5
  done
  rm -f "$tmp"
  return 1
}

if [ "$FRAMEWORK" = "oxide" ]; then
  # Oxide.Core.dll is the marker of an installed Oxide. A game update restores Valve's
  # Assembly-CSharp.dll, so Oxide is put back after every update, not only on first install.
  if [ ! -f server/RustDedicated_Data/Managed/Oxide.Core.dll ] || [ "$UPDATE_ON_START" = "1" ]; then
    if ! install_oxide; then
      [ -f server/RustDedicated_Data/Managed/Oxide.Core.dll ] || { echo "[clouder] could not download Oxide" >&2; exit 1; }
      echo "[clouder] could not update Oxide; using the installed copy" >&2
    fi
  fi
fi
echo "$FRAMEWORK" > /data/.framework

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

if [ "$FRAMEWORK" = "oxide" ]; then
  echo "[clouder] Oxide is on"
fi

# The game's Epic Online Services library closes file descriptor 0, after which Mono hands
# that number to the next file or socket it opens and aborts ("duplicate File fd 0"). Carbon and
# Rust+ both trigger it. keepstdin.so makes close(0) do nothing; see keepstdin.c. If Docker
# started the container with no stdin at all, give it /dev/null so descriptor 0 is taken.
[ -e /proc/self/fd/0 ] || exec 0</dev/null
export LD_PRELOAD="/usr/local/lib/keepstdin.so${LD_PRELOAD:+:$LD_PRELOAD}"

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
