# Handoff — Finish the ruin texturing in the game (for the local GPU instance)

> **Status: DONE (2026-06-09, local GPU instance).** All four jobs are complete: the 9
> runtime panels are verified live on R2 (sizes match `assets/ruins_manifest.json`);
> the shell walls are implemented in `scripts/terrain_overlay.gd` (delivered on demand
> via `scripts/ruins_library.gd`, triplanar fallback until cached); and the look was
> **verified on GPU** (RTX 3070 Ti, Forward+) with `tools/render_overlay_ruins_runner.tscn`,
> which renders the REAL renderer path — R2 fetch → in-place shell upgrade — for a 9×9″,
> a 9×6″ and a 90°-rotated 9×6″ ruin: every crumble arm steps down toward its free end
> (gotcha #1 passes, including under rotation via the `taper_dir` emitted by
> `TerrainPrefabs`). One GPU-only artifact was found and fixed: texture REPEAT wrap-bled
> the opposite panel edge at u=1.0 under anisotropic filtering (full-height stone slivers
> at mirrored crumble free ends) — panel materials now use `texture_repeat = false`
> (also applied to the reference tool). gdUnit4: full suite green. Still user-owned:
> **rotate the Gemini key** (§ "Do not").

**Date:** 2026-06-09 · **Read with:** [`docs/HANDOFF_RUIN_WALLS.md`](HANDOFF_RUIN_WALLS.md) —
the full design + §6 integration plan + gotchas. This file is the short "what's actually
left and what went wrong" directive on top of it.

---

## Why the in-game ruins still look old

`main` renders the **first-pass triplanar box** (`terrain_overlay.gd::_get_ruins_wall_material`
+ the single `ruins_wall.webp`). The approved **mossy shell-wall** look — two L-corners, a
crumble taper toward the open ends, the inset Gothic window / doorway openings — was
**planned and prototyped but never wired into the in-game renderer**. So the texturing work we
iterated on is **not visible in `main`**. That is the "old state".

What **is** already in `main` (don't redo it):

- **Wall layout** — `scripts/terrain_prefabs.gd` emits **two point-symmetric L-corners** +
  a per-segment `role` taper. Tested (gdUnit4: 256 green). Only the *visual rendering* is
  missing.
- The **reference implementation**, the **recipe**, and the **full plan** (see below).

## Where the textures are

Per `main`'s docs the mossy source-art set is **archived on R2**
(`assets.akesberg.de/terrain-source/ruins/`), **not bundled** — only the runtime
`ruins_wall.webp` ships. **First, verify the set is actually on R2.** If it isn't, the
complete 10-file set is preserved on `origin/claude/terrain-prop-textures` @ `8386ba1`, and is
reproducible via `tools/model_forge/generate_ruin_walls.py` (`--only variants` is free, no API).

> Heads-up: `HANDOFF_RUIN_WALLS.md` is internally inconsistent — §1/§3 say "on R2", §8 still
> says "committing is fine". Pick one. R2 matches the project's delivery model (biomes/models).

## The job

1. **Textures + runtime delivery.** Confirm the art exists (R2 → else branch `8386ba1` /
   recipe). Decide *runtime* delivery: **on-demand from R2** (same pattern as biomes —
   `BiomeLibrary` / `AssetDownloadManager`), which matches the R2 direction — **or** bundle the
   ~4 MB set. The renderer needs the panels available at runtime either way.
2. **Implement the shell walls** in `scripts/terrain_overlay.gd`, exactly per
   `docs/HANDOFF_RUIN_WALLS.md` §6 and the reference implementation `tools/render_ruin_walls.gd`:
   - pick the panel per segment from `role` (`full` → solid/topdmg/opening/window;
     `crumble_*` → the matching texture),
   - build a **shell, not a box** (front + back `QuadMesh` + a plain-stone top cap),
     alpha-scissor for the holed panels, normal map, **per-arm crumble U-flip**,
   - **collision stays a full-height Impassable box** — only the visual becomes a shell.
3. **Verify on the GPU** (the reason this was deferred to you): run
   `res://tools/render_ruin_walls_runner.tscn`, then load a map with ruins in-game. Check the
   **crumble direction** (gotcha #1) and the window/doorway. Target look:
   `docs/images/ruin_walls_reference.png`.
4. **Land it cleanly** — work on a **fresh branch off current `main`**; import-check +
   gdUnit4 green; if you bundle the art, confirm the binaries are actually in the merge
   (`git diff --stat main..<branch> -- assets/terrain/props/ruins/`).

## ⚠️ Do not

- **Do not merge or PR `claude/terrain-prop-textures`.** It was branched from an **old**
  `main`; merging it would **revert** PR #47 (biomes) and #49 (update check) — `update_checker.gd`
  −310 lines, `biome_library.gd` removed, etc. Use it **only** as an asset source:
  `git checkout origin/claude/terrain-prop-textures -- assets/terrain/props/ruins/`.
- **Do not lose the binaries on merge.** PR #48 was squash-merged and **silently dropped** the
  texture `.webp` (+ `.import`) — that is why they are absent from `main`. Don't repeat it.
- **Rotate the Gemini key** (`tools/model_forge/.gemini_key`) — it was pasted into a chat.

## Key gotcha (crumble flip — #1)

The crumble texture descends toward its **+U (right)** edge, so each arm's panel must be
U-flipped (`uv1_scale.x = -1`) so the wall steps **down toward the open end**. Canonical
(unrotated) mapping: **N no-flip, W flip, S flip, E no-flip** — re-derive against
`terrain_overlay`'s quad rotation (N=0 / E=+90° / S=180° / W=−90°, then `− grid_rotation`) and
compose with the piece's `rotation`/`flip`. Cleaner: emit a free-end direction from
`wall_segments_for` (it transforms with the cell, like edges do) and flip from that.
**Eyeball it on the GPU.**

## Already in `main` (your sources)

| Path | What |
|---|---|
| `docs/HANDOFF_RUIN_WALLS.md` §6 | Full integration plan + all gotchas |
| `tools/render_ruin_walls.gd` (+ `_runner.tscn`) | The approved reference implementation to port |
| `tools/model_forge/generate_ruin_walls.py` | Recipe (reproduce the texture set) |
| `scripts/terrain_prefabs.gd` | Wall layout — done, tested |
| `docs/images/ruin_walls_reference.png` | The target look |
