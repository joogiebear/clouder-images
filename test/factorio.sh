#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: factorio.sh <image>}
work=$(mktemp -d)
name=imgtest-factorio-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
setting() { docker run --rm --user "$(id -u):$(id -g)" -v "$work:/data" --entrypoint jq "$image" -r "$1" /data/config/server-settings.json; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" -e UPDATE_ON_START=0 "$@"; }

out=$(run --rm "$image" 2>&1) && fail "started without RCON_PASSWORD"
grep -q "RCON_PASSWORD must be set" <<<"$out" || fail "missing password gave: $out"

mkdir -p "$work/server/bin/x64" "$work/server/data"
echo '{"name": "x", "description": "x", "visibility": {"public": true, "lan": false}, "max_players": 0}' >"$work/server/data/server-settings.example.json"
cat >"$work/server/bin/x64/factorio" <<'GAME'
#!/usr/bin/perl
use strict;
use IO::Socket::INET;
open my $f, '>>', '/data/args.txt';
print $f join("\n", @ARGV), "\n";
close $f;
for my $i (0 .. $#ARGV) {
  if ($ARGV[$i] eq '--create') {
    open my $z, '>', $ARGV[$i + 1];
    close $z;
    exit 0;
  }
}
exit 0 if $ENV{STUB_EXIT};
my $port = 0;
for my $i (0 .. $#ARGV) { $port = $1 if $ARGV[$i] eq '--rcon-bind' && $ARGV[$i + 1] =~ /:(\d+)$/; }
my $saved = 0;
$SIG{TERM} = sub {
  open my $s, '>', '/data/terminated.txt';
  print $s $saved ? "saved\n" : "unsaved\n";
  close $s;
  exit 0;
};
my $srv = IO::Socket::INET->new(Listen => 5, LocalPort => $port, ReuseAddr => 1, Proto => 'tcp') or die "listen: $!";
$| = 1;
print "Hosting game at IP ADDR:({0.0.0.0:34197})\n";
sub pkt {
  my ($c, $id, $type, $body) = @_;
  $c->print(pack('l< l< l<', 10 + length($body), $id, $type) . $body . "\0\0");
}
while (my $c = $srv->accept) {
  while (read($c, my $h, 4) == 4) {
    my $size = unpack('l<', $h);
    read($c, my $p, $size);
    my ($id, $type) = unpack('l< l<', $p);
    my $body = substr($p, 8, $size - 10);
    if ($type == 3) {
      pkt($c, $body eq $ENV{RCON_PASSWORD} ? $id : -1, 2, '');
    } else {
      $saved = 1 if $body eq '/save';
      pkt($c, $id, 0, "echo:$body");
    }
  }
}
GAME
chmod +x "$work/server/bin/x64/factorio"
echo "2.0.0" >"$work/server/.version"

run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e "SERVER_NAME=My Factory" -e MAX_PLAYERS=abc -e AUTOSAVE_INTERVAL=5 \
  -e VISIBILITY=public -e AUTO_PAUSE=bogus -e "GAME_PASSWORD=secret" "$image" >/dev/null \
  || fail "the stubbed server did not start"

[ -f "$work/saves/world.zip" ] || fail "a new map was not created"
[ "$(setting .name)" = "My Factory" ] || fail "server name not written"
[ "$(setting .max_players)" = "0" ] || fail "invalid max players not replaced by the default"
[ "$(setting .autosave_interval)" = "5" ] || fail "autosave interval not written"
[ "$(setting .auto_pause)" = "true" ] || fail "invalid auto pause not replaced by the default"
[ "$(setting .visibility.public)" = "true" ] || fail "public visibility not written"
[ "$(setting .game_password)" = "secret" ] || fail "game password not written"
[ "$(cat "$work/config/server-adminlist.json")" = "[]" ] || fail "admin list not created"
grep -qx -- "--start-server-load-latest" "$work/args.txt" || fail "the server was not started from the latest save"
grep -qx -- "--rcon-bind" "$work/args.txt" || fail "RCON is not enabled"

run -d --name "$name" -e RCON_PASSWORD=pw -e RCON_PORT=27055 "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -q "Hosting game at" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -q "Hosting game at" || fail "the stubbed game never became ready"

docker exec "$name" console "/players" || fail "console command failed"
docker logs "$name" 2>&1 | grep -qx "\[rcon\] echo:/players" || fail "console answer is not in the log"

docker stop -t 30 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ "$(cat "$work/terminated.txt")" = "saved" ] || fail "the game was not asked to save before it was stopped"

echo "factorio: ok"
