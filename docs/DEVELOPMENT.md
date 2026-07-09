# Development

## Prerequisites

- **Godot 4.6** (Forward+). `project.godot` declares `config/features=("4.6",
  "Forward Plus")`.

This project is developed with the **Flatpak** Godot (`org.godotengine.Godot`,
4.6.x). If you have a native `godot` 4.6 binary, drop the `flatpak run
org.godotengine.Godot` prefix from the commands below. The Flatpak needs read access
to the project path; the examples use `--filesystem=home` (adjust to your checkout).

## Run

```bash
# Editor
flatpak run --filesystem=home org.godotengine.Godot --path . --editor      # then F5
# Directly (main scene = scenes/startup_menu.tscn)
flatpak run --filesystem=home org.godotengine.Godot --path .
```

## Compile-check (all scripts, headless)

A full headless editor import registers autoloads and compiles every script —
the reliable way to catch errors:

```bash
flatpak run --filesystem=home org.godotengine.Godot --headless --editor --quit \
  --path "$PWD" 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Failed to load script"
```

Empty output = everything compiles.

> `--check-only --script <file>` on a single file gives false "Identifier not found"
> errors for autoload references — use the full `--editor --quit` import instead.
> `.godot/` and `*.uid` are git-ignored, so imports don't dirty tracked files (verify
> with an `md5sum project.godot` before/after if unsure).

## Tests

**GDScript (gdUnit4)** — suites live in `test/`:

```bash
# all suites
flatpak run --filesystem=home org.godotengine.Godot --headless --path "$PWD" \
  -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test
# single suite
... -a res://test/coherency_checker_test.gd
```

`--ignoreHeadlessMode` is required (otherwise exit code 103). Success = "0 failures"
and exit code 0. Trailing "ObjectDB instances leaked" is harmless teardown noise.
Reports are written to `reports/` (git-ignored).

**Python** — the relay's tests (the offline asset pipeline lives in a separate private repo and has no tests here):

```bash
cd relay && python -m pytest                       # WebSocket relay (base + churn/soak)
```

**Multiplayer stability (headless 2-client soak)** — `test/mp/` boots two real headless Godot
clients + a local relay and asserts no drops / state convergence from parsed `MP_HARNESS` logs:

```bash
# full 2-client soak (synthetic load: spawn-sync, 15 Hz cursor, moves, dice)
relay/.venv/bin/python test/mp/run_soak.py \
  --godot "flatpak run --filesystem=home --share=network org.godotengine.Godot" \
  --duration 120 --workload synthetic

# realistic load: import a REAL Army Forge army (downloads its GLBs from R2 + syncs to the
# guest = the real army-sync burst + download-stall path). Needs internet/R2.
... --duration 120 --workload opr --army "https://army-forge.onepagerules.com/share?id=XXX"
# nastiest real case — army import WHILE the guest framedrops:
... --workload opr --army "<link>" --fault framedrop --target-fps 5

# heaviest — BOTH sides import an army, the host auto-generates terrain, and each side moves
# its OWN models (two army-syncs + terrain + two-way movement on a populated field):
... --duration 150 --workload stress --army "<link>"

# reproduce a sporadic-disconnect cause on demand (guest side) + assert recovery:
#   stall     = one long main-loop freeze (stall detector fires; survives)
#   framedrop = sustained low FPS (--target-fps 8/5/3) — also fires the in-game advisory
#   blip      = force socket close -> guest reconnects + recovers
#   churn     = drop + reconnect repeatedly under load (asserts each recovers + state converges)
#   chaos     = interleaved framedrop + blips under full load
... --fault framedrop --target-fps 3
... --fault stall
... --fault blip
... --workload stress --army "<link>" --fault churn   # or --fault chaos
# The stress workload also drives combat RPCs (non-lethal wounds + activation) and a node-count
# leak watch (baseline after settle; the soak fails if nodes balloon).
```

`run_soak.py` exits 0 (green) / 1 (a drop or state divergence) and starts the relay itself
(needs `websockets`; `relay/.venv` has it). In CI pass `--godot godot`.

## CI

`.github/workflows/build.yml` builds Linux + Windows exports, runs the gdUnit4 suites, and runs
the relay pytest (`relay-tests` job) on Godot 4.6 — keep it in sync with `project.godot`'s engine
version. The timing-sensitive headless 2-client soak + fault matrix run in
`.github/workflows/mp-nightly.yml` (nightly + on demand) to keep the push path fast and non-flaky.

## Release checklist

A release is cut by pushing a `v*` tag (the CI release job builds + publishes it).
Before tagging:

- Bump `application/config/version` in `project.godot` — the **single source**; the
  in-game version label and update checker derive from it (never hardcode versions in UI).
- Move the `[Unreleased]` block in `CHANGELOG.md` under the new version heading and
  leave `[Unreleased]` empty.
- **Bump the README status badge + status line** (`README.md`, top) and the
  `**Version:**` line in `PROJECT_STATUS.md` to the new version (the two manual
  version spots outside `project.godot`).
- Update `docs/ROADMAP.md` — move shipped items to **Recently shipped** with PR links.
- Sweep `docs/KNOWN_ISSUES.md` for entries the release fixed.

## Secrets

This repo contains no secrets or hardcoded credentials. The separate asset-pipeline
repository holds its own API tokens (git-ignored there).

## Conventions

- Coding standards: [`CODING_STANDARDS.md`](CODING_STANDARDS.md).
- Commits: conventional (`feat:`, `fix:`, `refactor:`, `docs:`, `perf:`); branch off
  `main` and open a PR.
- Validate (compile-check + gdUnit4) before committing.
