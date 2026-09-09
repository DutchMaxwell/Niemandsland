# Reference bundles, re-recorded at rules epoch 8 (2026-09-09)

The two arena reference bundles — `qbg_ref` (Grimdark Future) and `qag_ref` (Age of
Fantasy), 168 games each — were recorded on 2026-08-28. This document is the recording
contract for their epoch-8 successors and the record of what came out.

## 1. Why re-record

Issue #638. The core reads a record's rules epoch from `knobs.rules_epoch` in the act
header (`read_act_header` → `Knobs::rules_epoch`, `core/nml-core/src/acts.rs`), and an
**absent key reads back as `0`**. The GDScript arena recorder carried the number
(`AiActRecorder.rules_epoch`, the mirror of `CURRENT_RULES_EPOCH`) but never stamped it.

Consequence: every act header in the 2026-08-28 bundles reads back as epoch 0, so a replay
takes the pre-epoch branch of every `rule_on` gate — the dangerous-terrain gate in
`core/nml-core/src/dice.rs` is the one that surfaced it. Act 51 of a reference game
reproduces byte-exact only when the replay is forced to `rules_epoch: 7`. The gate's
200/200 replay check was therefore proving the **legacy** rules on the ground truth it
exists to defend.

The maintainer's decision was to **re-record, not re-stamp**: a header rewritten after the
fact would claim an epoch the game did not actually play under.

The stamp itself is PR **#844** (`fix(recorder): the arena record header carries
rules_epoch`). It is additive — a header written before the key still parses and still
reads `0`, so every older corpus keeps replaying exactly as it did.

## 2. Recording contract

Fixed **before** the first game, so that a later reader can tell whether a record belongs
to this bundle without dating the file.

| | |
|---|---|
| Recording sha | `f2935a61` (the PR #844 branch head) |
| Parent | `d4c3dfb5` — `main` at the time of recording |
| Merged as | `main` `268c1e0b` — PR #844's merge commit, so the recording sha stays reachable from `main` |
| Rules epoch | **8** (`CURRENT_RULES_EPOCH`, `core/nml-core/src/acts.rs`; mirrored by `AiActRecorder.rules_epoch`) |
| Encoder rule vocab | **7** (`data/encoder_rule_vocab_v1.json`, stamped as `knobs.rule_vocab_version`) |
| Army-book snapshot | `sha256 cc7d6c2633718067e62dc1c3cb04c4f327b8c51ce37b21e1731f5b5d5f332364`, generated `2026-08-28T16:14:42Z`, `source: snapshot` — the SAME pinned books as the 2026-08-28 bundles |
| Recorder | `tools/arena_match.gd`, `p1=planner_v0 p2=planner_v0`, `mission=duel`, `symmetric=1` |
| Seeds | `seed = dice_seed = 27…33` (7 per pairing/size), `layout_seed = seed + 500000` |
| Sizes | 1000 / 1500 / 2000 points per list |
| Pairings | 8 GF pairings (`farm` manifest builder for `qbg`) and 8 AoF pairings (`qag`), 3 sizes × 7 seeds each = 168 + 168 |
| Search knobs | `NML_TOP_K=2`, `NML_HORIZON=1` |
| Recorder env | `NML_REQUIRE_RULE_TEXT=1`, `NML_CAPTURE_ACTS=1`, act/node/dice/move/shot dumps on, `NML_NODE_DUMP_MAX=1000` |
| Game timeout | 5400 s (longest 2026-08-28 game: 3150 s) |
| Workers | 10 per box (16 vCPU, ~2.5 GB per game) |

Header knobs as stamped by this bundle (from the pilot record, verified before the fleet
ran):

```
cond_ap true | depth_discount 0.5 | dice "table" | engage_fold true | hero_attach true
horizon 1 | imagined_round_end true | playout_margin 0.02 | playout_rich true
rule_vocab_version 7 | rules_epoch 8 | seam_cast false | seam_spacing true | seat_mode 0
tail_cap_p1 0 | tail_cap_p2 0 | top_k 2
```

`rule_text_ok: true`, `rule_text_source: "snapshot"` on every record — under
`NML_REQUIRE_RULE_TEXT=1` a game whose army import fetched no rule text is refused before
`arena_*.json` is written, so it cannot enter the bundle silently.

### Digest rule

Record digests are taken over **basenames plus the recording sha**, never absolute paths.
The 2026-09-05 laptop/box divergence was exactly this: the digest hashed absolute army-list
paths (`/home/...` vs `/root/...`) and two byte-identical games disagreed.

A record's **raw bytes are not a stable identity** either. Every unit key in `acts.jsonl`
and `nodes.jsonl` is `<wall-clock>_<random>` — a per-process name — so two byte-exact
replays of the same game have different file digests. Measured on the same seed, recorded
twice on the same host: with the unit keys canonicalised both files are byte-identical, and
the `arena_*.json` differs in exactly one field, `duration_sec`. Any content hash over a
record must canonicalise the keys first.

### Output

New versioned directories. The 2026-08-28 bundles are read-only and are **not** touched:

```
selfplay_out/qbg_ref_e8/   168 game directories
selfplay_out/qag_ref_e8/   168 game directories
```

Each game directory holds `arena_<p1>_vs_<p2>_s<seed>_d<seed>.json`, `acts.jsonl`,
`nodes.jsonl`, `dice.jsonl`, `moves_calls.jsonl`, `shots.jsonl` (absent on a genuine
zero-volley game — the recorder creates it lazily) and `run.log`.

## 3. Recording run

Three 16-vCPU boxes, 10 recorder workers each, 2026-09-09 08:23–11:20.

| | rows | recorded | failed |
|---|---|---|---|
| box 3 | 111 | 111 | 0 |
| box 4 | 113 | 113 | 0 |
| box 5 | 112 | 112 | 0 |
| **total** | **336** | **336** | **0** |

Every row landed in exactly one box's partition. The partitions were built explicitly and
checked for disjointness and full coverage before the runners started — not left to the
runner's "skip an already recorded directory" guard, which protects against a re-run but not
against two runners racing on one game.

Per bundle, summed over the three boxes:

| bundle | games |
|---|---|
| `qbg_ref_e8` | 63 + 49 + 56 = **168** |
| `qag_ref_e8` | 48 + 64 + 56 = **168** |

Rows were ordered longest-first by the measured duration of the same game on 2026-08-28
(the two bundles sum to 79.3 CPU-hours, and a 3150 s game that starts last adds its whole
length to the wall clock), and balanced across the boxes to 26.4 / 26.4 / 26.3 CPU-hours.

## 4. Replay floor

`dice_gate.py --movement table`, run on each box against the games it recorded, on the
recording sha, then summed. **A STREAM is the floor**: seed a fresh tray with the game's own
`dice_seed`, walk `dice.jsonl` in file order and compare every face the twin returns against
the face the table recorded — exact, including the count.

| | `qbg_ref_e8` | `qag_ref_e8` |
|---|---|---|
| **A STREAM** | **168/168 games** (8888 rolls) | **168/168 games** (6971 rolls) |
| B TALLY | 371/640 activations | 561/846 |
| C NEXT | 633/949 activations | 917/1344 |
| C POS | 357/949 activations | 493/1344 |

Every one of the 336 records replays its recorded dice stream byte-exact on the sha it was
recorded on.

B and C are not a pass/fail on this bundle and never have been — they measure how far the
Rust twin's resolution and positions still sit from the table's. The like-for-like
comparison against the 2026-08-28 bundle exists only for `qbg_ref/table`, which was
`B 403/743`, `C NEXT 580/1003`, `C POS 458/1003`:

- B TALLY 54.2 % → **58.0 %**
- C NEXT 57.8 % → **66.7 %**
- C POS 45.7 % → **37.6 %**

Two of the three improve and one falls, so this is not a clean "the epoch stamp made the
gate better" story and should not be told as one. Note also that the denominators moved
(743 → 640 comparable activations): these are the same 168 pairings and seeds, but the games
themselves played out differently under epoch 8, so the two corpora are not two samples of
one distribution. The new numbers are the new floor; they are not a delta.

## 5. Position-parity harness

The parity pin is re-recorded in the same change, on the same sha the bundles were recorded
against — the parity plan's "PR 7 re-records the pin", one wave later.

### The new pin

`test/fixtures/position_parity/baseline.json`, recorded with `tools/position_parity.py
--runs 3 --record-baseline` on a host with nothing else running (the tool refuses to measure
while another Godot process is up).

| | |
|---|---|
| `source_revision` | `268c1e0b` (PR #844's merge, i.e. the recording sha on `main`) |
| previous pin | `bef020cf` |
| `fixture_sha256` | `0b5bb72c…` — **unchanged**; the fixture set is the same, only the measurement is new |
| determinism | `runs=3 identical=true timing_excluded=true sha256=548f872d…` |

Measurement on `main`:

```
models:     n=1702  equal=198  within_0.5in=1697  beyond_0.5in=5  declined=0
formation:  n=168   equal=168  recorded_equal=168  within_0.5in=168
per run:    n=304 positions, 0 in every failure bucket
            (base_shapes, boxed_escape, caught_panic, charge_final_placement,
             charge_snap, coherency_hold, parse_error, skirmish_chain,
             whole_unit_shorten)
```

`main` flags **0** against this pin by construction: the tool writes the baseline out of the
same measurement it just took. That is arithmetic, not evidence, and it is not re-run as a
separate pass.

### `#776` against the new pin

PR #776 (`parity-frame 4/7`, head `0da12d82`) measured against the pin above, one run — the
pin needs three identical runs by rule, a comparison needs one.

**One regression: `recorded-037: accepted model delta increased`.**

Against the previous `bef020cf` pin the 2026-09-08 measurement flagged three positions
(`recorded-026`, `-037`, `-128`). Two of those were `main`'s own drift from that pin and are
absorbed by re-recording it; `recorded-037` is the one that belongs to #776.

How far anything actually moved, pin vs #776, as the largest change of any one model's
accepted delta:

| case | max |Δ| change | reading |
|---|---|---|
| `recorded-128` | 0.0304 in | geometric, does **not** flag |
| `recorded-037` | 0.0091 in | geometric, **flags** |
| `recorded-026` | 0.000004 in | float noise |
| 10 further cases | ≤ 0.000003 in | float noise |

291 of 304 positions do not move at all. On `recorded-037` the flagged increase is 0.0083 in
(0.21 mm) on one of 21 models; four ULPs of the board's f32 inch scale — the accepted slack
from PARITY_FP6 — are 3.05e-5 in, so this is roughly 280× the slack and a real geometric
change, not rounding.

**A gate asymmetry worth knowing about:** `recorded-128` moves 3.3× further than
`recorded-037` and passes silently, because the regression check only fires when an
*accepted* delta **increases**. A position that moves a long way in the forgiving direction
— toward the table, or from beyond-tolerance to within it — leaves no trace in the verdict.
The gate as written answers "did anything get worse", not "did anything move".
