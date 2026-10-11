#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: rust.sh <image>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
run() { docker run --rm --user "$(id -u):$(id -g)" -v "$work:/data" "$@"; }

out=$(run "$image" 2>&1) && fail "started without RCON_PASSWORD"
grep -q "RCON_PASSWORD must be set" <<<"$out" || fail "missing password gave: $out"

out=$(run -e RCON_PASSWORD=pw -e FRAMEWORK=bogus "$image" 2>&1) && fail "accepted an unknown FRAMEWORK"
grep -q "unknown FRAMEWORK" <<<"$out" || fail "unknown framework gave: $out"

mkdir -p "$work/steamcmd"
cat >"$work/steamcmd/steamcmd.sh" <<'EOF'
#!/usr/bin/env bash
mkdir -p /data/server
cat >/data/server/RustDedicated <<'GAME'
#!/usr/bin/env bash
printf '%s\n' "$@" >/data/args.txt
printf '%s' "$LD_PRELOAD" >/data/preload.txt
exec 0<&-
[ -e /proc/$$/fd/0 ] && echo open >/data/stdin.txt
GAME
chmod +x /data/server/RustDedicated
EOF
chmod +x "$work/steamcmd/steamcmd.sh"

run -e RCON_PASSWORD=pw -e "SERVER_NAME=My Server" -e WORLD_SIZE=abc -e MAX_PLAYERS=10 "$image" >/dev/null \
  || fail "the stubbed server did not start"

grep -qx -- "My Server" "$work/args.txt" || fail "server name not passed through"
grep -qx -- "3000" "$work/args.txt" || fail "invalid world size not replaced by the default"
grep -qx -- "10" "$work/args.txt" || fail "max players not passed through"
grep -qx -- "-1" "$work/args.txt" || fail "Rust+ should be off by default"
grep -q "keepstdin.so" "$work/preload.txt" || fail "keepstdin.so is not preloaded"
[ -f "$work/stdin.txt" ] || fail "close(0) was not ignored"
[ "$(cat "$work/.framework")" = "vanilla" ] || fail "framework marker not written"

echo "rust: ok"
