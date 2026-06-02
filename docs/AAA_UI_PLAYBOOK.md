# Niemandsland — AAA UI Playbook

_Synthesized from a multi-agent research + codebase-audit pass (8 web-research
dimensions + 3 code audits). It maps general AAA-UI principles onto this repo's
actual files. Source URLs at the bottom. Keep this as the north star for the UI
redesign; update as items land._

## Pillars

### One enforced token system (no drift)

A single layered source of truth — hud_tokens.gd for the palette/geometry/spacing/motion tokens, glassmorphism_theme.gd as the Godot Theme adapter, ui_polish.gd reduced to delegating helpers. Every control consumes semantic tokens (surface, accent/primary=cyan, accent/secondary=amber, border/hairline, focus ring, SPACE_*, DUR_*), never raw Color()/px literals. Today two palettes (HudTokens vs UiPolish) disagree on danger, muted-text and radius (4 vs 12) — that split IS the indie tell. Consistency across the start menu, HUD, dialogs and map editor is what makes the product read as one designed object; tokens are how you enforce it and retune the whole navy/cyan/amber theme in one place.

### The command-console look, with discipline

Build on the existing tactical-HUD direction: deep-navy SURFACE fill, 1px hairline borders, soft top-light shadow, Orbitron headers over the amber-tick->cyan-rule accent line, mono technical labels. Sharpen it the AAA way — frame panels as instrumentation via reusable corner brackets + a single accent edge-line (a HudFrame node), near-sharp RADIUS=4 (never soft web-card rounding), segmented meters instead of smooth bars, column-aligned mono data. Keep ~90% of the chrome neutral so the 10% cyan/amber accent actually signals state. Add controlled richness (low-contrast navy gradient + faint grain to kill banding) and reserve cyan/amber EXCLUSIVELY for UI so they never collide with the 3D scene.

### Motion, feedback and sound that confirm every input

Every action gets proportional feedback within a frame, driven by centralized Motion tokens (DUR_HOVER=0.10, DUR_PANEL_IN=0.22/OUT=0.18, SCALE_HOVER=1.02/PRESS=0.97/PUNCH=1.06). Asymmetric curves — EASE_OUT to enter, faster EASE_IN to exit; distinct hover vs persistent keyboard-focus ring; press-in + release-punch for weight. Restrained juice only (scan-wipe on panel open, accent flash on confirm) — loud shake/squash stays on the 3D dice, not the data HUD. Pair every flourish with a short mono UI sound through a dedicated, mutable UI bus and a UiSound autoload. A 'Reduce Motion' toggle in GraphicsSettings collapses non-essential motion (WCAG 2.3.3) and never hides information behind animation.

### Reachability is non-negotiable

At any window size, DPI, text scale or aspect ratio the user can reach 100% of controls — nothing drifts off-edge, hides under a panel, or needs pixel-hunting. The foundation is right (canvas_items + expand) but three gaps remain: no min window size, no content_scale_factor/UI-scale, and no size_changed handler in main.gd. Close them, then enforce: anchors place the frame and Containers size the content (no absolute pixel offsets like the left panel's offset_bottom=700); every variable-length list lives in a ScrollContainer with follow_focus; dialogs clamp to the visible rect; >=44px hit targets with >=8px gaps; FOCUS_ALL + visible focus rings everywhere (fix the empty CheckBox focus box); WCAG-grade contrast on the dark theme; and meaning carried by shape/icon, not color alone.

## Reachability — non-negotiable (every control always reachable)

- No control is ever off-screen, clipped, occluded, or reachable only by mouse — at every window size, DPI, text scale and aspect ratio, 100% of controls are reachable (synthesis of WCAG 2.4.11/2.4.12 focus-not-obscured, XAG 101/112).
- Set a minimum window size once in the GraphicsSettings autoload: get_window().min_size = Vector2i(1280,720) (none is set today); leave max_size unset on desktop. Below the floor, content scrolls rather than compresses.
- Anchors place the structural frame; Containers size the content. No interactive element uses an absolute pixel offset inside a panel. Fix scenes/main.tscn LeftPanelScroll (currently anchors_preset=0 with a fixed offset_bottom=700) to Left-Wide + vertical EXPAND_FILL so its ScrollContainer governs overflow.
- Every variable-length list (army roster, unit equipment, command/action stack, import previews) lives in a ScrollContainer whose single child has Fill|Expand horizontal flags, vertical_scroll_mode=AUTO, follow_focus=true, and a deferred ensure_control_visible() after selection.
- All hardcoded dialog/panel sizes are clamped to the viewport: size = Vector2i(min(target_w, int(vp.x*0.9)), min(target_h, int(vp.y*0.85))) + popup_centered_ratio(0.85). Targets verified over-large: opr_import 550x450, wgs_import 550x500, lighting_panel 500x900, startup multiplayer popups 450x200/250, six 800x500 FileDialogs.
- Wire get_window().size_changed in main.gd (currently only cinematic_intro.gd has it) to reflow panels and re-clamp every free-floating dialog to get_window().get_visible_rect() so a dialog opened on a wide monitor is never stranded off-edge after the window shrinks.
- Expose a 'UI Scale' slider (0.8-2.0) bound to get_tree().root.content_scale_factor, defaulted from DisplayServer.screen_get_scale() with a 1.0 fallback (it returns 1.0 on Windows/X11, so the manual slider is mandatory for 4K); keep allow_hidpi on. Containers must reflow at 200% text scale with vertical scroll only, never horizontal, and never clip long German/localized strings.
- The entire UI is operable by keyboard AND controller digital input alone: focus_mode=FOCUS_ALL on every interactive control, FOCUS_NONE on pure labels; each dialog grab_focus (deferred) on open; modals trap focus and honor ui_cancel for Back; linear menus loop first<->last, 2D tile grids do NOT loop; a persistent Back/Quit path exists that is not a mouse-only corner X.
- Focus is always visibly indicated and never clipped: replace the StyleBoxEmpty focus boxes on CheckBox/CheckButton (glassmorphism_theme.gd lines 177-180), Tree (297) and TabContainer tab_focus (276) with a >=2px cyan ring clearing >=3:1 contrast against the deep-navy SURFACE (WCAG 2.4.13); the focused control must remain fully on-screen above any popup.
- Minimum hit target ~44px with >=8px spacing on all clickable buttons/icons (WCAG 2.5.8/2.5.5), enforced via HudTokens/Theme constants so dense rows (dice tray, command panel, unit-card actions) are never mis-clicked.
- Meaning is never carried by color alone: pair cyan/amber and every status color (coherency valid/invalid, dice pass/fail) with an icon, shape or label; use a CVD-safe (Wong-style) ramp and avoid red/green pairs.
- Keep all critical, interactive UI inside a safe zone (~90% / central 16:9) anchored to true screen edges with consistent MarginContainer insets, so ultrawide/tall extra space only adds breathing room and never strands a control behind an edge or notch.

## Prioritized actions

### Add a real cyan focus ring to CheckBox/CheckButton (and audit all focus styleboxes for >=3:1)
**impact: high · effort: low · Accessibility / focus**

Verified: scripts/glassmorphism_theme.gd _checks() (lines 177-180) sets a StyleBoxEmpty for the 'focus' state on BOTH CheckBox and CheckButton, so keyboard/controller users get NO visible focus there (WCAG 2.4.13 fail, strands tab navigation). Reuse the existing _focus() stylebox (a cyan border at 0.75 alpha) for those two controls instead of empty. While there, verify _focus()'s 1px cyan-0.75 border clears 3:1 against SURFACE (0.043,0.058,0.098) and bump border width to >=2px to satisfy WCAG 2.4.13's '2px perimeter' rule. Tree (line 297) and TabContainer (line 276) tab_focus also use StyleBoxEmpty — give them visible focus too.

### Set a minimum window size + UI-scale (content_scale_factor) in GraphicsSettings
**impact: high · effort: low · Responsive / reachability**

Verified: project.godot has window/stretch/mode=canvas_items + aspect=expand at 1920x1080 (correct foundation) but NO min window size and NO content_scale_factor anywhere in scripts/. A user can drag the window to ~100px and collapse the left panel, dice roller and unit card into each other. In GraphicsSettings autoload _ready(): get_window().min_size = Vector2i(1280,720), leave max unset. Add a 'UI Scale' slider (0.8-2.0) bound to get_tree().root.content_scale_factor, defaulted from DisplayServer.screen_get_scale() with a 1.0 fallback (it returns 1.0 on Windows/X11, so the manual slider is mandatory for 4K). Keep allow_hidpi on.

### Unify the token layer: collapse UiPolish into HudTokens as the single source of truth
**impact: high · effort: medium · Design tokens / consistency**

Verified drift: scripts/hud/hud_tokens.gd and scripts/ui_polish.gd BOTH define cyan as Color(0.0,0.85,1.0) but disagree everywhere else — UiPolish.DESTRUCTIVE = (1.0,0.35,0.43) vs HudTokens.DANGER = (1.0,0.33,0.38); UiPolish.TEXT_MUTED = (0.55,0.58,0.66) vs HudTokens.TEXT_MUTED = (0.56,0.61,0.69); and UiPolish radii are 12 while HudTokens.RADIUS = 4. This split palette is exactly the 'per-screen drift' tell. Make hud_tokens.gd the ONLY palette/geometry source; add the missing semantic tokens it lacks (SUCCESS, WARNING, and explicit DIALOG_MARGIN / SECTION_SEP / spacing scale SPACE_4/8/12/16/24) so callers stop reaching into UiPolish. Reduce UiPolish to thin helper wrappers (hex(), set_dialog_margins(), button height) that delegate to HudTokens constants, then migrate references. This is the keystone action — every other consistency fix routes through it.

### Make the left command panel and dice roller resolution-proof (anchors + size_changed)
**impact: high · effort: medium · Responsive / reachability**

Verified in scenes/main.tscn: LeftPanelScroll uses anchors_preset=0 with a hardcoded offset_bottom=700 (a fixed ~640px height that clips below 768px viewports and never scrolls the overflow); DiceRollerPanel and the FileDialogs are fixed-size/negative-offset. Re-anchor the left panel to Left-Wide (preset 9, full height) with custom_minimum_size.x and vertical EXPAND_FILL so its existing ScrollContainer actually governs overflow; anchor the dice roller Bottom-Right within the safe rect. Then add the missing global handler: main.gd has NO get_window().size_changed connection (only cinematic_intro.gd:266 has one) — wire it to re-clamp every free-floating dialog (table_size, wounds, casts, opr_import, wgs_import, lighting) to get_window().get_visible_rect() and popup_centered_ratio(0.85).

### Clamp all hardcoded dialog sizes to the viewport
**impact: high · effort: medium · Responsive / reachability**

Verified hardcoded sizes that overflow 1280x720 / 1024x600: opr_import_dialog.gd:25 (550x450), wgs_import_dialog.gd:30 (550x500), lighting_panel.gd:44 (500x900 — taller than a 768px screen), startup_menu.gd:170/217 (multiplayer popups 450x200), plus the six 800x500 FileDialogs in main.tscn. Replace each with size = Vector2i(min(target_w, int(vp.x*0.9)), min(target_h, int(vp.y*0.85))) and popup_centered_ratio(0.85). Wrap any variable-length body (opr_import army_preview RichTextLabel) in a ScrollContainer with follow_focus=true so long rosters never clip.

### Build one reusable HudFrame Control (corner brackets + single accent edge-line)
**impact: high · effort: medium · Tactical-HUD aesthetic**

This is the highest-leverage AAA aesthetic move and it builds directly on the existing HudTokens.header() chrome (which already does the Orbitron-title + amber-tick->cyan-rule accent line). Make a HudFrame node that, in _draw(), strokes short L-shaped corner brackets (e.g. 14px legs, antialiased) plus one accent edge-line, reading tokens (bracket length, HAIRLINE width, CYAN/AMBER) from HudTokens. Apply it consistently over the left command panel, unit cards, dice roller and all dialogs so they read as 'instrumentation' not 'web cards'. Keep RADIUS near-sharp (HudTokens.RADIUS=4 is already correct). Drive any hover/open animation via queue_redraw(), and only run per-frame phase updates while visible (honors the no-idle-work-in-_process standard).

### Create a Motion token set + reduce-motion toggle, and add hover/press/focus juice
**impact: high · effort: medium · Motion & feedback**

No motion tokens exist yet. Add them next to HudTokens: DUR_HOVER=0.10, DUR_PRESS=0.06, DUR_PANEL_IN=0.22, DUR_PANEL_OUT=0.18, DUR_SCREEN=0.35, SCALE_HOVER=1.02, SCALE_PRESS=0.97, SCALE_PUNCH=1.06. Wire hover (1.02 / TRANS_SINE EASE_OUT / 100ms), press-in 0.97 + release-punch (single TRANS_BACK tweener), and asymmetric panel enter (EASE_OUT ~220ms) / exit (EASE_IN ~180ms) — set pivot_offset to center first, store and kill() the previous tween to avoid flicker. Add a 'Reduce Motion' bool to the GraphicsSettings autoload (sits beside the existing presentation presets) that collapses motion to instant or a 0.10s opacity fade; never gate information behind animation (WCAG 2.3.3).

### Enable MSDF on the Orbitron header font; keep mono/body on hinted rasterization
**impact: medium · effort: low · Craft / text rendering**

Verified: assets/ui_glassmorphism/fonts/Orbitron.ttf.import has multichannel_signed_distance_field=false despite msdf_pixel_range=8 / msdf_size=48 already configured. Orbitron headers and unit-card titles sit over a zoomable 3D table, so enable MSDF on Orbitron only (set the flag true) to stay razor-sharp at any zoom. Keep SourceCodePro (mono technical labels) and Inter (body) on rasterized grayscale AA with hinting (MSDF has no hinting and softens small text). Also render the HUD on a non-stretched CanvasLayer at native resolution to dodge the documented canvas_items stretch blur (Godot #86563/#99440) so the 1px navy hairline borders render as true 1px.

### Add a dedicated UI audio bus + UiSound autoload auto-wiring BaseButton signals
**impact: medium · effort: medium · UI audio feedback**

default_bus_layout.tres exists; add a 'UI' bus under Master with independent, player-adjustable/mutable volume exposed through the existing AudioManager autoload (essential for long-session tools). Add a UiSound autoload that on _ready connects get_tree().node_added and, for every BaseButton, wires mouse_entered->hover, pressed->click, focus_entered->a quiet focus tick (covers keyboard/controller, not just mouse) — global audio with zero per-button work. Use AudioStreamPolyphonic + AudioStreamRandomizer (PLAYBACK_RANDOM_NO_REPEATS, +/-1-2 semitones, +/-2dB) so rapid hovers never machine-gun or fatigue. Map the palette to sound: cyan primary -> consonant rising confirm, amber secondary -> softer back/cancel, plus a gentle low/dissonant error for coherency_checker/opr_import failures. Keep UI sounds mono, <300ms, mixed below SFX.

### Add progressive disclosure to unit cards + breadcrumb back-stack to multi-step dialogs
**impact: medium · effort: medium · Information architecture**

unit_card: keep name/quality/defense/weapons always-visible; move full special-rule text + point breakdown into a Tween-animated collapsible VBox (cap at TWO disclosure levels). opr_import_dialog/wgs_import_dialog: render a breadcrumb HBox (Army > List > Equipment) + a Back button styled with the amber-secondary variation so it is visually distinct from the window close X, and intercept ui_cancel for Back so it is reachable without a mouse. Surface keybinds as mono sub-labels on command buttons (read from InputMap.action_get_events()) and consider a Ctrl+P fuzzy command palette for the long tail.

### Replace smooth bars with segmented meters + enforce keyboard/controller reachability
**impact: medium · effort: medium · Tactical-HUD aesthetic / accessibility**

For unit strength/wounds use XCOM-style countable segmented meters (loop N cells in _draw, filled vs outlined) so state is glanceable on the 3D table. Switch stat/coherency/dice readouts to the existing mono SourceCodePro face and column-align them for the 'machine readout' density. For reachability: set focus_mode=FOCUS_ALL on every interactive control, FOCUS_NONE on pure labels; grab_focus (call_deferred) when each dialog opens; trap focus in modals; fix spatial guesses with focus_neighbor_* in the radial menu / unit-card action rows. Pair cyan/amber and any status colors (coherency valid/invalid, dice pass/fail) with an icon or shape — never hue alone (CVD).

### Design the empty / loading / error states and migrate remaining hardcoded overrides
**impact: medium · effort: medium · Craft / finish**

Build a reusable StatePanel with EMPTY (no army imported / empty table -> icon + headline + direct action button), LOADING (skeleton placeholders sized to final layout, pulsing modulate, cross-fade real content in over ~180ms), and ERROR (message + code + Retry) variants; apply to the OPR API fetch, TTS model download and relay-connect flows so a wait never reads as a freeze. In parallel, work down the consistency audit's ~78 hardcoded overrides (startup_menu.gd, casts_dialog.gd, wounds_dialog.gd, radial_menu.gd's stray set_corner_radius_all(8) vs RADIUS=4, map_layout.gd, main.gd) replacing literal Color()/font_size/radius with HudTokens references. Adopt sentence case across menus/dialogs with one deliberate uppercase style for mono labels; swap any emoji icons for the existing single icon set.

### Make the entire left command panel selection-driven, not statically populated
**impact: medium · effort: high · Information architecture**

Verified: scenes/main.tscn LeftPanelVBox/SpawnPanel is a static stack of ~11 always-present buttons (LoadModel, ImportTTS, TerrainBrowser, ClearAll, NextRound...). The AAA RTS rule is that the command surface is a function of the live selection. Have object_manager/selectable_object emit selection_changed, and rebuild the panel from the union of valid actions for the current selection (empty selection = global/table verbs). This is the single biggest click-reducer for a data-dense tool and the radial_menu/unit_card already prove the selection-context pattern exists.

## Quick wins (do first)

- Enable MSDF on Orbitron.ttf (flip multichannel_signed_distance_field to true — msdf_pixel_range=8/msdf_size=48 are already set) so headers stay crisp as the table zooms; leave SourceCodePro/Inter on hinted rasterization.
- Give CheckBox/CheckButton a real cyan focus ring by reusing the existing _focus() stylebox instead of StyleBoxEmpty (glassmorphism_theme.gd:177-180) — one-line-per-state fix that restores keyboard focus visibility.
- Set get_window().min_size = Vector2i(1280,720) in GraphicsSettings._ready() so the window can never shrink below the supported layout breakpoint.
- Add a 'UI' audio bus under Master in default_bus_layout.tres with its own volume exposed in AudioManager, so UI sound is independently mixable/mutable for long sessions.
- Add the Motion token block (DUR_HOVER/PRESS/PANEL_IN/PANEL_OUT, SCALE_HOVER/PRESS/PUNCH) and a 'Reduce Motion' bool to GraphicsSettings now, so all later animation work references constants and honors the toggle from day one.
- Fix radial_menu.gd's stray set_corner_radius_all(8) to HudTokens.RADIUS (4) and replace its duplicate ACCENT_COLOR/DESTRUCTIVE_COLOR consts with HudTokens.CYAN/DANGER — removes an obvious radius/color drift.
- Connect get_window().size_changed in main.gd to a handler that re-clamps open dialogs to get_window().get_visible_rect() — main.gd currently has no resize handler at all.
- Re-anchor scenes/main.tscn LeftPanelScroll to Left-Wide with vertical EXPAND_FILL and drop the hardcoded offset_bottom=700 so its ScrollContainer actually scrolls overflow on a 768px laptop.

## Codebase audit — concrete findings

### UI Reachability & Responsive Design Audit

Comprehensive scan of Niemandsland codebase for controls that could become unreachable, clipped, or off-screen on small monitors. Found 10 critical/high-priority issues affecting dialogs, left panels, and fixed-position UI elements. Main risks: hardcoded dialog sizes that won't fit 1280x720 viewports, left panel with fixed height constraint (640px min), dice roller positioned off-screen at bottom-right on small displays, and modals that could appear partially outside viewport.
- **[high]** Hardcoded dialog sizes prevent display on 1280x720 monitors
  - @ `/home/user/openTTS/scripts/casts_dialog.gd:144, /home/user/openTTS/scripts/wounds_dialog.gd:173, /home/user/openTTS/scripts/model_info_popup.gd:116-143, /home/user/openTTS/scripts/opr_import_dialog.gd:25, /home/user/openTTS/scripts/wgs_import_dialog.gd:30`
  - fix: Replace fixed Vector2(250, 200) / Vector2(300, 200) / Vector2(250, 180) sizes with max() clamping to viewport: custom_minimum_size = Vector2(min(250, viewport.get_visible_rect().size.x * 0.8), min(180, viewport.get_visible_rect().size.y * 0.7)). For dialogs (Window), use size = Vector2i(min(550, int(viewport_width * 0.9)), min(450, int(viewport_height * 0.85))) and call popup_centered_ratio(0.8) instead of popup_centered(). Test at 1280x720, 1024x768.
- **[high]** OPRImportDialog hardcoded to 550x450 - won't fit 1024x600 tablets
  - @ `/home/user/openTTS/scripts/opr_import_dialog.gd:25`
  - fix: Change 'size = Vector2i(550, 450)' to: var viewport_size = DisplayServer.screen_get_size(); size = Vector2i(int(minf(550, viewport_size.x * 0.9)), int(minf(450, viewport_size.y * 0.85))). Use popup_centered_ratio(0.85) instead of manual sizing.
- **[high]** WGSImportDialog hardcoded to 550x500 - could overflow on small displays
  - @ `/home/user/openTTS/scripts/wgs_import_dialog.gd:30`
  - fix: Same as OPRImportDialog: size = Vector2i(int(minf(550, viewport.get_visible_rect().size.x * 0.9)), int(minf(500, viewport.get_visible_rect().size.y * 0.85))). Also add 'popup_centered_ratio(0.85)' in _ready().
- **[high]** LightingPanel fixed size (500x900) exceeds viewport on 1024px displays
  - @ `/home/user/openTTS/scripts/lighting_panel.gd:44-45`
  - fix: Change 'size = Vector2i(500, 900)' to: size = Vector2i(int(minf(500, viewport.get_visible_rect().size.x * 0.95)), int(minf(900, viewport.get_visible_rect().size.y * 0.9))); position = Vector2i.ZERO (remove hardcoded 50,50). The ScrollContainer at line 59 mitigates overflow, but enforce max height.
- **[high]** StartupMenu multiplayer popups hardcoded sizes (450x200/250) - too wide for 720px
  - @ `/home/user/openTTS/scripts/startup_menu.gd:170, 217`
  - fix: Replace _host_popup.size = Vector2i(450, 200) with: var max_w = int(DisplayServer.screen_get_size().x * 0.85); var max_h = int(DisplayServer.screen_get_size().y * 0.75); _host_popup.size = Vector2i(minf(450, max_w), minf(200, max_h)); _host_popup.popup_centered_ratio(0.75).
- **[high]** DiceRollerPanel positioned at bottom-right with hardcoded negative offsets - may clip on small monitors
  - @ `/home/user/openTTS/scenes/main.tscn:498-501 (DiceRollerPanel offset_left=-430, offset_top=-560)`
  - fix: Change anchors_preset from 3 (bottom-right) to 15 (full rect), then use size_flags_horizontal=Control.SIZE_SHRINK_END and size_flags_vertical=Control.SIZE_SHRINK_END. Remove hardcoded offsets. Alternatively: clamp position based on viewport: if global_position.y + size.y > viewport.size.y: global_position.y = viewport.size.y - size.y.
- **[high]** LeftPanelScroll fixed dimensions (offset 10,60 to 210,700) - 700px height assumes 768px+ viewport; content unscrollable if taller
  - @ `/home/user/openTTS/scenes/main.tscn:211-214`
  - fix: Remove hardcoded offset_bottom=700. Use anchors_preset=9 (left, full height), custom_minimum_size=Vector2(200, 0), and set size_flags_vertical=Control.SIZE_EXPAND_FILL. Ensure horizontal_scroll_mode=0 (already set), but test with 10+ buttons in LeftPanelVBox to confirm no vertical overflow. Add child_entered_tree signal to dynamically expand VBox if needed.
- **[medium]** ModelInfoPopup custom_minimum_size 300x200 may not fit on 720px-wide displays
  - @ `/home/user/openTTS/scripts/model_info_popup.gd:116, 143`
  - fix: Clamp sizes: panel.custom_minimum_size = Vector2(minf(300, viewport.get_visible_rect().size.x * 0.6), minf(200, viewport.get_visible_rect().size.y * 0.5)). Also wrap 'info' RichTextLabel in a ScrollContainer if weapon/equipment lists could exceed 120px height.
- **[medium]** InfoLabel (top-right corner) positioned at offset_left=-300 - assumes viewport wider than 300px; unreachable on very narrow windows
  - @ `/home/user/openTTS/scenes/main.tscn:157-158`
  - fix: Change anchors_preset from 1 (top-right) to 4 (top-left), offset_left=10. Or keep top-right but clamp: offset_left = -minf(300, viewport.get_visible_rect().size.x - 50) to ensure 50px margin from right edge.
- **[medium]** OPRImportDialog army_preview RichTextLabel lacks scroll on long unit lists - content may be hidden
  - @ `/home/user/openTTS/scripts/opr_import_dialog.gd:128-138`
  - fix: army_preview.custom_minimum_size already set to Vector2(0, 150), but scroll_following=true may not show all content. Ensure 'custom_minimum_size = Vector2(0, minf(150, viewport.size.y / 3))' and wrap in explicit ScrollContainer or ensure bbcode-rendered text respects fit_content=true. Test with 10+ unit army lists.

### UI Responsiveness Audit - Niemandsland HUD and Dialogs


- **[high]** LeftPanelScroll fixed height clips on small screens (1366x768)
  - @ `/home/user/openTTS/scenes/main.tscn:207-214`
  - fix: Replace offset_bottom = 700 with size_flags_vertical = EXPAND_FILL. Current 640px absolute height overflows 768px tall viewports. Use anchors_preset = 8 (center-stretch) and margin bindings.
- **[high]** DiceRollerPanel negative offset clips on 1366px wide monitors
  - @ `/home/user/openTTS/scenes/main.tscn:491-504`
  - fix: offset_left = -430, offset_right = -10 creates 420px panel. On 1366px: panel at x=936-1356 (off-screen). Use anchor_right = 1.0, margin_right = 10, and dynamic width clamping in main.gd.
- **[high]** FileDialog sizes hardcoded to 800x500 without viewport adaptation
  - @ `/home/user/openTTS/scenes/main.tscn:559-614`
  - fix: Six FileDialog nodes all size = Vector2i(800, 500). On 1366x768, leaves only 566px width. Implement adaptive sizing in main.gd _ready(): get_viewport().size_changed.connect(_on_window_resized) and resize dialogs to 80% of viewport (clamped 600-1200 width, 400-900 height).
- **[medium]** StartupMenu buttons fixed to 400px width, unscalable on 4K
  - @ `/home/user/openTTS/scenes/startup_menu.tscn:114-170`
  - fix: All 5 menu buttons custom_minimum_size = Vector2(400, 56). On 4K (3840px), buttons are 10% of width (too small). Use size_flags_horizontal = EXPAND_FILL and clamp in startup_menu.gd: btn.custom_minimum_size = Vector2(clamp(viewport_width * 0.35, 300, 500), 56).
- **[medium]** InfoLabel anchors top-right with fixed offset, clips on wide screens
  - @ `/home/user/openTTS/scenes/main.tscn:152-172`
  - fix: anchors_preset = 1 (top-right), offset_left = -300. On 4K: text overflows left. Use anchors_preset = 3 (top-left with margin) or PanelContainer with auto-sizing based on content_height().
- **[medium]** PerformanceLabel fixed offset ignores ultrawide viewport center
  - @ `/home/user/openTTS/scenes/main.tscn:174-190`
  - fix: offset_left = -100, offset_right = 100 (200px width) hardcoded. On ultrawide 3440x1440, readability drops. Bind to viewport: clamp(viewport_width * 0.15, 150, 400) in main.gd _ready() with size_changed signal.
- **[medium]** Map layout title font_size = 26 fixed, unscalable across resolutions
  - @ `/home/user/openTTS/scenes/map_layout.tscn:65-69`
  - fix: Title hardcoded to 26px font size. Too large on 1366x768, too small on 4K. Implement dynamic scaling in map_layout.gd: title_label.add_theme_font_size_override('font_size', int(clamp(get_viewport().size.x / 60, 18, 36))).
- **[medium]** MapLayout FileDialogs hardcoded to 600x400, no margin safety on 1366x768
  - @ `/home/user/openTTS/scenes/map_layout.tscn:252-268`
  - fix: SaveFileDialog and LoadFileDialog both size = Vector2i(600, 400). Add in map_layout.gd _ready(): get_viewport().size_changed.connect(_on_viewport_resized) to set adaptive sizes with margins.
- **[high]** Main HUD lacks global size_changed listener for resize responsiveness
  - @ `/home/user/openTTS/scripts/main.gd (missing handler)`
  - fix: Unlike cinematic_intro.gd (line 264-266), main.gd has no size_changed event listener. Window resize (fullscreen toggle, manual drag) does not reposition/resize left_panel_scroll or dice_roller_panel. Add in main.gd _ready(): vp.size_changed.connect(_on_viewport_resized) and implement _on_viewport_resized() to recalculate all panel sizes, offsets, and dialog dimensions.

### Niemandsland Tactical HUD UI Consistency Audit

Comprehensive audit of hardcoded colors, font sizes, styleboxes, and radii throughout the Niemandsland codebase that bypass the global theme system (HudTokens/GlassmorphismTheme). Found 78 hardcoded overrides across 15+ screens that violate the sleek tactical-HUD design language (deep-navy panels, cyan/amber accents, Orbitron headers, mono labels). Total 11 scripts and 2 scene files require migration to use centralized design tokens.
- **[high]** Startup Menu hardcoded colors and font sizes
  - @ `scripts/startup_menu.gd:22, 189, 231, 355-356, 419, 475-479; scenes/startup_menu.tscn:97`
  - fix: Replace ACCENT_COLOR const (0.0, 0.85, 1.0) with HudTokens.CYAN; Replace Color(0.6, 0.6, 0.6) info label with HudTokens.TEXT_MUTED; Replace exit button colors with HudTokens.DANGER; Move font_size 24 hardcodes to theme constants; Use HudTokens palette for wordmark/ember colors
- **[high]** Casts Dialog color and size inconsistencies
  - @ `scripts/casts_dialog.gd:144, 177, 186, 195, 204`
  - fix: Replace Color(0.7, 0.7, 0.7) with HudTokens.TEXT_MUTED; Create HudTokens constants for dialog sizes (250x180 panel, 40x40 buttons, 80 label width) instead of hardcoded Vector2 values
- **[high]** Wounds Dialog color and size duplicates
  - @ `scripts/wounds_dialog.gd:166, 173, 206, 215, 224`
  - fix: Replace Color(0, 0, 0, 0.4) background with HudTokens.SUNKEN or new opacity token; Use same HudTokens size constants as casts_dialog (duplicate code indicates shared design token missing)
- **[high]** Radial Menu hardcoded colors and wrong radius
  - @ `scripts/radial_menu.gd:21-28, 144, 150, 154, 172, 173`
  - fix: Replace @export colors with HudTokens references (CYAN, AMBER, DANGER); Remove duplicate ACCENT_COLOR and DESTRUCTIVE_COLOR consts; Change set_corner_radius_all(8) to HudTokens.RADIUS (4); Replace draw-time colors Color(0.92, 0.98, 1.0), Color(0.03, 0.045, 0.07, 0.95), Color(0.55, 0.6, 0.68) with HudTokens tokens
- **[high]** Map Layout Editor widespread color and font size overrides
  - @ `scripts/map_layout.gd:373, 381, 392, 400, 407, 530, 557-559, 597-635, 1044, 1051, 1420; scenes/map_layout.tscn:113, 149, 171, 183, 211, 222`
  - fix: Replace all add_theme_color_override with hardcoded colors (0.85, 0.87, 0.92 = TEXT; 0.7, 0.73, 0.8 = TEXT_MUTED; 0.9, 0.92, 0.96 = TEXT; 0.95, 0.97, 1.0 = TEXT) with theme references; Change set_corner_radius_all(8) to HudTokens.RADIUS (4); Move font_size overrides (16, 13, 36, 12) to named theme constants; Replace scene modulate opacity Color(1,1,1,0.15/0.2) with theme opacity token
- **[medium]** OPR Import Dialog hardcoded font sizes
  - @ `scripts/opr_import_dialog.gd:59, 65, 108, 124, 130`
  - fix: Create HudTokens.LABEL_SIZE (12) and HudTokens.SMALL_SIZE (11) constants; Replace add_theme_font_size_override hardcoded 12, 11, 12 with named constants; Replace custom_minimum_size Vector2(0, 150) with HudTokens.PREVIEW_HEIGHT constant
- **[medium]** Lighting Panel font size and dimension hardcodes
  - @ `scripts/lighting_panel.gd:73, 93, 128, 159, 181, 206`
  - fix: Move font_size_override(16) to theme constant; Create HudTokens constants for label widths (150, 60) and spacing values instead of hardcoded Vector2
- **[medium]** Marker Dialog hardcoded custom_minimum_size values
  - @ `scripts/marker_dialog.gd:353, 378, 395`
  - fix: Create HudTokens.DIALOG_WIDTH (360), HudTokens.SCROLL_HEIGHT (90) constants and replace hardcoded Vector2(360, 0), Vector2(0, 90)
- **[medium]** Table Size Dialog color inconsistency
  - @ `scripts/table_size_dialog.gd:106`
  - fix: Replace Color(0.55, 0.58, 0.66, 0.85) with HudTokens.TEXT_MUTED (matches semantics of muted quote text)
- **[medium]** Radial Menu Controller status marker colors not in palette
  - @ `scripts/radial_menu_controller.gd:96-100, 1104, 1126, 1146`
  - fix: Move status marker color definitions to HudTokens (WoundMarker red, CasterMarker purple, ShakenMarker blue, FatiguedMarker orange); Replace font_size hardcodes (24, 72, 72) with HudTokens.MARKER_LABEL_SIZE and HudTokens.BIG_MARKER_SIZE constants
- **[medium]** Main HUD color inconsistencies and missing theme derivation
  - @ `scripts/main.gd:1047, 1339, 1411, 2483, 2490, 2497, 2505, 2592`
  - fix: Replace Color(0.55, 0.85, 1.0) dice preset with HudTokens.CYAN; Replace Color(0.7, 0.7, 0.7) network status with HudTokens.TEXT_MUTED; Replace all add_theme_color_override with Color(0.85, 0.87, 0.92) / Color(0.7, 0.73, 0.8) with HudTokens.TEXT / TEXT_MUTED references (ensure consistency)

## Key sources

- [Review: Art Direction for AAA UI (Don X, on Omer Younas' DICE LA talk)](https://medium.com/@donxu29/review-art-direction-for-aaa-ui-d5f82ab0005b)
- [Design tokens – Material Design 3](https://m3.material.io/foundations/design-tokens)
- [Depth with Purpose: How Elevation Adds Realism and Hierarchy](https://designsystems.surf/articles/depth-with-purpose-how-elevation-adds-realism-and-hierarchy)
- [Material Design 3 — Easing and duration (tokens & specs)](https://m3.material.io/styles/motion/easing-and-duration/tokens-specs)
- [Godot Engine — Tween class reference (TRANS_*, EASE_*, set_parallel, bind_node)](https://docs.godotengine.org/en/stable/classes/class_tween.html)
- [prefers-reduced-motion CSS media feature — MDN (WCAG 2.3.3)](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion)
- [Xbox Accessibility Guideline 112: UI navigation (keyboard/controller, focus, back/quit)](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/112)
- [Xbox Accessibility Guideline 102: Contrast (4.5:1 / 3:1 / 7:1 tiers)](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/102)
- [WCAG 2.2 — What's New (2.4.11/2.4.12/2.4.13 focus, 2.5.8 target size)](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/)
- [Godot Engine docs — Keyboard/Controller Navigation and Focus](https://docs.godotengine.org/en/stable/tutorials/ui/gui_navigation.html)
- [Multiple resolutions — Godot Engine docs (stretch, content_scale_factor, DPI, min window)](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)
- [Using Containers — Godot Engine docs (size flags, custom_minimum_size, overflow)](https://docs.godotengine.org/en/stable/tutorials/ui/gui_containers.html)
- [ScrollContainer — Godot Engine class reference (follow_focus, ensure_control_visible)](https://docs.godotengine.org/en/stable/classes/class_scrollcontainer.html)
- [XCOM 2 — Hannah Montgomery, UI Designer (tactical command-console UI breakdown)](https://jamuidesign.com/xcom-2/)
- [Godot CanvasItem — custom 2D drawing API (corner brackets, accent lines, segmented meters)](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html)
- [Godot StyleBoxFlat — borders, corner_radius, anti_aliasing, shadow caveats](https://docs.godotengine.org/en/stable/classes/class_styleboxflat.html)
- [Using Fonts — Godot Engine docs (MSDF, hinting, subpixel, mipmaps)](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html)
- [Godot issue #86563 — Text gets blurry with canvas_items stretch mode](https://github.com/godotengine/godot/issues/86563)
- [Progressive Disclosure (Nielsen Norman Group)](https://www.nngroup.com/articles/progressive-disclosure/)
- [UI Strategy Game Design Dos and Don'ts (Game Developer)](https://www.gamedeveloper.com/design/ui-strategy-game-design-dos-and-don-ts)
- [Designing Empty States in Complex Applications — Nielsen Norman Group](https://www.nngroup.com/articles/empty-state-interface-design/)
- [Best Practices for Game UI Sounds — SFX Engine](https://sfxengine.com/blog/best-practices-for-game-ui-sounds)
- [AudioStreamRandomizer — Godot Engine documentation](https://docs.godotengine.org/en/stable/classes/class_audiostreamrandomizer.html)
- [Capitalization — PatternFly UX Writing (sentence case)](https://www.patternfly.org/ux-writing/capitalization/)
- [Coloring for Colorblindness (Wong CVD-safe palette tool)](https://davidmathlogic.com/colorblind/)
