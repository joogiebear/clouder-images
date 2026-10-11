#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: cs2.sh <image>}
work=$(mktemp -d)
name=imgtest-cs2-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

out=$(run --rm "$image" 2>&1) && fail "started without RCON_PASSWORD"
grep -q "RCON_PASSWORD must be set" <<<"$out" || fail "missing password gave: $out"

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
d=/data/server/game/bin/linuxsteamrt64
mkdir -p "$d"
cat >"$d/cs2" <<'GAME'
#!/usr/bin/perl
use strict;
use IO::Socket::INET;
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
my $port = 0;
for my $i (0 .. $#ARGV) { $port = $ARGV[$i + 1] if $ARGV[$i] eq '-port'; }
my $srv = IO::Socket::INET->new(Listen => 5, LocalPort => $port, ReuseAddr => 1, Proto => 'tcp') or die "listen: $!";
$| = 1;
print "ready\n";
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
      pkt($c, 0, 0, '');
      pkt($c, $body eq $ENV{RCON_PASSWORD} ? $id : -1, 2, '');
    } elsif ($body eq 'quit') {
      open my $s, '>', '/data/quit.txt';
      close $s;
      exit 0;
    } else {
      pkt($c, $id, 0, "echo:$body");
    }
  }
}
GAME
chmod +x "$d/cs2"
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e "SERVER_NAME=My Server" -e MAX_PLAYERS=abc -e MAP=de_mirage \
  -e GAME_MODE=deathmatch -e STEAM_BRANCH=bogus! -e "SERVER_PASSWORD=bad pass" -e STEAM_TOKEN=ABC123 "$image" >/dev/null \
  || fail "the stubbed server did not start"

grep -qx -- '"My Server"' "$work/args.txt" || fail "server name not passed through, quoted so the engine keeps the spaces"
grep -qx -- "10" "$work/args.txt" || fail "invalid max players not replaced by the default"
grep -qx -- "de_mirage" "$work/args.txt" || fail "map not passed through"
grep -qx -- "-usercon" "$work/args.txt" || fail "RCON is not enabled"
[ "$(grep -x -A1 -- '+game_type' "$work/args.txt" | tail -1)" = "1" ] || fail "deathmatch is game type 1"
[ "$(grep -x -A1 -- '+game_mode' "$work/args.txt" | tail -1)" = "2" ] || fail "deathmatch is game mode 2"
! grep -qx -- "+sv_password" "$work/args.txt" || fail "an unsafe password was passed"
grep -qx -- "+sv_setsteamaccount" "$work/args.txt" || fail "the Steam token was dropped"
grep -qx -- "public" "$work/steamcmd-args.txt" || fail "unknown branch not replaced by public"
! grep -qx -- "validate" "$work/steamcmd-args.txt" || fail "validate ran without being asked"

run -d --name "$name" -e RCON_PASSWORD=pw -e SERVER_PORT=27099 "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx ready && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx ready || fail "the stubbed game never became ready"

docker exec "$name" console "status" || fail "console command failed"
docker logs "$name" 2>&1 | grep -qx "\[rcon\] echo:status" || fail "console answer is not in the log"
docker exec -e RCON_PASSWORD=wrong "$name" console "status" 2>/dev/null && fail "a wrong password was accepted"

docker stop -t 30 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ -f "$work/quit.txt" ] || fail "the stop never reached the game console"

echo "cs2: ok"
