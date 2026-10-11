#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: vintagestory.sh <image>}
work=$(mktemp -d)
name=imgtest-vs-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" -e PATH=/data/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin "$@"; }
conf() {
  local json
  json=$(sed -n '/^--setconfig$/{n;p}' "$work/args-config.txt")
  docker run --rm -i --entrypoint jq "$image" -r "$1" <<<"$json"
}

mkdir -p "$work/bin" "$work/server"
echo "1.22.7" >"$work/server/.version"
touch "$work/server/VintagestoryServer.dll"
cat >"$work/bin/dotnet" <<'EOF'
#!/usr/bin/perl
my $kind = (grep { $_ eq '--setconfig' } @ARGV) ? 'config' : 'run';
open my $f, '>', "/data/args-$kind.txt";
print $f "$_\n" for @ARGV;
close $f;
exit 200 if $kind eq 'config';
exit 0 if $ENV{STUB_EXIT};
$| = 1;
print "Dedicated Server now running on Port 42420 and all ips!\n";
while (my $line = <STDIN>) {
  chomp $line;
  open my $l, '>>', '/data/commands.txt';
  print $l "$line\n";
  close $l;
  if ($line eq '/stop') {
    print "Stopped the server!\n";
    exit 0;
  }
}
EOF
chmod +x "$work/bin/dotnet"

run --rm -e STUB_EXIT=1 -e VS_VERSION=1.22.7 -e "SERVER_NAME=My World" -e MAX_PLAYERS=abc -e SERVER_PORT=42500 \
  -e SERVER_PASSWORD=pw -e WHITELIST=true -e ALLOW_PVP=maybe -e 'WORLD_SEED=bad;seed' -e ADVERTISE=true "$image" >/dev/null \
  || fail "the stubbed server did not start"

grep -qx -- "--dataPath" "$work/args-run.txt" || fail "data path not passed to the server"
[ "$(conf .ServerName)" = "My World" ] || fail "server name not written"
[ "$(conf .Port)" = "42500" ] || fail "port not written"
[ "$(conf .MaxClients)" = "16" ] || fail "invalid max players not replaced by the default"
[ "$(conf .Password)" = "pw" ] || fail "password not written"
[ "$(conf .WhitelistMode)" = "1" ] || fail "whitelist not turned on"
[ "$(conf .AllowPvP)" = "true" ] || fail "invalid pvp not replaced by the default"
[ "$(conf .AdvertiseServer)" = "true" ] || fail "advertising not written"
[ "$(conf .WorldConfig.Seed)" = "null" ] || fail "an unsafe seed was written"

run --rm -e STUB_EXIT=1 -e VS_VERSION=1.22.7 -e WORLD_SEED=hello "$image" >/dev/null || fail "the stubbed server did not start with a seed"
[ "$(conf .WorldConfig.Seed)" = "hello" ] || fail "seed not written"
[ "$(conf .Password)" = "null" ] || fail "an empty password was written as text"
[ "$(conf .WhitelistMode)" = "0" ] || fail "whitelist is on by default"

run -d --name "$name" -e VS_VERSION=1.22.7 "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -q "Dedicated Server now running" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -q "Dedicated Server now running" || fail "the stubbed game never started"

docker exec "$name" /usr/local/bin/clouder-console "/announce hello"
for _ in $(seq 1 50); do
  [ -f "$work/commands.txt" ] && break
  sleep 0.2
done
grep -qx "/announce hello" "$work/commands.txt" || fail "console input did not reach the game"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
grep -qx "/stop" "$work/commands.txt" || fail "the stop did not send /stop to the game"

echo "vintagestory: ok"
