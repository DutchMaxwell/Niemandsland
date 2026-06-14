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

- **Regiments — facing & front-arc display (M5)** — _logic + facing marker done_
  (`LosRules.is_in_front_arc`, `RegimentTray.facing_2d` / `front_arc_contains`, a cyan
  front-facing arrow on the tray; all unit-tested). **Pending (needs live verification):**
  wiring the "LOS toward front" check into the measure tool + an optional front-arc
  wedge overlay. Display only, no rule enforcement. _M_

## 📋 Next (accepted, queued)

- **AoF: Regiments — verify import vs a real list** — confirm base sizes / frontage
  from Army Forge against an actual `aofr` army. _S_
- **Multiplayer — two-client live test** — confirm lobby/chat/names + the relay
  (room browser, host reconnect) across two real clients. _S_
- **Regiments — handling polish** — frontage cycle (5-wide ↔ other), wheel about the
  front corner. _M_

## 🧊 Ideas (icebox — captured, not committed)

- Rules-reference overlays for more game systems.
- _Community feedback from the alpha lands here first._

## ✅ Recently shipped

See [`CHANGELOG.md`](../CHANGELOG.md). Highlights: **Age of Fantasy: Regiments**
(movement-tray blocks, square bases, casualty re-rank, save/load), **skirmish 6″
coherency** (Firefight / AoF: Skirmish), **units block line of sight** (Asgard
height + closed 1″ gaps), the **UI sound bus** (UiFeedback autoload), the asset-CDN
decoupling, and the go-public preparation.

---

<sub>Maintainer/agent note: this file is the curated backlog and the single
forward-looking source. The agent reads it at the start of a session, implements the
top **Now / Next** item, and moves it to **Shipped** with a PR link on merge. Internal
release mechanics (domain move, history scrub, going-public settings) live in
`_internal/`.</sub>
