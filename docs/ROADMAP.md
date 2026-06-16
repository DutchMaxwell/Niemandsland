# Roadmap

Niemandsland is an early alpha. This is the **living, prioritized view** of what's
planned and where ideas go. For what already works see
[`PROJECT_STATUS.md`](../PROJECT_STATUS.md); for shipped history see
[`CHANGELOG.md`](../CHANGELOG.md).

## How a request flows

```
💡 Idea  →  🔍 Triage  →  📋 Next  →  🔨 In progress  →  ✅ Shipped
            (maintainer
             accepts / declines)
```

- **Submit** ideas and bugs as [GitHub issues](../../issues/new/choose) (Bug report /
  Feedback templates) — that's the intake.
- The **maintainer triages**: accepted items move to **Next**, raw ideas to **Ideas**.
  Nothing is owed an outcome; this is a hobby project (see
  [`CONTRIBUTING.md`](../CONTRIBUTING.md)).
- Each item stays short: **title · why · size (S/M/L) · status · link**.

## 🔨 Now (in progress)

- **Casual sandbox terrain (grid-free)** — pick terrain from a shelf and drag/rotate it
  freely on the 3D table, no 3″-grid binding. Walkable multi-storey grassland ruins
  (`SandboxTerrainProp`), tree-group forests + hazard clusters on a shared movable base
  (`TerrainGroupBase`), and a 2D mirror of the placed terrain in the map-layouter.
  Ruins are built from the SAME masonry wall panels as the grid ruins (RuinsLibrary, already
  on R2) — no GLB / model-forge assets needed. Engine + tests landed. _M_
- **AoF: Regiments — verify import vs a real list** — confirm base sizes / frontage
  from Army Forge against an actual `aofr` army. _S_

## 📋 Next (accepted, queued)
- **Multiplayer — two-client live test** — confirm lobby/chat/names + the relay
  (room browser, host reconnect) across two real clients. _S_
- **Regiments — handling polish** — frontage cycle (5-wide ↔ other), wheel about the
  front corner. _M_
- **Units as line-of-sight blockers** — formation height + closed 1″ gaps (after the
  terrain LOS aid). _M_
- **UI sound bus** — a dedicated mutable "UI" audio bus + a `UiSound` autoload wiring
  button hover/click/focus feedback. _S_

## 🧊 Ideas (icebox — captured, not committed)

- **Multi-level terrain** — per-cell elevation, walkable ruin floors, ramps. The
  surface-aware placement raycast (models rest on terrain tops) is the groundwork. _L_
- Rules-reference overlays for more game systems.
- _Community feedback from the alpha lands here first._

## ✅ Recently shipped

See [`CHANGELOG.md`](../CHANGELOG.md). Highlights: **Age of Fantasy: Regiments**
(movement-tray blocks, square bases, casualty re-rank, save/load, **facing &
front-arc display**), **skirmish 6″ coherency** (Firefight / AoF: Skirmish), the
asset-CDN decoupling, and the go-public preparation.

---

<sub>Maintainer/agent note: this file is the curated backlog and the single
forward-looking source. The agent reads it at the start of a session, implements the
top **Now / Next** item, and moves it to **Shipped** with a PR link on merge. Internal
release mechanics (domain move, history scrub, going-public settings) live in
`_internal/`.</sub>
