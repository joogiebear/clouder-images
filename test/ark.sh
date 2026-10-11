#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: ark.sh <image>}
work=$(mktemp -d)
name=imgtest-ark-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

out=$(run --rm "$image" 2>&1) && fail "started without RCON_PASSWORD"
grep -q "RCON_PASSWORD must be set" <<<"$out" || fail "missing password gave: $out"

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
d=/data/server/ShooterGame/Binaries/Linux
mkdir -p "$d"
cat >"$d/ShooterGameServer" <<'GAME'
#!/usr/bin/perl
use strict;
use IO::Socket::INET;
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
my ($port, $admin) = (0, '');
$port = $1 if $ARGV[0] =~ /\?RCONPort=(\d+)/;
$admin = $1 if $ARGV[0] =~ /\?ServerAdminPassword=([^?]*)/;
my $srv = IO::Socket::INET->new(Listen => 5, LocalPort => $port, ReuseAddr => 1, Proto => 'tcp') or die "listen: $!";
$| = 1;
print "Server has completed startup and is now advertising for join.\n";
my $saved = 0;
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
      pkt($c, $body eq $admin ? $id : -1, 2, '');
    } elsif ($body eq 'DoExit') {
      open my $s, '>', '/data/exit.txt';
      print $s $saved ? "saved\n" : "unsaved\n";
      close $s;
      exit 0;
    } else {
      $saved = 1 if $body eq 'saveworld';
      pkt($c, $id, 0, "echo:$body");
    }
  }
}
GAME
chmod +x "$d/ShooterGameServer"
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e "SERVER_NAME=My Ark" -e MAX_PLAYERS=abc -e MAP=Ragnarok \
  -e "SERVER_PASSWORD=bad pass" -e STEAM_BRANCH=bogus! "$image" >/dev/null \
  || fail "the stubbed server did not start"

url=$(sed -n 1p "$work/args.txt")
[[ "$url" == Ragnarok\?listen\?SessionName=My\ Ark\?Port=7777\?QueryPort=27015\?* ]] || fail "unexpected map and session: $url"
[[ "$url" == *"?MaxPlayers=20"* ]] || fail "invalid max players not replaced by the default: $url"
[[ "$url" == *"?ServerAdminPassword=pw?"* ]] || fail "the admin password should default to the console password: $url"
[[ "$url" != *ServerPassword* ]] || fail "an unsafe join password was passed: $url"
grep -qx -- "-server" "$work/args.txt" || fail "the server was not started dedicated"
grep -qx -- "public" "$work/steamcmd-args.txt" || fail "unknown branch not replaced by public"
! grep -qx -- "validate" "$work/steamcmd-args.txt" || fail "validate ran without being asked"

run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e ADMIN_PASSWORD=boss -e SERVER_PASSWORD=join "$image" >/dev/null \
  || fail "the second stubbed start failed"
url=$(sed -n 1p "$work/args.txt")
[[ "$url" == *"?ServerAdminPassword=boss?"* && "$url" == *"?ServerPassword=join" ]] || fail "passwords not passed through: $url"

run -d --name "$name" -e RCON_PASSWORD=pw -e ADMIN_PASSWORD=boss "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -q "advertising for join" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -q "advertising for join" || fail "the stubbed game never became ready"

docker exec "$name" console "listplayers" || fail "console command failed"
docker logs "$name" 2>&1 | grep -qx "\[rcon\] echo:listplayers" || fail "console answer is not in the log"

docker stop -t 60 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ "$(cat "$work/exit.txt")" = "saved" ] || fail "the world was not saved before the server exited"

echo "ark: ok"
