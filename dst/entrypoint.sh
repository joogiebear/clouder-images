#!/usr/bin/env bash
set -euo pipefail

num() { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo "$2"; }
word() { [[ "$1" =~ ^[A-Za-z0-9_-][A-Za-z0-9_.-]*$ ]] && echo "$1" || echo "$2"; }
text() {
  local re='^[A-Za-z0-9 _.,!#()-]*$'
  [[ "$1" =~ $re ]] && echo "$1" || echo "$2"
}
secret() { [[ "$1" =~ ^[A-Za-z0-9_.-]*$ ]] && echo "$1" || echo ""; }
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

SERVER_PORT=$(num "${SERVER_PORT:-10999}" 10999)
MAX_PLAYERS=$(num "${MAX_PLAYERS:-6}" 6)
SERVER_NAME=$(text "${SERVER_NAME:-Dont Starve Together Server}" "Dont Starve Together Server")
SERVER_DESCRIPTION=$(text "${SERVER_DESCRIPTION:-}" "")
SERVER_PASSWORD=$(secret "${SERVER_PASSWORD:-}")
GAME_MODE=$(pick "${GAME_MODE:-survival}" survival survival endless wilderness)
PVP=$(pick "${PVP:-false}" false true false)
PAUSE_WHEN_EMPTY=$(pick "${PAUSE_WHEN_EMPTY:-true}" true true false)
ENABLE_CAVES=$(pick "${ENABLE_CAVES:-false}" false true false)
OFFLINE_CLUSTER=$(pick "${OFFLINE_CLUSTER:-false}" false true false)
CLUSTER_KEY=$(secret "${CLUSTER_KEY:-clouder}")
CLUSTER_TOKEN=${CLUSTER_TOKEN:-}
re='^[A-Za-z0-9_=^+/.-]*$'
[[ "$CLUSTER_TOKEN" =~ $re ]] || CLUSTER_TOKEN=
WORKSHOP_MODS=${WORKSHOP_MODS:-}
re='^[0-9]+(,[0-9]+)*$'
[[ "$WORKSHOP_MODS" =~ $re ]] || WORKSHOP_MODS=
: "${UPDATE_ON_START:=1}"
: "${VALIDATE_ON_START:=0}"

if [ -z "$CLUSTER_TOKEN" ] && [ "$OFFLINE_CLUSTER" != true ]; then
  echo "[clouder] CLUSTER_TOKEN must be set: create a server token at accounts.klei.com under Games, Don't Starve Together, Game Servers" >&2
  exit 1
fi

export HOME=/data
cd /data
mkdir -p steamcmd server

if [ ! -x steamcmd/steamcmd.sh ]; then
  echo "[clouder] downloading SteamCMD from Valve"
  curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi

steam_update() {
  steamcmd/steamcmd.sh +force_install_dir /data/server +login anonymous +app_update 343050 "$@" +quit
}

bin_rel=bin64/dontstarve_dedicated_server_nullrenderer_x64
binpath=server/$bin_rel
if [ ! -x "$binpath" ] || [ "$UPDATE_ON_START" = "1" ]; then
  validate=()
  if [ "$VALIDATE_ON_START" = "1" ]; then
    validate=(validate)
  fi
  retry "downloading or updating Don't Starve Together" steam_update "${validate[@]}" \
    || { echo "[clouder] could not download the Don't Starve Together server" >&2; exit 1; }
fi
[ -x "$binpath" ] || { echo "[clouder] the Don't Starve Together binary is missing after install" >&2; exit 1; }

if [ -d server/bin64/lib64 ] && [ -f steamcmd/linux64/steamclient.so ]; then
  ln -sf /data/steamcmd/linux64/steamclient.so server/bin64/lib64/steamclient.so
fi

cluster=/data/DoNotStarveTogether/Cluster
mkdir -p "$cluster/Master"
printf '%s' "$CLUSTER_TOKEN" >"$cluster/cluster_token.txt"

cat >"$cluster/cluster.ini" <<EOF
[GAMEPLAY]
game_mode = $GAME_MODE
max_players = $MAX_PLAYERS
pvp = $PVP
pause_when_empty = $PAUSE_WHEN_EMPTY

[NETWORK]
cluster_name = $SERVER_NAME
cluster_description = $SERVER_DESCRIPTION
cluster_password = $SERVER_PASSWORD
cluster_intention = cooperative
offline_cluster = $OFFLINE_CLUSTER
lan_only_cluster = false

[MISC]
console_enabled = true

[SHARD]
shard_enabled = $ENABLE_CAVES
bind_ip = 127.0.0.1
master_ip = 127.0.0.1
master_port = 10998
cluster_key = $CLUSTER_KEY
EOF

cat >"$cluster/Master/server.ini" <<EOF
[NETWORK]
server_port = $SERVER_PORT

[SHARD]
is_master = true
name = Master

[STEAM]
master_server_port = 27018
authentication_port = 8768

[ACCOUNT]
encode_user_path = true
EOF

if [ "$ENABLE_CAVES" = true ]; then
  mkdir -p "$cluster/Caves"
  cat >"$cluster/Caves/server.ini" <<EOF
[NETWORK]
server_port = 11000

[SHARD]
is_master = false
name = Caves

[STEAM]
master_server_port = 27019
authentication_port = 8769

[ACCOUNT]
encode_user_path = true
EOF
  printf 'return {\n  override_enabled = true,\n  preset = "DST_CAVE",\n}\n' >"$cluster/Caves/worldgenoverride.lua"
fi

mkdir -p server/mods
: >server/mods/dedicated_server_mods_setup.lua
if [ -n "$WORKSHOP_MODS" ]; then
  overrides='return {'
  IFS=',' read -ra mods <<<"$WORKSHOP_MODS"
  for id in "${mods[@]}"; do
    echo "ServerModSetup(\"$id\")" >>server/mods/dedicated_server_mods_setup.lua
    overrides+=$'\n'"  [\"workshop-$id\"] = { enabled = true },"
  done
  overrides+=$'\n}'
  printf '%s\n' "$overrides" >"$cluster/Master/modoverrides.lua"
  [ "$ENABLE_CAVES" != true ] || printf '%s\n' "$overrides" >"$cluster/Caves/modoverrides.lua"
fi

cd server/bin64
bin=./dontstarve_dedicated_server_nullrenderer_x64
game_args=(-console -persistent_storage_root /data -conf_dir DoNotStarveTogether -cluster Cluster)

fifo=/data/.console
rm -f "$fifo"
mkfifo "$fifo"
exec 3<>"$fifo"

echo "[clouder] starting Don't Starve Together"
"$bin" "${game_args[@]}" -shard Master <&3 &
game=$!
caves=
if [ "$ENABLE_CAVES" = true ]; then
  rm -f /data/.console-caves
  mkfifo /data/.console-caves
  exec 4<>/data/.console-caves
  "$bin" "${game_args[@]}" -shard Caves <&4 &
  caves=$!
fi

alive() {
  kill -0 "$game" 2>/dev/null && return 0
  [ -n "$caves" ] && kill -0 "$caves" 2>/dev/null
}

stopping=0
stop() {
  stopping=1
  echo "[clouder] stop requested, saving the world"
  printf 'c_shutdown(true)\n' >&3
  [ -z "$caves" ] || printf 'c_shutdown(true)\n' >&4
  for _ in $(seq 1 100); do
    alive || return 0
    sleep 1
  done
  kill -TERM "$game" ${caves:+"$caves"} 2>/dev/null || true
}
trap stop TERM INT

rc=0
while kill -0 "$game" 2>/dev/null; do
  wait "$game" || rc=$?
done
[ -z "$caves" ] || kill -TERM "$caves" 2>/dev/null || true
[ "$stopping" = 1 ] && exit 0
exit "$rc"
