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
  --path "$PWD" 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Failed to load script|Fehler bei|nicht ableiten|Cannot infer"
```

Empty output = everything compiles.

> **The Flatpak Godot on this dev machine runs in a German locale** — headless parse
> errors print as `Fehler bei (line, col): …` (e.g. `… nicht ableiten` for "cannot
> infer"), not the English `Parse Error` / `SCRIPT ERROR`. Grep for **both** locales
> (as above) or real errors are silently missed.

> `--check-only --script <file>` on a single file gives false "Identifier not found"
> errors for autoload references — use the full `--editor --quit` import instead.
> `.godot/` and `*.uid` are git-ignored, so imports don't dirty tracked files (verify
> with an `md5sum project.godot` before/after if unsure).

### Scene-script smoke gate (main.gd and other scene-only scripts)

The `--editor --quit` import and the gdUnit4 suites both **skip** `scripts/main.gd` and
any script that is only attached to a scene (never instantiated by a test). A parse
error there passes both gates and then hangs the startup menu's threaded load of
`main.tscn` on the LOADING overlay. After editing scene-attached scripts, run a short
real launch as the gate:

```bash
timeout 25 flatpak run --filesystem=home org.godotengine.Godot --path "$PWD" \
  res://scenes/main.tscn 2>&1 | grep -iE "Failed to load script|SCRIPT ERROR|Fehler bei"
```

0 hits = pass. (Headless does not exercise the scene scripts; the launch needs a display.
On this machine the physical display may be in use — do not seize `:0` without asking.)

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

> **Run the compile-check import pass first.** gdUnit4 resolves `class_name` scripts and
> test methods from `.godot/global_script_class_cache.cfg`. After pulling or merging work
> that adds a new `class_name` or new test methods, a stale cache makes the suite either
> abort with `Parse Error: Identifier "Foo" not declared` (exit 134) for a class that
> plainly exists, or silently run the old method count. The `--headless --editor --quit`
> import above regenerates the cache — run it, then the suite.

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

## Sandbox & `/tmp` gotchas

- **The Flatpak Godot sandbox cannot read `/tmp/claude-*`** (agent scratch paths). When a
  headless run needs an input file (e.g. an Army Forge list JSON for the `opr`/`stress` soak
  workloads), copy it **into the worktree** first, run, then delete it — a path under `/tmp`
  outside the sandbox reads as missing.
- **A full `/tmp` tmpfs makes bash exit 1/128 with no output.** On this dev machine the usual
  culprit is an accumulated Gradio cache; `rm -rf /tmp/gradio*` frees it. If unrelated commands
  start failing with empty output, check `df -h /tmp` first.

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

> **Relay deploys are separate from the game v-tag.** `fly deploy -c relay/fly.toml`
> (see `relay/README.md`) builds the image from your **local working tree**, not from
> `origin/main` — `git pull` first so you don't ship stale or someone else's uncommitted
> relay code. `flyctl` is not installed in the dev sandbox; the maintainer runs the deploy.

## Secrets

This repo contains no secrets or hardcoded credentials. The separate asset-pipeline
repository holds its own API tokens (git-ignored there).

## Conventions

- Coding standards: [`CODING_STANDARDS.md`](CODING_STANDARDS.md).
- Commits: conventional (`feat:`, `fix:`, `refactor:`, `docs:`, `perf:`); branch off
  `main` and open a PR.
- Validate (compile-check + gdUnit4) before committing.
