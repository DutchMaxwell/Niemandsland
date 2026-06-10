# Model Forge — faction pipeline status

The "model review" tracker. Every Grimdark Future faction moves through:
**2D** (3 versions/unit, gate-checked) → **pick** (best of 3) → **3D** (TRELLIS GLB) →
**R2** (uploaded + in [`assets/model_manifest.json`](../../assets/model_manifest.json),
live in-game on demand).

_Last updated: 2026-06-10 — Eternal Dynasty (samurai) shipped; Orc Marauders converting._

## Summary

| Stage | Factions |
|---|---|
| ✅ Live on R2 | **7** (167 models) |
| ⏳ 3D conversion running | **1** (Orc Marauders) |
| 🎯 Picked — ready for 3D | **4** |
| 🖼️ 2D done — needs picking | **21** |
| ⬜ 2D not generated yet | **5** |

## ✅ Live on R2 — playable in-game (167 models)

| Faction | Models | Note |
|---|---|---|
| Alien Hives | 41 | |
| Robot Legions | 29 | |
| High Elf Fleets | 28 | |
| Eternal Dynasty | 26 | ronin-samurai recast |
| Battle Brothers | 23 | |
| Dao Union | 19 | |
| Dark Brothers | 1 | ⚠️ hero only — 26 more units are 2D-done, not yet 3D/R2 |

## ⏳ 3D conversion running

- **Orc Marauders (29)** — TRELLIS finalize in progress → R2 next.

## 🎯 Picked — ready for 3D → R2 (just run finalize + publish)

Dwarf Guilds (~27) · Goblin Reclaimers (~18) · Ratmen Clans (~25) · Saurian Starhost (~23).

## 🖼️ 2D done — needs picking (best of 3) before 3D

⭐ **Human Defense Force (28)** — modern-military sci-fi recast (was WW2/Wehrmacht), fresh 2D done; **pick this**.

Then: Wolf Brothers, Blessed Sisters, Blood Brothers, Dark Elf Raiders, Plague Disciples,
Infected Colonies, Wormhole Daemons (Change / Plague / War / Lust), Soul Snatcher Cults,
Machine Cult, Lust Disciples, Custodian Brothers, Human Inquisition, Rebel Guerrillas,
Knight Brothers, Jackals, Elven Jesters, Titan Lords.

*(Dark Brothers also belongs here for its remaining 26 units.)*

## ⬜ 2D not generated yet (session stub only)

Change Disciples · Havoc Brothers · Prime Brothers · War Disciples · Watch Brothers.

## Pipeline commands

```bash
cd tools/model_forge
# 3D (TRELLIS 1536/300k/4096 RAW -> state/<session>/glb_final/), reads images/:
./venv/bin/python faction_finalize.py <session_dir_name>
# R2 publish (upload content-addressed + merge into model_manifest.json):
./venv/bin/python faction_publish.py  <session_dir_name>
# IMPORTANT before publishing a new faction: purge other factions' local
# assets/miniatures/*/glb/ staging (they are R2-delivered) — publish asserts that only
# the target faction has local GLBs. Also purge assets/.manifest_upload/ (transient).
```

> Clean-regen gotcha: the pipeline is resume-safe (skips existing images/versions). To force a
> clean re-gen after a design-language change, archive the old `state/<faction>_*` session,
> move the old `assets/miniatures/<faction>/_reference*.webp` anchors aside, and delete any
> `state/_overnight_done_<faction>` marker — otherwise everything is skipped and the old
> reference drags the look back.

> Build hygiene: the per-faction `_reference*.webp` style anchors (~17 MB across 33 factions)
> are Model-Forge generation inputs only; the runtime game never loads them. They should be
> gitignored out of the game build (pending).
