#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: satisfactory.sh <image>}
work=$(mktemp -d)
name=imgtest-satisfactory-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
d=/data/server/Engine/Binaries/Linux
mkdir -p "$d"
printf '#!/bin/sh\n' >/data/server/FactoryServer.sh
cat >"$d/FactoryServer-Linux-Shipping" <<'GAME'
#!/usr/bin/perl
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
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
chmod +x /data/server/FactoryServer.sh "$d/FactoryServer-Linux-Shipping"
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --name "$name" -e STUB_EXIT=1 -e MAX_PLAYERS=abc -e AUTOSAVE_COUNT=7 -e STEAM_BRANCH=bogus "$image" >/dev/null \
  || fail "the stubbed server did not start"
docker rm "$name" >/dev/null

grep -qF "GameSession]:MaxPlayers=4" "$work/args.txt" || fail "invalid max players not replaced by the default"
grep -qF "mNumRotatingAutosaves=7" "$work/args.txt" || fail "autosave count not passed through"
grep -qx -- "public" "$work/steamcmd-args.txt" || fail "unknown branch not replaced by public"
! grep -qx -- "validate" "$work/steamcmd-args.txt" || fail "validate ran without being asked"

run --rm -e STUB_EXIT=1 -e VALIDATE_ON_START=1 "$image" >/dev/null || fail "the validating start failed"
grep -qx -- "validate" "$work/steamcmd-args.txt" || fail "VALIDATE_ON_START did not validate"

run -d --name "$name" "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx ready && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx ready || fail "the stubbed game never became ready"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ -f "$work/stopped.txt" ] || fail "the stop signal never reached the game"

echo "satisfactory: ok"
