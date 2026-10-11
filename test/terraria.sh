#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: terraria.sh <image>}
work=$(mktemp -d)
name=imgtest-terraria-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

d=$work/server/1458/Linux
mkdir -p "$d"
cat >"$d/TerrariaServer.bin.x86_64" <<'EOF'
#!/usr/bin/perl
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
$| = 1;
print "Server started\n";
while (my $line = <STDIN>) {
  chomp $line;
  open my $l, '>>', '/data/commands.txt';
  print $l "$line\n";
  close $l;
  if ($line eq 'exit') {
    print "Saving before exit\n";
    exit 0;
  }
}
EOF
chmod +x "$d/TerrariaServer.bin.x86_64"

run --name "$name" -e STUB_EXIT=1 -e WORLD_NAME="My World" -e MAX_PLAYERS=abc -e WORLD_SIZE=9 -e DIFFICULTY=2 \
  -e SERVER_PASSWORD=pw -e SERVER_PORT=7778 "$image" >/dev/null \
  || fail "the stubbed server did not start"
docker rm "$name" >/dev/null

cfg=$work/serverconfig.txt
grep -qx "worldname=My World" "$cfg" || fail "world name not written"
grep -qx "world=/data/worlds/My World.wld" "$cfg" || fail "world path not written"
grep -qx "maxplayers=8" "$cfg" || fail "invalid max players not replaced by the default"
grep -qx "autocreate=2" "$cfg" || fail "invalid world size not replaced by the default"
grep -qx "difficulty=2" "$cfg" || fail "difficulty not written"
grep -qx "password=pw" "$cfg" || fail "password not written"
grep -qx "port=7778" "$cfg" || fail "port not written"
grep -qx -- "/data/serverconfig.txt" "$work/args.txt" || fail "config file not passed to the server"

run -d --name "$name" "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx "Server started" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx "Server started" || fail "the stubbed game never started"

docker exec "$name" /usr/local/bin/clouder-console "say hello there"
for _ in $(seq 1 50); do
  [ -f "$work/commands.txt" ] && break
  sleep 0.2
done
grep -qx "say hello there" "$work/commands.txt" || fail "console input did not reach the game"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
grep -qx "exit" "$work/commands.txt" || fail "the stop did not send exit to the game"

echo "terraria: ok"
