#!/usr/bin/env bash
# Acceptance run: real WINDOWED instances of <worktree> walk the player's paths (test/acceptance/acceptance_driver.gd).
# Usage: tools/acceptance/run_acceptance.sh <worktree> [--live-relay] [--scenarios "1 2 3 3c 4"] [--out DIR]
# Each instance gets its own XDG_DATA_HOME (user://) and nothing else. Online scenarios use a local relay from
# <worktree>/relay unless --live-relay (the public relay, private rooms). `ss -tin` samples the relay flow every 2 s.
set -uo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
wt=$(cd "${1:?usage: run_acceptance.sh <worktree> [--live-relay] [--scenarios LIST] [--out DIR]}" && pwd); shift
live=0; scen="1 2 3 3c 4"; out=""
while [ $# -gt 0 ]; do case $1 in --live-relay) live=1;; --scenarios) scen=$2; shift;; --out) out=$2; shift;;
	*) echo "unknown argument: $1" >&2; exit 2;; esac; shift; done
GODOT=${GODOT:-godot}; rev=$(git -C "$wt" rev-parse --short HEAD)
out=${out:-${ACCEPT_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/niemandsland-acceptance}/$(date +%Y%m%d-%H%M%S)-$rev}; mkdir -p "$out"
# The desktop may be shared with a player: never open test windows next to a running shipped build.
if pidof Niemandsland.x86_64 >/dev/null; then echo "a Niemandsland build is running: no windowed run now" >&2; exit 3; fi
# The driver comes from this checkout; a worktree under test gets an untracked copy.
[ "$here" -ef "$wt" ] || { mkdir -p "$wt/test/acceptance"; cp "$here"/test/acceptance/acceptance* "$wt/test/acceptance/"; }
if [ ! -d "$wt/.godot" ]; then
	XDG_DATA_HOME=$out/xdg-import XDG_CONFIG_HOME=$out/xdg-import XDG_CACHE_HOME=$out/xdg-import \
		"$GODOT" --headless --editor --quit --path "$wt" > "$out/import.log" 2>&1
fi
pids=(); trap 'for p in "${pids[@]}"; do kill -- "-$p" 2>/dev/null; done' EXIT
if [ $live = 1 ]; then
	relay=wss://niemandsland-relay.fly.dev   # both address families: the client may take either
	filter=$(getent ahosts niemandsland-relay.fly.dev | awk '!s[$1]++{printf "%sdst %s", n++ ? " or " : "", ($1 ~ /:/ ? "[" $1 "]" : $1)}')
else
	port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
	setsid python3 "$wt/relay/relay_server.py" --host 127.0.0.1 --port "$port" > "$out/relay.log" 2>&1 & pids+=($!)
	relay=ws://127.0.0.1:$port; filter="dport = :$port"; sleep 2
fi
setsid bash -c "while :; do echo \"# \$(date +%T)\"; ss -tinH state established '( $filter )'; sleep 2; done" > "$out/ss.log" 2>&1 & pids+=($!)
# One instance: role, scenario, window x-position. Windowed (NML_WINDOWED) so two fit side by side.
launch() {
	local d=$out/s$2; mkdir -p "$d/xdg-$1"
	XDG_DATA_HOME=$d/xdg-$1 NML_WINDOWED=1 setsid "$GODOT" --path "$wt" --resolution 1280x720 --position "$3,60" \
		res://test/acceptance/acceptance.tscn -- --role "$1" --scenario "$2" --out "$d" --relay "$relay" > "$d/$1.log" 2>&1 &
	pids+=($!); echo $!
}
for s in $scen; do
	case $s in 1|4) group=$(launch solo "$s" 0);; *) group="$(launch host "$s" 0) $(launch guest "$s" 1290)";; esac
	end=$(( $(date +%s) + ${ACCEPT_TIMEOUT_S:-600} ))
	for p in $group; do
		while kill -0 "$p" 2>/dev/null && [ "$(date +%s)" -lt "$end" ]; do sleep 1; done
		kill -0 "$p" 2>/dev/null && { echo "| s$s | FAIL | driver timed out, instance $p killed |" >> "$out/s$s/timeout.md"; kill -- "-$p"; }
	done
	# No silent pass: every instance must have written its rows, and its log must hold no script error.
	for f in "$out/s$s"/*.log; do r=$(basename "$f" .log)
		[ -f "$out/s$s/$r.md" ] || echo "| s$s $r | FAIL | no checkpoint rows (driver did not finish) |" >> "$out/s$s/zz.md"
		n=$(grep -c "SCRIPT ERROR" "$f"); [ "$n" = 0 ] || echo "| s$s $r | FAIL | $n SCRIPT ERROR line(s) in $r.log |" >> "$out/s$s/zz.md"
	done
done
{
	echo "# Acceptance run $rev ($([ $live = 1 ] && echo live || echo local) relay) $(date '+%F %T')"
	echo; echo "| checkpoint | result | evidence |"; echo "|---|---|---|"
	for s in $scen; do cat "$out/s$s"/*.md 2>/dev/null; done
	echo; echo "## Main-loop stalls (frame gaps > 2 s)"; cat "$out"/s*/*.stalls 2>/dev/null
	echo; echo "## Relay flow (ss -tin every 2 s): samples, max lastrcv ms, max rto ms, max retrans, max Recv-Q"
	awk '/^#/{n++} /^[0-9]/{q=$1>q?$1:q} {for(i=1;i<=NF;i++){split($i,a,":"); if(a[1]=="lastrcv"&&a[2]>lr)lr=a[2];
		if(a[1]=="rto"&&a[2]>rto)rto=a[2]; if(a[1]=="retrans"){split(a[2],r,"/"); if(r[2]>rt)rt=r[2]}}}
		END{printf "%d samples, lastrcv %d, rto %d, retrans %d, Recv-Q %d\n", n, lr, rto, rt, q}' "$out/ss.log"
	echo; echo "## Game tx/rx lines (last 3 per instance)"
	for f in "$out"/s*/*.log; do echo "- ${f#$out/}: $(grep -c '\[Relay\] tx' "$f") lines"; grep '\[Relay\] tx' "$f" | tail -3 | sed 's/^/    /'; done
} > "$out/report.md"
echo "report: $out/report.md"; ! grep -q "| FAIL |" "$out/report.md"
