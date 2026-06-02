# Session Handoff — Niemandsland

A snapshot so work can resume after a context reset. Living notes — update or
delete entries as the project moves on.

- **Branch:** `claude/zen-bell-XDivY` — push here; the maintainer merges to
  `main` **locally**.
- **Engine:** Godot 4.6, GDScript. Test baseline: gdUnit4 **199/199 green**.

## Working conventions
- Respond to the maintainer in **German** (see `CLAUDE.md`).
- **Never commit without being asked.** Push only to the branch above.
- GDScript: explicit types, **no warnings** (warnings are treated as errors).
  Don't use `:=` on Variant-returning calls — e.g. use `lerpf`, not `lerp`.
- Real visuals can't be rendered headless (dummy renderer) → use PIL mockups
  for UI previews; validate logic with compile-check + headless smoke + tests.

### Validation (GODOT_BIN = `$HOME/.local/share/godot/godot`)
- Compile-check: `"$GODOT_BIN" --headless --editor --quit --path .`
- Tests: `"$GODOT_BIN" --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test --ignoreHeadlessMode`
- Menu smoke: `"$GODOT_BIN" --headless --path . --quit-after 150` (expect "Startup menu animation complete")

## Recent work on this branch (newest first)
- `ced4c7e` — **Radial menu** polished + trimmed: Inter labels (was cryptic
  single letters), cyan hover with outward pop + accent arc, segment gaps,
  dark glass + cyan rim + glow, red destructive actions, styled tooltip.
  Removed **Stats/Info** and **Coherency**; dropped on-wheel shortcut numbers
  (keys 1–9 already do "arrange at cursor").
- `2cd6c81` — **Rotating anti-war menu quotes** (10, English, random per
  launch) + **Dr. Strangelove** footer on the table-size dialog + **all
  remaining UI localized to English**.
- `373f3d5` — **Rebrand OpenTTS → Niemandsland** (no man's land / WWI
  anti-war framing): app name + window title, README/docs/LICENSE, save
  extension `.otts`→`.nml` (+ `tools/` MIME/.desktop/.reg renamed),
  ProjectSettings namespace `opentts/`→`niemandsland/`, relay app/host
  `opentts-relay`→`niemandsland-relay`, start-menu wordmark **NIEMANDS|LAND**
  + subtitle + quote.

## Start-menu identity
- Subtitle: "A Fan-Made Tabletop Simulator for OnePageRules Game Systems".
- `scripts/startup_menu.gd` → `MENU_QUOTES` (10, picked at random in `_ready`):
  Remarque ×3 (All Quiet on the Western Front), Full Metal Jacket, Das Boot,
  Platoon, Catch-22, Paths of Glory, The Thin Red Line, Apocalypse Now.
- `scripts/table_size_dialog.gd`: fixed footer — "Gentlemen, you can't fight
  in here! This is the War Room!" (Dr. Strangelove).

## Open items / follow-ups
- **Relay deploy:** default URL is now `wss://niemandsland-relay.fly.dev`
  (`relay/fly.toml` app = `niemandsland-relay`). The fly.io app must be
  (re)deployed under that name, or online play breaks on the default URL.
- **Platform renames (external, maintainer):** GitHub repo
  `dutchmaxwell/opentts` → `…/niemandsland`; itch.io project slug; set the
  GitHub variable `ITCH_TARGET`. CI references already point to the new slug;
  GitHub auto-redirects old URLs.
- **Pre-release** (runbooks in `docs/runbooks/`, checklist in
  `docs/PRE_RELEASE_LICENSING.md`): git **history scrub** (old bundled OPR
  data, the removed AGPL dice addon, and the old "OpenTTS" name still live in
  history); IP-lawyer review (AI-generated + OPR-derived assets); move
  `tools/model_forge/` to a separate repo.
- **OPR data rule (hard):** OPR unit data must never be bundled or MIT — load
  it only at runtime via the Army Forge API. Keep it that way.
- **Save format:** extension is now `.nml` (was `.otts`) — breaking for old
  saves (acceptable pre-release; flag if a user has saves to migrate).
- **Radial controller:** `scripts/radial_menu_controller.gd` still has
  `unit_stats` / `check_coherency` action handlers that are now unreachable
  from the wheel (harmless). Optional cleanup.
- **i18n:** all user-facing UI is English; some **code comments** remain
  German (not UI — left as-is).

## Map
Architecture: `docs/ARCHITECTURE.md` · Project guide: `CLAUDE.md` ·
Status/roadmap: `PROJECT_STATUS.md` · Build/run/test: `docs/DEVELOPMENT.md`.
