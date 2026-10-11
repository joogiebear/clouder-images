#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: palworld.sh <image>}
work=$(mktemp -d)
name=imgtest-palworld-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
d=/data/server/Pal/Binaries/Linux
mkdir -p "$d"
cat >/data/server/DefaultPalWorldSettings.ini <<'INI'
[/Script/Pal.PalGameWorldSettings]
OptionSettings=(Difficulty=None,ExpRate=1.000000,DeathPenalty=All,bIsPvP=False,ServerPlayerMaxNum=32,ServerName="Default Palworld Server",ServerDescription="",AdminPassword="",ServerPassword="",PublicPort=8211,RCONEnabled=False,RESTAPIEnabled=False)
INI
cat >"$d/PalServer-Linux-Shipping" <<'GAME'
#!/usr/bin/perl
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
$SIG{TERM} = sub {
  open my $s, '>', '/data/stopped.txt';
  print $s "interrupted\n";
  close $s;
  exit 143;
};
$| = 1;
print "running\n";
sleep 1 while 1;
GAME
chmod +x "$d/PalServer-Linux-Shipping"
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --name "$name" -e STUB_EXIT=1 -e SERVER_NAME="My Palworld" -e MAX_PLAYERS=abc -e PVP=true -e EXP_RATE=3 \
  -e ADMIN_PASSWORD=adm1n -e DEATH_PENALTY=bogus -e PUBLIC_LOBBY=true "$image" >/dev/null \
  || fail "the stubbed server did not start"
docker rm "$name" >/dev/null

ini=$work/server/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini
grep -qF 'ServerName="My Palworld"' "$ini" || fail "server name not written"
grep -qF "ServerPlayerMaxNum=16" "$ini" || fail "invalid max players not replaced by the default"
grep -qF "bIsPvP=True" "$ini" || fail "PvP not written"
grep -qF "ExpRate=3," "$ini" || fail "experience rate not written"
grep -qF 'AdminPassword="adm1n"' "$ini" || fail "admin password not written"
grep -qF "DeathPenalty=All" "$ini" || fail "unknown death penalty not replaced by the default"
grep -qx -- "-port=8211" "$work/args.txt" || fail "port not passed through"
grep -qx -- "-publiclobby" "$work/args.txt" || fail "-publiclobby missing"

run -d --name "$name" "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx running && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx running || fail "the stubbed game never started"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ -f "$work/stopped.txt" ] || fail "the stop signal never reached the game"

echo "palworld: ok"
