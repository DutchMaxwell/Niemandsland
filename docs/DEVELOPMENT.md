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
flatpak run org.godotengine.Godot --path . --editor      # then F5
# Directly (main scene = scenes/startup_menu.tscn)
flatpak run org.godotengine.Godot --path .
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

**Python** — the relay (the offline 3D asset pipeline lives in a separate private repo):

```bash
cd relay && python -m pytest                       # WebSocket relay
```

## CI

`.github/workflows/build.yml` builds Linux + Windows exports and runs the gdUnit4
suites on Godot 4.6. Keep it in sync with `project.godot`'s engine version.

## Secrets

This repo contains no secrets or hardcoded credentials. The separate asset-pipeline
repository holds its own API tokens (git-ignored there).

## Conventions

- Coding standards: [`.claude/AAA_CODING_STANDARDS.md`](../.claude/AAA_CODING_STANDARDS.md).
- Commits: conventional (`feat:`, `fix:`, `refactor:`, `docs:`, `perf:`); branch off
  `main` and open a PR.
- Validate (compile-check + gdUnit4) before committing.
