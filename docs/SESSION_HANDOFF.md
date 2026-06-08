# Session Handoff — Niemandsland

A snapshot so a fresh agent can take over the **game codebase** cleanly. Living
notes — update or delete entries as the project moves on.

## State at handoff

- **Version:** `0.3.1-alpha` (Alpha Release Candidate) · **Engine:** Godot 4.6, GDScript.
- **Branch / sync:** `main` is the source of truth and is **up to date** with all
  shipped work (the multiplayer + UI fixes #24–42, on-demand R2 model delivery, the
  0.3.1 docs). Feature work lands on a `claude/*` branch and is fast-forwarded to `main`.
- **Tests:** gdUnit4 **255 green** across 37 suites (`test/`). No known failures.
- **Working tree is clean** apart from the maintainer's local Model Forge scratch, which
  is gitignored (see *Boundaries* below).

What works today and the roadmap live in [`../PROJECT_STATUS.md`](../PROJECT_STATUS.md);
the architecture map is [`ARCHITECTURE.md`](ARCHITECTURE.md); build/run/test details are
in [`DEVELOPMENT.md`](DEVELOPMENT.md); the full history is `git log` / [`../CHANGELOG.md`](../CHANGELOG.md).

## Validation (do this before committing)

Godot is installed as a **Flatpak** (`org.godotengine.Godot`); there is no bare binary
on `PATH`. Always pass `--filesystem=home` so the sandbox can read the project.

```bash
GODOT="flatpak run --filesystem=home org.godotengine.Godot"
# 1. Re-import first — a stale class_name cache shows up as false "Identifier not declared".
$GODOT --headless --path "$PWD" --import
# 2. Parse/compile-check the WHOLE project (gdUnit4 does NOT load main.gd, so scene-script
#    parse errors only surface here):
$GODOT --headless --editor --quit --path "$PWD" 2>&1 \
  | grep -iE "Fehler bei|nicht ableiten|Parse Error|SCRIPT ERROR|Cannot infer"   # expect none
# 3. Tests:
$GODOT --headless --path "$PWD" -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test --ignoreHeadlessMode
```

> **German locale:** this machine prints Godot errors in German — *"Fehler bei (1969,23):
> … kann den Typ nicht ableiten"*, not the English "Parse Error". Grep for **both** (the
> command above does). Missing this is how a `var x := <Variant call>` parse error once
> shipped.

## Working conventions (from `CLAUDE.md`)

- Reply to the maintainer in **German**; keep everything in the codebase **English**.
- **Never commit without being asked.** Conventional commits (`feat:`/`fix:`/…).
- GDScript: explicit types, **no warnings** (treated as errors). Do **not** use `:=` on a
  Variant-returning call (e.g. a method on a `Node`-typed reference) — annotate the type.
- Real visuals can't be rendered headless (dummy renderer); validate logic with the
  compile-check + tests, and eyeball UI changes in an actual build.

## Open items / follow-ups

- **#43 — Host-drop reconnect (relay).** Guests already auto-rejoin after a relay blip
  (#37), but if the **host** drops, the room dies. Full spec in
  [`../relay/HOST_RECONNECT.md`](../relay/HOST_RECONNECT.md). **Deploy-gated:** it needs a
  relay-server change + a Fly.io redeploy (`flyctl` is not installed here) and a local
  two-player test before touching the shared live relay (`wss://niemandsland-relay.fly.dev`).
- **OPR rule descriptions** resolve for freshly imported armies; loaded saves / remote-only
  armies show rule *names* without descriptions (persist/sync is a future step).
- **Pre-release** (see [`PRE_RELEASE_LICENSING.md`](PRE_RELEASE_LICENSING.md)): IP-lawyer
  review of AI-generated + OPR-derived assets; **OPR unit data must never be bundled or
  MIT-licensed** — it is loaded only at runtime via the Army Forge API. Keep it that way.

## Known gotchas (don't re-introduce)

- **Headless editor re-saves mutate two tracked files** — if you see them as unexplained
  working-tree diffs, `git checkout` them; they are editor artifacts, not intended changes:
  - `project.godot` loses `renderer/rendering_method.web="gl_compatibility"` under
    `[rendering]`. That line is **required** for the Web/itch.io export (`web-itch.yml`) and
    is harmless to desktop — it must stay.
  - `scenes/map_layout.tscn` gets churned (regenerated `uid://`, per-node `unique_id=`,
    `Color(1.0,…)`→`Color(1,…)`, default-valued properties dropped). No design intent — revert it.
- **gdUnit4 never instantiates `main.gd`** — run the `--editor --quit` compile-check (step 2
  above) or a `main.tscn` scene parse error slips past a green test run.

## Boundaries — `tools/model_forge/` is the maintainer's domain

Model Forge is an **offline content pipeline** (OPR data → Gemini image → TRELLIS 3D →
Cloudflare R2). It is **not** loaded by the running game — the game only reads
`assets/model_manifest.json` and fetches GLBs on demand. A codebase agent should not need
to touch `tools/model_forge/`. Its secrets (`.gemini_key`, `.hf_token`, `.r2_credentials`,
`.trellis_space`) and heavy scratch (`.bbtmp/`, `engine_comparison/` render sweeps,
`state/`, one-off `_*.py`) are gitignored; the reusable, versioned pipeline is
`faction_finalize.py` (image→GLB batch) + `faction_publish.py` (R2 upload + manifest merge)
+ `publish_manifest.py`, with `glb_srgb_fix.py` as a documented post-TRELLIS colour fix.
Live on R2 today: **113 models across 5 factions** (Alien Hives, Battle Brothers, Robot
Legions, Dao Union, a Dark Brothers hero).
