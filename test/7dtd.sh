#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: 7dtd.sh <image>}
work=$(mktemp -d)
name=imgtest-7dtd-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; docker logs "$name" >&2 2>&1 || true; exit 1; }
run() { docker run -i --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }
prop() { grep -o "name=\"$1\" value=\"[^\"]*\"" "$work/serverconfig.xml" | sed 's/.*value="//; s/"$//'; }

out=$(run --rm "$image" 2>&1) && fail "started without RCON_PASSWORD"
grep -q "RCON_PASSWORD must be set" <<<"$out" || fail "missing password gave: $out"

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/steamcmd-args.txt
mkdir -p /data/server
cat >/data/server/serverconfig.xml <<'XML'
<?xml version="1.0"?>
<ServerSettings>
  <property name="ServerPort" value="26900"/>
  <property name="ServerName" value="My Game Host"/>
  <property name="ServerPassword" value=""/>
  <property name="TelnetPort" value="8081"/>
</ServerSettings>
XML
cat >/data/server/7DaysToDieServer.x86_64 <<'GAME'
#!/usr/bin/perl
use strict;
use IO::Socket::INET;
open my $f, '>', '/data/args.txt';
print $f "$_\n" for @ARGV;
close $f;
exit 0 if $ENV{STUB_EXIT};
my $srv = IO::Socket::INET->new(Listen => 5, LocalPort => 8081, ReuseAddr => 1, Proto => 'tcp') or die "listen: $!";
$| = 1;
print "2026-10-11T16:16:38 45.513 INF StartGame done\n";
while (my $c = $srv->accept) {
  $c->autoflush(1);
  print $c "Please enter password:\r\n";
  my $pw = <$c>;
  $pw =~ s/\r?\n$//;
  if ($pw ne $ENV{RCON_PASSWORD}) {
    print $c "Wrong password!\r\n";
    next;
  }
  print $c "Logon successful.\r\n\r\nPress 'help' for a list of commands.\r\n";
  print $c "*** Connected with 7DTD server.\r\nServer port: 8081\r\n";
  while (my $line = <$c>) {
    $line =~ s/\r?\n$//;
    last if $line eq 'exit';
    if ($line eq 'shutdown') {
      open my $s, '>', '/data/shutdown.txt';
      close $s;
      exit 0;
    }
    print $c "2026-10-11T16:17:02 69.871 INF Executing command '$line' by Telnet from 127.0.0.1:59084\r\n";
    print $c "echo:$line\r\n";
    print $c "2026-10-11T16:17:03 70.000 INF unrelated log line\r\n";
  }
}
GAME
chmod +x /data/server/7DaysToDieServer.x86_64
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run --rm -e STUB_EXIT=1 -e RCON_PASSWORD=pw -e "SERVER_NAME=My <Server> & Co" -e MAX_PLAYERS=abc -e WORLD_SIZE=5000 \
  -e VISIBILITY=unlisted -e GAME_WORLD=Navezgane -e "SERVER_PASSWORD=a&b" "$image" >/dev/null \
  || fail "the stubbed server did not start"

[ "$(prop ServerName)" = "My &lt;Server&gt; &amp; Co" ] || fail "server name not written: $(prop ServerName)"
[ "$(prop ServerMaxPlayerCount)" = "8" ] || fail "invalid max players not replaced by the default"
[ "$(prop WorldGenSize)" = "6144" ] || fail "invalid world size not replaced by the default"
[ "$(prop ServerVisibility)" = "0" ] || fail "unlisted visibility not written"
[ "$(prop GameWorld)" = "Navezgane" ] || fail "world not written"
[ "$(prop ServerPassword)" = "a&amp;b" ] || fail "server password not written"
[ "$(prop TelnetPassword)" = "pw" ] || fail "telnet password is not the console password"
[ "$(prop TelnetEnabled)" = "true" ] || fail "telnet is not enabled"
[ "$(prop UserDataFolder)" = "/data/userdata" ] || fail "saves are not in the data volume"
grep -qx -- "-dedicated" "$work/args.txt" || fail "the server was not started dedicated"
grep -qx -- "-configfile=/data/serverconfig.xml" "$work/args.txt" || fail "the config file is not used"
grep -qx -- "public" "$work/steamcmd-args.txt" || fail "default branch is not public"

run -d --name "$name" -e RCON_PASSWORD=pw "$image" >/dev/null
for _ in $(seq 1 50); do
  docker logs "$name" 2>&1 | grep -q "StartGame done" && break
  sleep 0.2
done
docker logs "$name" 2>&1 | grep -q "StartGame done" || fail "the stubbed game never became ready"

docker exec "$name" console "listplayers" || fail "console command failed"
docker logs "$name" 2>&1 | grep -qx "\[telnet\] echo:listplayers" || fail "console answer is not in the log"
! docker logs "$name" 2>&1 | grep -q "\[telnet\].*\(unrelated\|Connected with\|Server port\)" || fail "the console repeated the server log or the banner"
docker exec -e RCON_PASSWORD=wrong "$name" console "listplayers" 2>/dev/null && fail "a wrong password was accepted"

docker stop -t 60 "$name" >/dev/null
[ "$(docker inspect -f '{{.State.ExitCode}}' "$name")" = "0" ] || fail "a requested stop did not exit cleanly"
[ -f "$work/shutdown.txt" ] || fail "the stop never reached the game console"

echo "7dtd: ok"
