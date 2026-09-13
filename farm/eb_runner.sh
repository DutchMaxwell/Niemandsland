#!/usr/bin/env bash
# E-B GRADER HEADROOM — pre-registered runner (the dry run is the deliverable).
#
# E-B (planning/PLAN.md "Pre-registered probes"; RSI_RESTART_DESIGN_2026-09-13.md R6):
# same planner, same candidate sets, but the GRADER is replaced by a re-simulation
# oracle — each finalist candidate is played to game end and scored by its actual
# marker delta. Bar: an oracle grader that gains < 5 points over CHIMAERE on the
# 6-faction thermometer proves the grader is not the bottleneck. This runner
# composes the plan, writes the pre-registration + noise-floor statement BEFORE
# the first game, plays the games, and stamps core sha + rules epoch into SCORE.
#
# It costs nothing while DRY_RUN is unset/1: the dry run prints the composed
# command, the sample plan (n, blocks, seeds, seats), the projected box-hours/EUR
# and the projected standard error, and writes NOTHING. DRY_RUN=0 runs the games.
# NO BOX IS PROVISIONED, STARTED OR SPENT ON BY THIS FILE.
#
# Usage:
#   farm/eb_runner.sh                       # DRY_RUN=1, full 6F plan
#   DRY_RUN=0 OUT=... farm/eb_runner.sh     # real run
#   DRY_RUN=0 SMOKE=1 farm/eb_runner.sh     # laptop smoke, at most 10 games
#
# Env: OUT, PAIRS, N_BLOCKS, SEED_LO, SEED_HI, WORKERS, DRY_RUN, SMOKE, CKPT2,
#      BAR, SITE, NETLAB_DIR, BLOCK_SD, EUR_PER_BOX_HOUR, PY.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OUT="${OUT:-$HOME/selfplay_out/eb_oracle}"
PAIRS="${PAIRS:-$HOME/selfplay_out/residual_600/prescreen_pairs.tsv}"
N_BLOCKS="${N_BLOCKS:-150}"
SEED_LO="${SEED_LO:-}"
SEED_HI="${SEED_HI:-}"
WORKERS="${WORKERS:-4}"
DRY_RUN="${DRY_RUN:-1}"
SMOKE="${SMOKE:-0}"
BAR="${BAR:-5.0}"
SITE="${SITE:-$HOME/.cache/nml-main/site}"
SHA_FILE="$HOME/.cache/nml-main/SHA"
PIN_FILE="$HOME/nml-mission/farm/YARDSTICK_SHA"
NETLAB_DIR="${NETLAB_DIR:-$HOME/nml-mission/netlab}"
PY="${PY:-$HOME/venvs/netlab-fixed/bin/python}"
REF_CKPT_DEFAULT="$HOME/nml-mission/netlab/nets/gen2b/c10a_gen2b.pt,$HOME/nml-mission/netlab/nets/gen2/c7_gen2only.pt"
if [ "${CKPT2:-}" = "off" ]; then
  REF_CKPT=""                       # net-free hand grader (laptop smoke / blocked-ckpt fallback)
elif [ -n "${CKPT2:-}" ]; then
  REF_CKPT="$CKPT2"
else
  REF_CKPT="$REF_CKPT_DEFAULT"      # CHIMAERE, the real E-B reference seat
fi
BLOCK_SD="${BLOCK_SD:-0.1827}"                 # measured 6F within-arm block sd (ARENA_RESCORE 2026-09-13)
EUR_PER_BOX_HOUR="${EUR_PER_BOX_HOUR:-0.25}"   # cx43 target, per the AI_STATE_AUDIT 2026-09-13
ORACLE_LABEL="token_oracle"
REF_LABEL="token_value_v1"

MAX_GAMES=0
[ "$SMOKE" = "1" ] && MAX_GAMES=10

# --- 1) core parity: the pin and the built wheel must agree --------------
[ -f "$SHA_FILE" ] || { echo "REFUSED: no built-core SHA at $SHA_FILE" >&2; exit 2; }
[ -f "$PIN_FILE" ] || { echo "REFUSED: no yardstick pin at $PIN_FILE" >&2; exit 2; }
CORE_SHA="$(head -1 "$SHA_FILE")"
PIN_SHA="$(head -1 "$PIN_FILE")"
RULES_EPOCH="$(PYTHONPATH="$SITE" "$PY" -c 'import nml_core; print(nml_core.CURRENT_RULES_EPOCH)')"
if [ "$CORE_SHA" != "$PIN_SHA" ]; then
  echo "REFUSED: built core $CORE_SHA != yardstick pin $PIN_SHA (PIN_MISMATCH)" >&2
  exit 2
fi

# --- 2) compose the plan: one seed = one block of 4 games ----------------
PLAN_ALL="$(PYTHONPATH="$SITE" "$PY" "$SCRIPT_DIR/eb_oracle.py" plan \
  --pairs "$PAIRS" --out - --seed-lo "${SEED_LO:-0}" --seed-hi "${SEED_HI:-999999999}" \
  --max-games "$MAX_GAMES")"
PLAN_STATS="$(printf '%s\n' "$PLAN_ALL" | grep '^plan_')"
PLAN_ROWS="$(printf '%s\n' "$PLAN_ALL" | grep -v '^plan_')"
BLOCKS="$(printf '%s\n' "$PLAN_STATS" | sed -n 's/^plan_seeds=//p')"
GAMES="$(printf '%s\n' "$PLAN_STATS" | sed -n 's/^plan_games=//p')"
if [ -z "$GAMES" ] || [ "$GAMES" = "0" ]; then
  echo "REFUSED: empty plan (check PAIRS/SEED_LO/SEED_HI)" >&2
  exit 2
fi

# --- 3) projections: SE, resolvable effect, box-hours, EUR ----------------
read -r SE_PTS EFFECT_PTS < <(awk -v sd="$BLOCK_SD" -v k="$BLOCKS" 'BEGIN { se=sd/sqrt(k); printf "%.2f %.2f\n", 100*se, 100*2.8*se }')
K_REQ="$(awk -v sd="$BLOCK_SD" -v bar="$BAR" 'BEGIN { k=(2.8*sd*100/bar)^2; printf "%d", (k==int(k)?k:int(k)+1) }')"
BOX_HOURS="$(awk -v g="$GAMES" 'BEGIN { printf "%.2f", g/600.0 }')"
EUR="$(awk -v h="$BOX_HOURS" -v e="$EUR_PER_BOX_HOUR" 'BEGIN { printf "%.2f", h*e }')"

prereg() {
  cat <<EOF
E-B GRADER HEADROOM — PRE-REGISTRATION (written before the first game)
bar: oracle grader gain >= ${BAR} points over CHIMAERE on the 6-faction thermometer (UNCHANGED).
sample plan: ${BLOCKS} blocks x up to 4 games = ${GAMES} games; each seed is one block,
  every (dice, oracle seat) pair present, so seats are swapped and seeds paired.
statistic: block-mean win share from the oracle's point of view, ties carry 0.5;
  gain = score - 50.0 points.
oracle noise floor (ADDED 2026-09-13, the amendment): each finalist candidate is
  decided by up to 7 stochastic full playouts per branch (3 minimum, escalating by 2
  while the mean marker delta stays inside the margin), against the value-net re-rank
  of the reference seat. A SINGLE playout per candidate is refused as a verdict: its
  decision noise is unbounded and shared inside a block, so a NULL could be pure
  sampling noise. The fixed 3-7 floor plus the block structure is the error budget:
  projected block sd ${BLOCK_SD} (measured 6F within-arm, ARENA_RESCORE 2026-09-13)
  -> projected SE ${SE_PTS} points at ${BLOCKS} blocks.
  effect resolvable at 80% power: ${EFFECT_PTS} points (one-sample, two-sided).
  bar ${BAR} points resolvable at ${BLOCKS} blocks: $(awk -v e="$EFFECT_PTS" -v b="$BAR" 'BEGIN{print (e<=b)?"YES":"NO"}') (need K >= ${K_REQ} blocks; SE falls with 1/sqrt(K)).
projected cost: ${BOX_HOURS} box-hours ~ ${EUR} EUR (cx43 at ${EUR_PER_BOX_HOUR} EUR/box-hour);
  cpx62 ceiling ~ 4x. Laptop smoke (<= 10 games) is free.
core: built_sha=${CORE_SHA}  yardstick=${PIN_SHA}  rules_epoch=${RULES_EPOCH}
EOF
}

COMPOSED="PYTHONPATH=$SITE $PY $SCRIPT_DIR/eb_oracle.py play <slice> --tsv <slice.tsv> --repo $REPO_DIR --bank \$HOME/selfplay_out/terrain_bank --oracle-label $ORACLE_LABEL --ref-label $REF_LABEL ${REF_CKPT:+--ckpt2 $REF_CKPT }--top-k 10 --horizon 3"

# --- 4) dry run: print everything, write nothing --------------------------
if [ "$DRY_RUN" != "0" ]; then
  echo "=== E-B DRY RUN (writes nothing) ==="
  echo "composed command (one per worker slice):"
  echo "  $COMPOSED"
  echo
  prereg
  echo
  echo "sample rows (first 6):"
  printf '%s\n' "$PLAN_ROWS" | head -6
  echo
  echo "DRY RUN: NOTHING was written. Set DRY_RUN=0 to play."
  exit 0
fi

# --- 5) real run: pre-registration first, then play, then SCORE -----------
mkdir -p "$OUT"
prereg > "$OUT/PREREGISTRATION.txt"
printf '%s\n' "$PLAN_ROWS" > "$OUT/plan.tsv"
echo "E-B started $(date -Is) games=$GAMES workers=$WORKERS core_sha=$CORE_SHA epoch=$RULES_EPOCH" > "$OUT/STATUS"

PIDS="$OUT/eb_pids.txt"
: > "$PIDS"
for i in $(seq 0 $((WORKERS - 1))); do
  SLICE="$OUT/slice_$i.tsv"
  awk -v w="$WORKERS" -v i="$i" 'NR % w == i' "$OUT/plan.tsv" > "$SLICE"
  PYTHONPATH="$SITE" NETLAB_DIR="$NETLAB_DIR" \
    nohup "$PY" "$SCRIPT_DIR/eb_oracle.py" play "$OUT" --tsv "$SLICE" \
      --repo "$REPO_DIR" --bank "$HOME/selfplay_out/terrain_bank" \
      --oracle-label "$ORACLE_LABEL" --ref-label "$REF_LABEL" \
      ${REF_CKPT:+--ckpt2 "$REF_CKPT"} --top-k 10 --horizon 3 \
      >> "$OUT/worker_$i.log" 2>&1 &
  echo $! >> "$PIDS"
done
echo "workers launched; waiting (blocking)…"
for pid in $(cat "$PIDS"); do wait "$pid"; done

COUNT="$(ls "$OUT"/arena_*.json 2>/dev/null | wc -l)"
echo "all done $(date -Is) count=$COUNT/$GAMES" >> "$OUT/STATUS"

PYTHONPATH="$SITE" "$PY" "$SCRIPT_DIR/eb_oracle.py" score "$OUT" \
  --oracle-label "$ORACLE_LABEL" --ref-label "$REF_LABEL" --bar "$BAR" \
  --core-sha "$CORE_SHA" --rules-epoch "$RULES_EPOCH" --pin-sha "$PIN_SHA" \
  | tee "$OUT/SCORE"
