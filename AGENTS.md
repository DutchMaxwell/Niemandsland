# AGENTS.md - a guide for contributors and coding agents

This file is for anyone who changes code in this repository: a human contributor or an automated
coding agent. It is tool-neutral on purpose. It summarises where things live, how the repository
builds and tests itself, and the rules a change has to meet. The longer documents it links to are
the authority; when this file and one of them disagree, the linked document wins and this file is
the bug.

## What the project is

Niemandsland is a fan-made digital tabletop for miniature wargames, with first-class support for
the OnePageRules game systems (Grimdark Future, Age of Fantasy and their skirmish / regiments
variants). It is an open-source, non-commercial project under the MIT licence.

- The **table** is a Godot 4.6 game written in GDScript: 3D board, miniatures, measuring, army
  import, multiplayer through a small relay, save files.
- The **rules core** is a Rust crate that resolves the rules for engine play (solo against the
  built-in opponent, automatic resolution) and runs the opponent's search.
- In human-vs-human play the table measures, shows and synchronises; the players apply the rules.
  In engine play the core applies them, rules-exact and fully logged.

Start with [`README.md`](README.md), [`CONTRIBUTING.md`](CONTRIBUTING.md) and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Architecture map

| Path | What it is |
|---|---|
| `project.godot`, `scenes/` | The Godot project. The main scene is `scenes/startup_menu.tscn`; the table is `scenes/main.tscn`. |
| `scripts/` | The GDScript game. `scripts/main.gd` is the top-level controller that wires subsystems and UI (large; see "Known structure debt"). |
| `scripts/solo/` | The engine-play side of the table: solo controller, turn manager, the GDScript battle simulation, recorders, rule registries. |
| `scripts/solo/core_activation.gd` | The **door** between the table and the rules core: every table path that may resolve through the core asks its predicates first, and the kill switch `NML_ONE_CORE_ACTIVATION=0` restores the table path. |
| `core/` | One Cargo workspace (`core/Cargo.toml`) with three crates. |
| `core/nml-core/` | The rules port and the search (pure Rust, no Godot). `src/acts.rs` holds the rules epochs. |
| `core/nml-core-godot/` | The GDExtension that exposes the core to Godot as `NmlCore`. |
| `core/nml-core-py/` | Python bindings (built with maturin) for tools, training and replay gates. |
| `core/nml-core/src/boardgen/` | The seeded board generator: the layout grid (cells, levels, ladders) that is the gameplay truth of a generated board, reached from Godot as `NmlCore.boardgen_layout`. |
| `scripts/boardgen_*.gd` | The Godot side of generated boards: greybox, theme, mood, town kit and props. |
| `scripts/boardgen_dress*.gd` | The dressing of a generated ruin-town board: authored modules drawn over the grid under fixed honesty rules (see [ADR 0003](docs/adr/0003-generated-board-dressing.md)). |
| `shaders/` | Spatial and sky shaders, including the dressing shaders `shaders/ruintown_dress*.gdshader`. |
| `assets/` | Manifests and small bundled assets. Large 3D assets are delivered at runtime from a CDN (see [`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md)). `assets/solo/` holds the rule / spell mechanics and missions the core reads; `assets/ruintown_dress.json` is the dressing kit manifest. |
| `test/` | gdUnit4 suites (`*_test.gd`), collected recursively. |
| `test/one_core/` | Door and parity suites between the table and the core. |
| `test/e2e/` | End-to-end suites that boot the real `scenes/main.tscn` (shared harness `test/e2e/e2e_boot.gd`). |
| `test/fixtures/` | Fixtures, including the core goldens. |
| `tools/` | Developer and CI tools (Python, shell, GDScript probes). `tools/ci/` holds the CI helpers; `tools/clippy_gate.sh` and `tools/epoch_gate_check.py` are gates. |
| `relay/` | The multiplayer WebSocket relay (Python). |
| `addons/gdUnit4/` | The vendored test framework. |
| `docs/` | Technical documentation; [`docs/README.md`](docs/README.md) is the index, [`docs/adr/`](docs/adr/README.md) the architecture decision records. |

OnePageRules content (army books, rule text, AI opponent lists) is **never** committed; it is
delivered at runtime. The `Repo Hygiene` workflow enforces this.

## Build and test

These are the commands CI runs (`.github/workflows/rust.yml`, `.github/workflows/build.yml`).
Run the ones that cover your change before you push. The Rust toolchain is pinned by
`rust-toolchain.toml` at the repo root, so run cargo from the repo root with `--manifest-path`.

### Rust core

```bash
# lint gate: fails only when a clippy lint count rises or a new lint appears
bash tools/clippy_gate.sh
# nml-core tests (CI builds tests on the release profile without LTO)
CARGO_PROFILE_RELEASE_LTO=false CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 \
  cargo test --manifest-path core/nml-core/Cargo.toml --release
# the Godot extension
cargo build --manifest-path core/nml-core-godot/Cargo.toml --release
# the Python bindings: check, build the wheel, install it, run its tests
cargo check --manifest-path core/nml-core-py/Cargo.toml
pip install maturin pytest numpy pytest-timeout
maturin build --release -m core/nml-core-py/Cargo.toml -o dist
pip install dist/*.whl
PYTHONPATH=core/nml-core-py/python python3 -m pytest core/nml-core-py/tests/python -q -x --timeout 900
# the tools' own tests
python3 -m pytest tools -q --timeout 600
```

Clippy is a differential gate on purpose, never `-D warnings`: some findings would change
parity-critical constants if "fixed" (see the header of `tools/clippy_gate.sh`). A rules PR that
changes the rules epoch is also checked by `tools/epoch_gate_check.py` (see
[ADR 0002](docs/adr/0002-rules-epochs.md)). A change to a Rust crate builds and tests all three.

### Godot table

The table needs the built core before its tests run:

```bash
cargo build --release --features onnx-tract --manifest-path core/nml-core-godot/Cargo.toml
bash core/install_gdextension.sh
# headless import: generates .godot/, registers class_names, compile-checks every script
godot --headless --editor --quit --path .
# all suites; -c keeps going after a failure so the report shows every failing case
godot --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -c -a res://test
# one suite
godot --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -c -a res://test/boardgen_dress_rules_test.gd
```

CI splits the suites into time-balanced shards (`tools/ci/run_shard_group.sh`,
`tools/shard_assign.py`) and checks that every shard printed its summary and ran every suite it
owns. Pitfalls:

- **"Identifier not declared" after a new `class_name`.** gdUnit resolves classes from the import
  cache. After you add a `class_name` or pull work that does, a stale cache aborts with
  `Identifier "Foo" not declared` for a class that exists, or runs an old method count.
  Re-run the headless import, then the suite.
- `--ignoreHeadlessMode` is required; without it gdUnit exits with code 103.
- A suite that fails to parse can report "No test cases found" and exit 0. Grep the output for
  `SCRIPT ERROR` / `Parse Error` (a German-locale Godot prints `Fehler bei`) on every run.
- The import and the unit suites do not compile scene-only scripts such as `scripts/main.gd`;
  only `test/e2e/` boots `main.tscn`. See the scene smoke gate in
  [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

### Relay

```bash
cd relay && pip install -r requirements-dev.txt && python -m pytest -q
```

## Coding standards (summary)

The full standard is [`docs/CODING_STANDARDS.md`](docs/CODING_STANDARDS.md). The points most
often missed:

- **English** everywhere: identifiers, comments, commit messages, docs.
- **Units.** Rules and the API are in **inches** on the table; the Godot world is in **metres**
  (1 Godot unit = 1 m, `INCHES_TO_METERS = 0.0254`); miniature bases are in millimetres.
  Document the unit of every numeric parameter.
- **Defensive checks.** Validate arguments, early-return on expected-empty input, skip invalid
  elements, report errors loudly (`push_error` / `push_warning`) instead of a silent default.
- **Every rule value cites its source**: the rulebook or army book and page next to the
  constant that encodes it, and rules values are named constants.
- **Every applied rule writes a battle-log line** that names the rule (exact rule-name compare).
  A silent rule is a bug.
- Prefer typed data objects over loose dictionaries; MultiMesh and pooling over many nodes.

## Rules-engine principles

- **Rulebook parity.** The core is the rules authority for engine play. Dice, rule-determined
  state and the legality of the result follow the rulebook on both sides; free choices are the
  core's. See [ADR 0001](docs/adr/0001-rulebook-parity.md) and
  [`docs/one_core/PARITY_RULING.md`](docs/one_core/PARITY_RULING.md).
- **Rules epochs.** A change to a recorded rules outcome is gated by a frozen `EPOCH_<n>_<NAME>`
  constant through `rule_on`, so every recorded game replays byte-identically at its stamp. See
  [ADR 0002](docs/adr/0002-rules-epochs.md).
- **Generated boards.** The layout grid is the gameplay truth; the dressing only draws it. See
  [ADR 0003](docs/adr/0003-generated-board-dressing.md) and
  [ADR 0004](docs/adr/0004-dressing-materials-and-kit-manifest.md).

## Pull requests

- **One concern per PR**, small diffs. A refactor does not ride along with a fix.
- **A new check must be shown able to fail**: plant the fault, show it red, restore it, show it
  green, and say so in the PR body. A test that never failed proves nothing.
- **Never bypass hooks** (`--no-verify`) and never force-push a shared branch.
- **No generated or private files**: no build outputs, reports, caches, local notes, or tool
  configuration of your own environment. Stage files by path.
- **Public-repo hygiene**: no personal data (names, e-mail addresses, home paths, machine names),
  no secrets, no OnePageRules content. The `Repo Hygiene` workflow checks part of this; the rest
  is on the author.
- CI must be green. A PR touching `.github/workflows/` needs a maintainer to merge it.

### Commit convention

Write commit subjects and PR titles as `type(scope): subject`, with `type` one of `feat`, `fix`,
`refactor`, `test`, `docs`, `chore`, and an optional scope such as `core`, `solo`, `boardgen`,
`mp`. Example: `fix(core): a volley keeps the declared Defense of a killed target`.
The version-prefix convention seen in older history (`[0.3.x] subject`) is under review.

## Known structure debt

Some files are far larger than the standard allows (`scripts/main.gd`,
`core/nml-core/src/sim.rs`). Do not grow them for convenience: put new behaviour in its own
script or module and wire it in. Decomposition is planned and will be recorded as an ADR.
