# Niemandsland — Status & Roadmap

**Version:** 0.3.10.1-alpha *(public alpha — forward-looking backlog in [`docs/ROADMAP.md`](docs/ROADMAP.md))* · **Engine:** Godot 4.6 · **Branch:** `main`

This is the single source of truth for what works, what's in progress, and what's
planned. Architecture details live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md);
the full change history is in `git log`.

## Works today

**Solo mode — a full game against NACHTMAHR** — mark any imported army as AI-controlled
(checkbox at import, or later in the solo panel), or press **AI Opponent** and let
NACHTMAHR bring a list of its own (faction and 1000–3000 pts selectable). NACHTMAHR is a
**game AI in the classic sense: rule-based, deterministic, fully offline** — no machine
learning, no language model, no network call; the same inputs produce the same decisions.
**Exactly one difficulty ships: full strength** (`scripts/solo/solo_difficulty.gd` — every
legacy grade name resolves to NACHTMAHR; selectable grades are a roadmap item). The match
runs the rulebook flow end to end: roll-off → the winner picks a table edge and deploys
first → both sides alternate unit by unit with explicit hand-over clicks → scout phase in
the 12″ band → the roll-off winner opens round 1. Ambush / Infiltrate reserves wait off
table and arrive from round 2 (alternating placement, a per-model >9″ base-edge gate,
terrain-legal), objective markers are scored at the end of each round, and after the final
round (4 by default) a victory dialog states the result. The AI's own lists are fetched
from the asset CDN at runtime and cached for offline play — they are **never bundled in
this repo**, and a CI hygiene check blocks any commit that would add them.

**Solo — your side of the table** — you attack through the radial menu: **Shoot** / **Fight**
on any of your units (single models and lone heroes included), with a target mode that draws
the range ring and a live line-of-sight ray (green = clear, red = blocked), and real physics
dice in the tray for **both** sides. The melee sequence follows the book: the charge snaps to
base contact, Counter strikes first, Impact hits land, your strike-back is an explicit prompt,
fatigue applies to both sides, the loser tests morale up to Rout, and pile-in plus the
up-to-3″ consolidation wait for your input instead of locking the board. Casualties are
removed per model (plain models before special-weapon / equipment / Tough bearers, outside-in
so the chain does not tear); Takedown model picks, Deadly multiplication and Regeneration ask
the human player where they land. When **your** unit takes wounds and the choice can matter
(a Tough model or mixed loadouts in the unit), the game asks you to **allocate them by
clicking** — LMB places one wound on the model under the cursor, RMB auto-allocates the
rest; the AI keeps allocating its own by value.

**Solo — casting, both sides** — **Cast** in the radial menu opens the spell list with token
costs and effect text, marks legal targets with pulsing rings (green friendly / yellow enemy),
measures spell range base-edge to base-edge, and offers a boost tableau with live success odds;
NACHTMAHR then decides whether to interfere. It casts by the official D3+X procedure with its
own token economy and asks you to interfere through a single tableau (+/− tokens, the odds
update as you spend). Spell effects are **mechanical, not cosmetic**: lasting spells create
buff/debuff tokens from the army book, and hit / defence / movement / range / morale modifiers
and granted rules feed the real dice rolls, the movement rings and the target checks. Tokens
are consumed after exactly one exchange, expire at round end, and each application is logged.

**Solo — rules automation and one measuring truth** — a per-system rules registry
(`scripts/solo/rules_registry.gd`; values load strictly per game system, because the same rule
name means different things in GF / GFF / AoF / AoFS / AoFR) resolves hundreds of special rules
automatically for both sides: the core combat set (Deadly, Blast, Takedown, Counter, Impact,
Fear, Rending, Furious, Relentless …), the modifier families (Stealth / Evasive / Shielded /
Fortified / Guarded, the conditional-AP family, the "X Aura" variants) and the behaviour rules
(Aircraft, Strider / Flying terrain, Hit & Run, Retaliate, Strafing, Re-Deployment, Vanguard,
Bounding, Teleport …) — **100 % coverage over the bundled opponent lists, >91 % playable
book-wide**. **Every applied rule writes its own battle-log line** (a silently-correct rule
reads like a broken one), and any rule the automation does *not* cover is named per unit in the
log. Measurement has a single truth: shooting gates, charge reach, melee reach, spell range and
objective control all measure **base edge to base edge** like the ruler, and line of sight is
computed per model from the base edge — walls and intervening units block, woods and ruins are
area terrain (see in and out, never through), containers block hard — so ruler, sight fan and
engine always agree.

**Not automated (named, not hidden)** — seven rule names are **not** resolved by the game and
are named in full rather than hidden behind an "…": the cross-unit caster aura (**Extended Buff
Range**), the rules that create or return units (**Spawn**, **Split**, **Reinforcement**) and the
movement / deployment set (**Coordinate**, **Delayed Action**, **Traversal**). The per-unit notice
in the battle log names the ones your list actually contains, so you can apply them by hand.
Everything else in the books is modeled — including plain *Re-Deployment*, *Grounded
Reinforcement*, *Reanimation*, *Caster Group*, *Spell Accumulator* and all three Ambush variants
(see below). The follow-up resolver waves are post-release work (see
[`docs/ROADMAP.md`](docs/ROADMAP.md)).

**Ambush variants** — **Ambush Beacon** waives *every* enemy distance restriction (the 9″/3″
arrival ring and an enemy's *Repel Ambushers* 12″ alike) for a reserve that lands within 6″ of the
beacon model; the AI actively looks for those circles, and your own arrivals get the waiver instead
of the honour-system warning. **Rapid Ambush** arrives from round 1 — after deployment and the
Scout phase, as a round-start beat, so it never buys an extra deployment slot. **Ambush
Re-Deployment** lets a unit whose models all carry it leave the table once per game at the end of
its activation and return, as if from Ambush, at the start of the *next* round exactly. Every one
of them writes its own battle-log line — including when a beacon stood close by and did *not*
apply.

**Transports (stage 1)** — units embark and unload through the radial menu with book-exact
capacity, disembark into an automatic 6″ formation, and a destroyed transport spills its cargo
with a Shaken marker. An **Ambush transport can load during deployment** ("Embark (reserve)"
in the radial while both wait in reserve) — the whole package arrives together from round 2.
The whole embark state syncs in multiplayer and persists in saves (`SAVE_VERSION` 1.7, with a
migration step).

**Battle log & play aids** — a collapsible event log narrates the game (moves with the real
traveled distance, who rolled what and the faces, wounds, kills, revives, round changes and
every automated rule) with All / Combat / Movement / AI filters. **Export** or `F8` writes the
log to a text file and **Copy** puts the rendered log on the clipboard — both intended for bug
reports; a developer "AI reasoning" toggle adds NACHTMAHR's per-decision record. A **sight &
range fan** (`F`, `Shift+F` clears) shades what the selected unit can legally see and shoot —
walls cast shadows, woods are see-into-not-through, one band per weapon range — and it appears
automatically on every AI volley. Picking a unit up leaves a translucent **origin ghost** where
the move began, hovering an object shows that object's hotkeys in a hint line, and `Ctrl+R`
snaps any selectable (unit, loose model, terrain) to the nearest 90°.

**Sandbox & objects** — 3D table (variable sizes), orbit/pan/zoom camera, spawn/
move/rotate/delete, multi- and box-select, copy/paste/duplicate, row/arrow
arrangement with constant base-edge spacing, distance measuring (inches), physics
D6 dice in a scaled SubViewport (our own MIT `dice_tray.gd` / `dice_d6.gd`; replaced
the former AGPL `dice_roller` addon) with a per-face result readout and a shared
multiplayer dice log. **Extended dice options** (display-only, rules in
`dice_rules.gd`): success target (2+…6+) + modifier with OPR's natural-6/1 rule,
success counts in readout and log, and one-click partial rerolls (fails / 1s /
6s / all — only those dice re-toss, the rest stay frozen); faces + evaluation
context sync to remote players.

**Map layout** — top-down 3″ grid editor: terrain pieces (ruins/forest/container/
dangerous), front-line + custom-polygon deployment zones (1″ grid, symmetric/
asymmetric, snap points, float-precision vertices), objectives, auto-generate, OPR
guideline checker, 3D overlay, save/load layouts. **The whole prop set is textured and
R2-delivered** (per-prop manifests + libraries, holographic offline fallbacks that
upgrade in place): ruin walls as fully closed masonry shells (per-role panels, stepped
crumble, alpha-profile caps, window reveals), forests as volumetric TRELLIS tree models
(billboards as the mid tier; deterministic variant/size/facing, spacing + boundary
margins), blockers as shipping containers (2 colourways), dangerous terrain as a
minefield (15 anti-tank mines + 2 warning signs). **Biome themes** re-skin the set in
place via `table.set_biome`: grassland (default), desert (fine adobe + cacti) and
tundra (snowed stone/conifers/containers); volcanic/jungle/urban still use the default
set. **Terrain reference aids (Asgard tournament standard, display only)**:
always-visible effect labels per terrain zone (Cover / Difficult / Dangerous /
Impassable / Height) and height-aware top-down line-of-sight in the measure tool
(`los_rules.gd` Height categories + per-zone flood fill in `terrain_overlay.gd`;
a 🚫 marker on the measure line when LOS is blocked). **Units also block sight
lines** (Asgard: a model blocks at its Height when ≥ both endpoints' Height, and
gaps under 1″ inside a unit count as closed; the endpoint units never block their
own line — `LosRules.units_block_line`). In a **human-vs-human** game the players apply
the effects themselves — terrain has **no automated movement/cover/damage effects**
there, by design. In a **solo** game the same pieces are rules-active for both sides
(line of sight, cover, difficult and dangerous ground — `scripts/solo/terrain_rules.gd`).

**Units (OPR)** — Army Forge import via the OPR API; per-model architecture
(`ModelInstance`) wrapped by system-agnostic `GameUnit`; automatic equipment
distribution; coherency check + on-table visualizer; radial context menu; docked
unit info card; per-model wounds and caster points; unit-wide Fatigue/Shaken/
Activated tokens; hero attachment.

**Movement & trails** — dragging a model paints a base-width "chalk" trail behind it
(**Path Painting**); the in-move ruler and the battle log report the actual traveled
path length (arc), not straight-line, while weapon/charge RANGE stays straight-line.
Every executed move is recorded to a move ledger and MP-synced (proof-of-movement),
and clicking a trail reports its distance. A **1″ spacing** layer shows proximity walls
(red enemy / orange friendly), snaps to base contact and forbids overlapping drops (own
units too). An **opt-in "dry-brush" movement cap** (default on) hard-stops the drag at
the selected action band (Advance ~6″ / Rush-Charge ~12″, Fast/aura-aware); backtracking
refunds the budget — the eraser band is the model's own chalk-ribbon width, so hand-walked
corrections actually refund (a genuine detour wider than the base still counts in full).
**`Ctrl`+`Z` takes a finished move back**: position, facing, chalk trail and the inch proof
all revert, synced to the other player; the window closes when dice hit the tray or the
next activation begins (a take-back is final — it never enters the redo stack). A **game-phase gate** frames setup vs play (Deployment → *Start Game*
→ Playing, with a multiplayer ready-sync and save/load persistence); trails auto-suppress
during deployment. Trail-visibility and movement-cap toggles persist in settings. For
**your own** models this is UX/measurement only — no move is resolved or forced; you still
move the models. In a solo game the phase gate flips automatically (solo deploy / first
activation), so the opening moves are painted too, and NACHTMAHR moves its own models along
the same measured, base-width corridors with a distance label.

**Multiplayer** — ENet over LAN and over the internet via the WebSocket relay
([`relay/`](relay/README.md)); full state sync (models, terrain, rotation, table
size) with batch RPCs; shared dice log; player avatars/cursors; multiplayer
save/load. A **slot a connected human occupies is never driven by the solo
automation** (hard guard since 0.3.10.1 — human-vs-human play is manual dice, as
designed; the roster shows "P2: NACHTMAHR" only for genuinely AI-designated
slots). **Deployment-zone geometry is host-authoritative** and synced on join;
"Show Deployment Zones" and "Flip Zone Colours" are per-player view preferences
(strictly local). **Player names** (entered in Host/Join, persisted, host-authoritative
sync) appear in the dice log, on avatars and in a connected-player **roster**;
an **in-game chat** panel (Enter to type, Esc to return — typing freezes camera
and object shortcuts). A **version handshake** on join rejects mismatched clients
(gating state sync on a match). A **room browser** lists joinable public rooms
(opt-in per host) and joins by click; private rooms stay code-only.
**Host-drop reconnect** (the relay preserves a dropped host's room for 20 s; the
host rehosts and re-syncs full state) is also live; see
[`relay/HOST_RECONNECT.md`](relay/HOST_RECONNECT.md). The relay (`list_rooms` +
host-reconnect) is deployed to Fly.io (`niemandsland-relay`, fra). The reconnect /
rate-limit / army-sync cascade was live-validated across two real clients.

**Import, saves & autosave** — Army Forge (OPR) list import and the `.nml` save format with
OS file association. The game **autosaves** every 5 minutes and at every round change into
three rotating slots that show up in CONTINUE and the load dialog (in multiplayer only the
host writes them; each autosave is announced by toast and battle-log line). Older saves
from removed import paths still load; their units come in as generic units.

**Onboarding — guided tutorial course** — **64 steps in 11 chapters** that teach on the real
table, event-gated (a lesson advances only when the player actually does the action): camera
& table, selecting, moving/rotating/arranging, measuring and rings, the full dice tray, unit
cards & the radial menu, wounds/casualties/revive, a real army import, table & casual terrain,
the competitive Map Layout editor, and movement & trails (path painting, dry-brush cap, 1″
spacing, Start-Game phase gate). It ships with a bundled board (official lists, real minis,
auto-generated terrain), progress persistence and an end assessment. Still open for later
waves: Settings, hosting/multiplayer, Regiments, and an OPR-rules / solo-play track.

**Presentation** — a built-in Tactical-HUD UI theme (sleek; cyan/amber), atmosphere
presets (Day/Sunset/Night/Overcast/Rain), graphics quality presets, SSAO + glow, cinematic intro. **Battlefield atmosphere**
([`docs/ATMOSPHERE.md`](docs/ATMOSPHERE.md)): one-click Day/Sunset/Night/Overcast/Rain
presets (2 s blends, rain particles, lightning + delayed thunder), a "war-torn" toggle
(deterministic fires at ruin walls with smoke + flicker light) and "distant war sounds"
— audio is real CC0 recordings delivered from R2 with procedural synth fallback
(`ambience_synth.gd`), persisted per player. Scatter decor: brick-rubble piles at ruin
wall bases + grassland grass field (one MultiMesh each, quality-gated). **AAA main
menu**: live night-battlefield diorama (production terrain stack + miniatures vignette
+ orbit camera with DoF), left command column (HudTokens), CONTINUE-newest-save entry,
typewriter quote ticker, menu soundscape + CC0 dark-ambient drone, idle attract mode.
Settings window reachable in-game via left panel button or F7. **UI audio**: every
`BaseButton` gets procedural hover/click/focus ticks via the `UiFeedback` autoload
(one `node_added` hook, zero per-button code; variation-aware confirm/back tones) on
a dedicated, independently mutable "UI" bus with its own persisted settings slider.

**3D model pipeline** — the offline pipeline (OPR data → image → TRELLIS mesh → GLB)
lives in a **separate private repository**; this repo and the shipped game consume only
its R2-delivered outputs, mapped by [`assets/model_manifest.json`](assets/model_manifest.json).

**3D model delivery (R2)** — miniature GLBs are **not bundled**; they are delivered
on demand from Cloudflare R2 (content-addressed `sha256.glb`, served from the asset CDN),
mapped by [`assets/model_manifest.json`](assets/model_manifest.json). Builds stay slim
(GLBs are gitignored + excluded from every export preset); the editor/game fetches
models at runtime. The publish tooling lives in the private pipeline repository. See
[`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md). **Live today: 1,185 models across
44 factions** (verified retrievable on R2 via `assets.niemandsland.xyz`) — from Alien Hives
(41) and Robot Legions / Orc Marauders (29 each) through recent additions
(havoc_brothers 26, dark_brothers 27, war_disciples 24) to the newest — **Mummified
Undead** (171 modular socket + composition entries: mounts, chariots, fixed
heavy-weapon variants), flipped live on R2 2026-07-15. Remaining factions are 2D
generated and pick-ready.

## In progress

The forward-looking work now lives in [`docs/ROADMAP.md`](docs/ROADMAP.md); see the
**Now / Next** sections there for what is actively being worked.

## Planned

The forward-looking plan and the feature-request pipeline now live in
[`docs/ROADMAP.md`](docs/ROADMAP.md) (single source) — see its **Next** and **Ideas**
sections (Age of Fantasy + Regiments, MP 3+ hardening, selectable AI difficulty grades,
co-op against the AI, transports stage 2, the remaining rule-resolver waves, …).

## Out of scope (by design)

For **human-vs-human** play Niemandsland stays a **tool, not an automated game**: in a local
or multiplayer game between people nothing is resolved for you — no automated combat or damage
resolution, no forced turn tracking, no automated terrain effects. The only framing device is
the lightweight **deployment→play phase gate** (a Start-Game affordance with a multiplayer
ready-sync), which resolves nothing.

**Solo mode is the deliberate exception**, because an opponent that resolves nothing cannot
play: when an army is marked AI-controlled the game runs activations, dice, wounds, morale and
special rules for both sides. Those systems only activate in a solo game; a human-vs-human
table behaves exactly as before. The legacy AI system + battle simulator (~5500 lines) was
removed and was **not** revived — today's solo engine (`scripts/solo/`) was written from
scratch against OPR's official Solo & Co-Op ruleset, deterministic and explainable by design.

**Not in this release, but planned:** co-op (two or more humans sharing a side against the AI) —
solo is single-player today; it sits in **Next** in [`docs/ROADMAP.md`](docs/ROADMAP.md).
Still out of scope by design: campaigns/ladders, and any AI that learns or calls out to a service.

## Not built (despite older docs)

The old root-level `ai_*.gd` scripts and `battle_simulator.gd` are gone and were not revived —
the `scripts/solo/ai_*.gd` files are the new, unrelated solo engine. `activation_tracker.gd`
and `hero_attachment_dialog.gd` never existed as separate files — that logic lives in
`game_unit.gd` / `radial_menu*.gd` / `network_manager.gd`.

## Known issues

- **Solo is alpha.** One difficulty grade only (full strength); solo is single-player
  (co-op vs the AI is not built); the rules listed under *Not automated* above must be
  applied by hand; all solo UI is English-only.
- Dice can occasionally jitter at miniature scale (mitigated by the scaled-SubViewport
  dice approach; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#scaling)).
- Some TTS texture-loading errors (non-fatal).
- OPR rule descriptions resolve for freshly imported armies; loaded saves /
  remote-only armies show rule names without descriptions (persist/sync is a
  future step).
- The 3D dice tray is shared between local and remote rolls: a remote roll that
  arrives while a local physics roll/reroll is still tumbling (same ~2 s window)
  preempts and drops the local roll (not logged/broadcast). Remote wins by design
  (it is already shared state); rare in practice.

## Tests

gdUnit4: **1,709 tests green** across **160 suites** in `test/` (incl. `coherency_checker`,
`save_manager`, `startup_menu`, `internet_lobby`, `relay_multiplayer_peer`, `network_manager` /
`network_version_handshake`, `dice_rules`, `player_identity`, the movement/spacing
suites `separation_checker` / `separation_resolver` / `separation_zone`, `move_ledger` /
`move_trails`, `game_phase`, `object_manager`, the guided-tutorial flow, and the solo
suites — `solo_controller`, `turn_manager`, `movement_planner`, `ai_decision` /
`ai_targeting` / `ai_position` / `ai_round_planner` / `ai_combat_math` / `ai_spell`,
`rules_registry`, `spells_registry`, `terrain_rules`, `sight_fan`, `transport_state` /
`transport_embark`, `autosave_controller`). A small **end-to-end layer** (`test/e2e/`)
boots the real `scenes/main.tscn` and drives the real menu / deployment-gate / click-ownership
/ battle-log-export / AI-path-label flows that unit tests skip. Python: `relay/test_relay_server.py`
(67 green). How to run: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md). Coverage of the
solo / movement / MP / tutorial paths is solid; some older gameplay scripts are still
untested.
