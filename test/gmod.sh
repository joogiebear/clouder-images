#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: gmod.sh <image>}
work=$(mktemp -d)
name=imgtest-gmod-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

out=$(run --rm "$image" 2>&1) && fail "started without RCON_PASSWORD"
grep -q "RCON_PASSWORD must be set" <<<"$out" || fail "missing password gave: $out"

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >>/data/steamcmd-args.txt
dir=""
app=""
while [ $# -gt 0 ]; do
  case "$1" in
    +force_install_dir) dir=$2 ;;
    +app_update) app=$2 ;;
  esac
  shift
done
if [ "$app" = 232330 ]; then
  mkdir -p "$dir/cstrike"
  exit 0
fi
mkdir -p "$dir"
cat >"$dir/srcds_linux" <<'GAME'
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
open my $log, '>>', 'garrysmod/console.log';
print $log "ready\n";
close $log;
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
chmod +x "$dir/srcds_linux"
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e "SERVER_NAME=My Server" -e MAX_PLAYERS=abc -e MAP=gm_flatgrass \
  -e GAMEMODE=terrortown -e STEAM_BRANCH=bogus! -e "SERVER_PASSWORD=bad pass" -e STEAM_TOKEN=ABC123 \
  -e WORKSHOP_COLLECTION=12345 -e WORKSHOP_AUTHKEY=KEY1 "$image" >/dev/null \
  || fail "the stubbed server did not start"

grep -qx -- '"My Server"' "$work/args.txt" || fail "server name not passed through, quoted so the engine keeps the spaces"
grep -qx -- "16" "$work/args.txt" || fail "invalid max players not replaced by the default"
grep -qx -- "gm_flatgrass" "$work/args.txt" || fail "map not passed through"
grep -qx -- "terrortown" "$work/args.txt" || fail "game mode not passed through"
grep -qx -- "-usercon" "$work/args.txt" || fail "RCON is not enabled"
grep -qx -- "-condebug" "$work/args.txt" || fail "the console log is off"
! grep -qx -- "+sv_password" "$work/args.txt" || fail "an unsafe password was passed"
grep -qx -- "+sv_setsteamaccount" "$work/args.txt" || fail "the Steam token was dropped"
grep -qx -- "+host_workshop_collection" "$work/args.txt" || fail "the workshop collection was dropped"
grep -qx -- "public" "$work/steamcmd-args.txt" || fail "unknown branch not replaced by public"
! grep -qx -- "validate" "$work/steamcmd-args.txt" || fail "validate ran without being asked"
grep -qx -- "232330" "$work/steamcmd-args.txt" || fail "the Counter-Strike: Source content was not installed"
grep -q '"cstrike"' "$work/server/garrysmod/cfg/mount.cfg" || fail "the Counter-Strike: Source content is not mounted"

rm -rf "$work/steamcmd-args.txt" "$work/css" "$work/server/garrysmod/cfg/mount.cfg"
run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e MOUNT_CSS=0 "$image" >/dev/null || fail "the stubbed server did not start without CSS"
! grep -qx -- "232330" "$work/steamcmd-args.txt" || fail "the Counter-Strike: Source content was installed although it is off"
[ ! -f "$work/server/garrysmod/cfg/mount.cfg" ] || fail "content was mounted although it is off"
! grep -qx -- "+host_workshop_collection" "$work/args.txt" || fail "a workshop collection without a key was passed"

run -d --name "$name" -e RCON_PASSWORD=pw -e SERVER_PORT=27099 "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx ready && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx ready || fail "the stubbed game never became ready"

for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -qx "\[clouder\] Garry's Mod is accepting connections" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -qx "\[clouder\] Garry's Mod is accepting connections" || fail "readiness was never reported"

docker exec "$name" console "status" || fail "console command failed"
docker logs "$name" 2>&1 | grep -qx "\[rcon\] echo:status" || fail "console answer is not in the log"
docker exec -e RCON_PASSWORD=wrong "$name" console "status" 2>/dev/null && fail "a wrong password was accepted"

docker stop -t 30 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ -f "$work/quit.txt" ] || fail "the stop never reached the game console"

echo "gmod: ok"
