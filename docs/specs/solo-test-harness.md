# Solo test harness, stage A

Status: proposed. Stage B is scheduled after the table resolvers are deleted (see "Out of scope").

## Goal

Tests set up a solo game through one public test facade, `SoloHarness`, instead of writing
`main.gd`'s private members. After stage A no test outside `test/support/` writes
`_ensure_solo_controller`, `_solo_batch`, `_solo_fast` or `_solo_auto_saves`, and a CI gate keeps
the number of test accesses to `main.gd` private members from rising again.

Why: on `main` today 457 test files make 3,733 accesses to `main.gd` private members (`_main._...`).
`_ensure_solo_controller` alone is called 373 times in 334 files, `_solo_batch` is written 338 times
in 287 files. Every extraction from `main.gd` (26k lines) breaks those tests although no behaviour
changes. With the facade, moving that code touches one file.

Done when: tickets 1-8 below are merged, the gate is green on `main`, and the gate's baseline has
no entry for the four setup members.

## Out of scope

- Stage B: tests that call rule steps directly (`_run_ai_shooting` 52x, `_solo_melee_strike_phase`
  42x, `_solo_morale_test` 34x, ...). Many of those functions leave `main.gd` when the table
  resolver is deleted; migrating their callers first would be done twice. Stage B gets its own spec
  after that deletion.
- `_solo_core_ai_h` (163x) and `_solo_target_mode` (108x): door and player-input state, stage B.
- Any change to `main.gd` or other production code. Stage A changes `test/`, `tools/` and the CI
  workflow only.
- Multiplayer tests (`test/mp/`), which do not use a solo game.

## Terms

From [`docs/glossary.md`](../glossary.md): table, rules core, door, volley, battle log, digest.
New terms (proposed for the glossary with ticket 1):

| Term | Meaning |
| --- | --- |
| test facade | A class under `test/support/` that is the only place tests touch a production class's internals; tests call the facade. |
| `SoloHarness` | The test facade for a solo game on a loaded `main.tscn`: slots, pacing and dice modes. |
| private-access gate | The CI check that counts test accesses to `main.gd` private members per member; a count may fall, never rise. |

## Module structure

One deep module, `test/support/solo_harness.gd` (`class_name SoloHarness`, static functions, no
state of its own):

```gdscript
## Start a solo game on a loaded main scene: AI slots, the human slot, the controller ready.
static func start(main: Node, ai_slots: Array[int] = [2], human_slot := 1) -> SoloController
## Instant dice and no pacing holds (headless sweeps); implies fast.
static func instant(main: Node, on := true) -> void
## Shorter pacing holds and no move animation.
static func fast(main: Node, on := true) -> void
## Saves roll straight to the tray without the save dialog.
static func auto_saves(main: Node, on := true) -> void
```

`start` covers the setup block that recurs in the suites today (`solo_ai_slots = {..}`,
`_ensure_solo_controller()`, `solo_controller.ai_slot`, `solo_controller.human_slot`); a test that
needs more (for example `last_move_paths = []`) keeps that one line after `start`. The four
functions are the whole interface; nothing else is added in stage A.

The private-access gate is `tools/test_private_access_gate.sh` with the baseline
`tools/test_private_access_baseline.txt` (one line per member: `name count`), built like
`tools/clippy_gate.sh`: `--record` rewrites the baseline on purpose; a normal run fails when a
member's count rises or a new member appears, and prints the members whose count fell.
`test/support/` is excluded from the count.

## Acceptance criteria and tests

- `test/support/solo_harness_test.gd` drives a loaded `main.tscn` through the facade only and
  checks the observable result: `start` gives a controller whose `ai_slot` / `human_slot` are the
  requested ones and an AI unit activates; `instant` makes a volley's dice land without waiting
  frames; `auto_saves` resolves a save without a dialog. Each case is shown able to fail (planted
  fault red, restored green).
- The gate is shown able to fail: one added `_main._solo_batch = true` in a test file turns it red.
- Every migration PR: the touched suites have the same number of test cases and the same number of
  passing cases before and after, `SCRIPT ERROR` 0 in every log, and the PR lowers the baseline.
- No file outside `test/`, `tools/` and `.github/workflows/` changes.

## Risks

- Two-way door, small blast radius: only tests and tooling change; reverting a PR restores the old
  setup lines.
- A migration could silently change what a test sets up (for example drop `human_slot`). Guard: the
  same case and pass counts per suite, and `start` sets exactly the lines it replaces.
- Merge conflicts with test PRs of the deletion work (`test/one_core/`). Guard: a migration batch
  skips files that an open pull request touches and names them in its body; a later batch takes them.
- The workflow change (ticket 2) needs a maintainer to merge it.

## Tickets

1. `SoloHarness` and its test (`test/support/solo_harness.gd`, `solo_harness_test.gd`), plus the
   three glossary rows. No dependency.
2. The private-access gate: script, baseline recorded on `main`, one job in
   `.github/workflows/hygiene.yml`. No dependency; parallel to 1 in its own worktree.
3. Migrate `test/one_core/` files A-C (setup block + the three mode writes). After 1 and 2.
4. Migrate `test/one_core/` files D-K. After 1 and 2; parallel to 3 (different files).
5. Migrate `test/one_core/` files L-Z. After 1 and 2; parallel to 3 and 4.
6. Migrate `test/e2e/`. After 1 and 2; parallel to 3-5.
7. Migrate `test/v36/` and `test/parity/`. After 1 and 2; parallel to 3-6.
8. Migrate the rest of `test/` (top-level suites, `test/acceptance/`), then confirm the baseline has
   no entry for the four setup members. After 3-7.

Each migration ticket: at most about 30 files per pull request (split a ticket into a and b when it
is larger); each lowers the gate baseline with `--record` in the same pull request. Tickets 3-7
rebase onto `main` before pushing because each lowers the same baseline file.
