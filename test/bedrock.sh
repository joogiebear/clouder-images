#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: bedrock.sh <image>}
work=$(mktemp -d)
name=imgtest-bedrock-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

d=$work/server
mkdir -p "$d"
echo "1.21.1.1" >"$d/.version"
printf 'server-name=Dedicated Server\ngamemode=survival\nlevel-name=Bedrock level\ntexturepack-required=false\n' >"$d/server.properties"
cat >"$d/bedrock_server" <<'EOF'
#!/usr/bin/perl
open my $f, '>', '/data/ld.txt';
print $f "$ENV{LD_LIBRARY_PATH}\n";
close $f;
exit 0 if $ENV{STUB_EXIT};
$| = 1;
print "[INFO] Server started.\n";
while (my $line = <STDIN>) {
  chomp $line;
  open my $l, '>>', '/data/commands.txt';
  print $l "$line\n";
  close $l;
  if ($line eq 'stop') {
    print "[INFO] Quit correctly\n";
    exit 0;
  }
}
EOF
chmod +x "$d/bedrock_server"

run --name "$name" -e STUB_EXIT=1 -e BEDROCK_VERSION=1.21.1.1 -e "SERVER_NAME=My Realm" -e MAX_PLAYERS=abc \
  -e GAMEMODE=creative -e DIFFICULTY=impossible -e ALLOW_CHEATS=true -e SERVER_PORT=19140 -e 'LEVEL_SEED=bad;seed' "$image" >/dev/null \
  || fail "the stubbed server did not start"
docker rm "$name" >/dev/null

props=$d/server.properties
grep -qx "server-name=My Realm" "$props" || fail "server name not written"
grep -qx "gamemode=creative" "$props" || fail "game mode not written"
grep -qx "difficulty=easy" "$props" || fail "invalid difficulty not replaced by the default"
grep -qx "max-players=10" "$props" || fail "invalid max players not replaced by the default"
grep -qx "allow-cheats=true" "$props" || fail "cheats not written"
grep -qx "server-port=19140" "$props" || fail "port not written"
grep -qx "server-portv6=19141" "$props" || fail "IPv6 port not derived"
grep -qx "level-seed=" "$props" || fail "an unsafe seed was written"
grep -qx "texturepack-required=false" "$props" || fail "a setting the image does not manage was lost"
[ "$(grep -c '^server-name=' "$props")" = 1 ] || fail "server name written twice"
grep -qx "." "$work/ld.txt" || fail "the server does not load its libraries from its own folder"

run -d --name "$name" -e BEDROCK_VERSION=1.21.1.1 "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx "\[INFO\] Server started." && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx "\[INFO\] Server started." || fail "the stubbed game never started"

docker exec "$name" /usr/local/bin/clouder-console "say hello there"
for _ in $(seq 1 50); do
  [ -f "$work/commands.txt" ] && break
  sleep 0.2
done
grep -qx "say hello there" "$work/commands.txt" || fail "console input did not reach the game"

docker stop -t 20 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
grep -qx "stop" "$work/commands.txt" || fail "the stop did not send stop to the game"

echo "bedrock: ok"
