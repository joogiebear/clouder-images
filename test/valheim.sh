#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: valheim.sh <image>}
work=$(mktemp -d)
name=imgtest-valheim-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
mkdir -p /data/server
cat >/data/server/valheim_server.x86_64 <<'GAME'
#!/usr/bin/perl
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
print $f "$ENV{SteamAppId}\n";
close $f;
exit 0 if $ENV{STUB_EXIT};
$SIG{INT} = sub {
  open my $s, '>', '/data/stopped.txt';
  print $s "interrupted\n";
  close $s;
  exit 143;
};
$| = 1;
print "ready\n";
sleep 1 while 1;
GAME
chmod +x /data/server/valheim_server.x86_64
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

out=$(run --rm -e SERVER_PASSWORD=abc "$image" 2>&1) && fail "accepted a password of 3 characters"
grep -q "at least 5 characters" <<<"$out" || fail "short password gave: $out"

out=$(run --rm -e SERVER_NAME=Secret1 -e SERVER_PASSWORD=secret "$image" 2>&1) && fail "accepted a password that is part of the name"
grep -q "part of the server name" <<<"$out" || fail "password in name gave: $out"

run --name "$name" -e STUB_EXIT=1 -e SERVER_NAME="My Server" -e WORLD_NAME='bad;name' -e SAVE_INTERVAL=abc \
  -e PUBLIC=true -e PRESET=hard -e SERVER_PASSWORD=hunter22 "$image" >/dev/null \
  || fail "the stubbed server did not start"
docker rm "$name" >/dev/null

grep -qx -- "My Server" "$work/args.txt" || fail "server name not passed through"
grep -qx -- "Dedicated" "$work/args.txt" || fail "unsafe world name not replaced by the default"
grep -qx -- "1800" "$work/args.txt" || fail "invalid save interval not replaced by the default"
grep -qx -- "hard" "$work/args.txt" || fail "preset not passed through"
grep -qx -- "892970" "$work/args.txt" || fail "SteamAppId not set"
grep -qx -- "-public" "$work/args.txt" || fail "-public missing"

run -d --name "$name" "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx ready && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx ready || fail "the stubbed game never became ready"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ -f "$work/stopped.txt" ] || fail "the stop signal never reached the game"

echo "valheim: ok"
