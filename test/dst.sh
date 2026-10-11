#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: dst.sh <image>}
work=$(mktemp -d)
name=imgtest-dst-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

out=$(run --rm "$image" 2>&1) && fail "started without a cluster token"
grep -q "CLUSTER_TOKEN must be set" <<<"$out" || fail "missing token gave: $out"

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
d=/data/server/bin64
mkdir -p "$d"
cat >"$d/dontstarve_dedicated_server_nullrenderer_x64" <<'GAME'
#!/usr/bin/perl
my $shard = '';
for my $i (0 .. $#ARGV) { $shard = $ARGV[$i + 1] if $ARGV[$i] eq '-shard'; }
open my $f, '>', "/data/args-$shard.txt";
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
$| = 1;
print "Sim paused $shard\n";
while (my $line = <STDIN>) {
  chomp $line;
  open my $l, '>>', "/data/commands-$shard.txt";
  print $l "$line\n";
  close $l;
  if ($line eq 'c_shutdown(true)') {
    print "Shutting down $shard\n";
    exit 0;
  }
}
GAME
chmod +x "$d/dontstarve_dedicated_server_nullrenderer_x64"
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --rm -e STUB_EXIT=1 -e 'CLUSTER_TOKEN=pds-g^KU_abc^xyz=' -e "SERVER_NAME=My Camp" -e MAX_PLAYERS=abc \
  -e GAME_MODE=endless -e PVP=maybe -e "SERVER_PASSWORD=bad pass" -e SERVER_PORT=11111 \
  -e WORKSHOP_MODS=111,222 "$image" >/dev/null \
  || fail "the stubbed server did not start"

c=$work/DoNotStarveTogether/Cluster
grep -qx "cluster_name = My Camp" "$c/cluster.ini" || fail "server name not written"
grep -qx "game_mode = endless" "$c/cluster.ini" || fail "game mode not written"
grep -qx "max_players = 6" "$c/cluster.ini" || fail "invalid max players not replaced by the default"
grep -qx "pvp = false" "$c/cluster.ini" || fail "invalid pvp not replaced by the default"
grep -qx "cluster_password = " "$c/cluster.ini" || fail "an unsafe password was written"
grep -qx "shard_enabled = false" "$c/cluster.ini" || fail "caves are on by default"
grep -qx "server_port = 11111" "$c/Master/server.ini" || fail "port not written"
[ "$(cat "$c/cluster_token.txt")" = 'pds-g^KU_abc^xyz=' ] || fail "token not written"
[ ! -d "$c/Caves" ] || fail "a caves shard was created although caves are off"
grep -qx 'ServerModSetup("111")' "$work/server/mods/dedicated_server_mods_setup.lua" || fail "mod download list not written"
grep -q 'workshop-222' "$c/Master/modoverrides.lua" || fail "mods not enabled"
grep -qx -- "Master" "$work/args-Master.txt" || fail "the master shard was not started"
grep -qx -- "Cluster" "$work/args-Master.txt" || fail "cluster name not passed"

run -d --name "$name" -e CLUSTER_TOKEN=tok -e ENABLE_CAVES=true "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -q "Sim paused Master" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -q "Sim paused Master" || fail "the stubbed game never started"

grep -qx "shard_enabled = true" "$c/cluster.ini" || fail "caves not enabled"
grep -q 'DST_CAVE' "$c/Caves/worldgenoverride.lua" || fail "cave preset not written"
for _ in $(seq 1 50); do
  [ -f "$work/args-Caves.txt" ] && break
  sleep 0.2
done
grep -qx -- "Caves" "$work/args-Caves.txt" || fail "the caves shard was not started"

docker exec "$name" /usr/local/bin/clouder-console "c_announce('hello')"
for _ in $(seq 1 50); do
  [ -f "$work/commands-Master.txt" ] && break
  sleep 0.2
done
grep -qx "c_announce('hello')" "$work/commands-Master.txt" || fail "console input did not reach the game"

docker stop -t 30 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
grep -qx "c_shutdown(true)" "$work/commands-Master.txt" || fail "the stop did not shut the master down"
grep -qx "c_shutdown(true)" "$work/commands-Caves.txt" || fail "the stop did not shut the caves down"

echo "dst: ok"
