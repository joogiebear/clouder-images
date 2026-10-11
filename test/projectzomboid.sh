#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: projectzomboid.sh <image>}
work=$(mktemp -d)
name=imgtest-projectzomboid-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
mkdir -p /data/server
printf '{"vmArgs": ["-Xmx8g", "-Dfoo=bar"]}\n' >/data/server/ProjectZomboid64.json
cat >/data/server/start-server.sh <<'GAME'
#!/usr/bin/perl
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
$| = 1;
print "*** SERVER STARTED ****\n";
while (my $line = <STDIN>) {
  chomp $line;
  open my $l, '>>', '/data/commands.txt';
  print $l "$line\n";
  close $l;
  exit 0 if $line eq 'quit';
}
GAME
chmod +x /data/server/start-server.sh
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

mkdir -p "$work/Zomboid/Server"
printf 'PublicName=Old\nMaxPlayers=32\nMods=keep\n' >"$work/Zomboid/Server/myworld.ini"

run --name "$name" -e STUB_EXIT=1 -e SERVER_NAME=myworld -e PUBLIC_NAME="My Server" -e MAX_PLAYERS=abc \
  -e PVP=false -e XMX=6144m -e STEAM_BRANCH=bogus -e ADMIN_PASSWORD=adm1npw "$image" >/dev/null \
  || fail "the stubbed server did not start"
docker rm "$name" >/dev/null

ini=$work/Zomboid/Server/myworld.ini
grep -qx "PublicName=My Server" "$ini" || fail "public name not written over the old one"
grep -qx "MaxPlayers=16" "$ini" || fail "invalid max players not replaced by the default"
grep -qx "PVP=false" "$ini" || fail "PVP not written"
grep -qx "Mods=keep" "$ini" || fail "an unmanaged setting was lost"
grep -qx "DefaultPort=16261" "$ini" || fail "game port not written"
grep -q -- "-Xmx6144m" "$work/server/ProjectZomboid64.json" || fail "memory not applied"
grep -qx "public" "$work/steamcmd-args.txt" || fail "unknown branch not replaced by public"
grep -qx -- "adm1npw" "$work/args.txt" || fail "admin password not passed to the server"
grep -qx -- "-servername" "$work/args.txt" || fail "server name flag missing"

rm -f "$work/args.txt"
out=$(run --rm -e STUB_EXIT=1 "$image" 2>&1)
grep -q "admin account password is" <<<"$out" || fail "no admin password was announced: $out"
[ "$(wc -c <"$work/.admin-password")" -ge 10 ] || fail "generated admin password is too short"
grep -qx -- "$(cat "$work/.admin-password")" "$work/args.txt" || fail "generated admin password not passed to the server"

run -d --name "$name" "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -q "SERVER STARTED" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -q "SERVER STARTED" || fail "the stubbed game never started"

docker exec "$name" /usr/local/bin/clouder-console "players"
for _ in $(seq 1 50); do
  [ -f "$work/commands.txt" ] && break
  sleep 0.2
done
grep -qx "players" "$work/commands.txt" || fail "console input did not reach the game"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
grep -qx "quit" "$work/commands.txt" || fail "the stop did not send quit to the game"

echo "projectzomboid: ok"
