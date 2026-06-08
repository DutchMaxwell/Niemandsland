# Niemandsland — Vision & Roadmap

*The definitive strategic roadmap. Authored by the vision committee, grounded in committee research (the OPR online-play landscape, what remote wargamers need, the competitor/VTT deep-dive, technical feasibility, and the go-to-market/IP frame) and reconciled against the codebase at version `0.3.1-alpha`.*

*This is the target the project steers by. When a decision is unclear, it should be resolved in favour of THE ZIELMARKE below.*

---

## 1. Executive summary & THE ZIELMARKE

OnePageRules (OPR) has ~48,000 Patreon members and is the #1 wargaming Patreon, yet invests **zero** in online play — all of its digital effort goes into list-building (Army Forge), leaving the "play the game online" layer wide-open whitespace. The only way to play OPR remotely today is a brittle, partly-delisted, single-maintainer Tabletop Simulator (TTS) mod chain: a 7-step Army Forge → third-party web tool → TTS importer → hunt-your-own-3D-models gauntlet, behind a $19.99 × 2 Steam paywall, plagued by broken model links and clunky measuring. Niemandsland is — on the evidence — the **only purpose-built, OPR-native virtual tabletop in existence**, and almost everything needed to win this category is already in the repository (one-click Army Forge import, 113 IP-safe content-addressed 3D models on R2, inch-accurate measuring, a coherency visualizer, a pure-WebSocket relay that is already browser-compatible). The strategy is therefore not to *build more* but to *wire, harden, and prove* the end-to-end journey that is broken everywhere else — while holding the deliberate no-rules-automation design line, because the research shows players abandon VTTs for social/friction reasons and explicitly do **not** want a video game.

> ### THE ZIELMARKE (north-star)
>
> **Two OnePageRules players who have never met — on two different continents, on a weeknight — paste their Army Forge links, share a 6-character code, and play a complete Grimdark Future or Age of Fantasy game from deployment to last turn, together in one browser tab, in under five minutes to first model on the table. Free. No Steam. No install. No account. No tool-chain. No missing-model errors, ever. And if either player's connection blips — including the host's — the game pauses and resumes instead of dying.**
>
> We have arrived when a non-technical OPR player can do all of that with **zero out-of-app instructions**, and we can prove it with a single unedited screen recording of two real strangers, filmed three sessions in a row without an edit. If we cannot film that clip, we are not done.

---

## 2. Judging the three visions

Three north-star visions were submitted. All three independently verified the same load-bearing facts against the codebase and converged on the same opening move; they differ in *ambition surface* and *where they spend the scarce solo-maintainer + AI-agent capacity*.

| Criterion (weight) | Vision 1 — Pragmatist | Vision 2 — Platform Builder | Vision 3 — Experience Designer |
|---|---|---|---|
| **Impact on researched user needs** (35%) | 9 — nails the single biggest gap (one integrated path, link+friend → playing) | 8 — adds retention (content + LFG) but defers the proven core wins | 9 — directly targets the *abandonment* drivers (friction, "impersonal", LOS/placement) |
| **Feasibility for solo + AI team** (30%) | 10 — "wire existing parts, not build subsystems"; cuts ruthlessly | 6 — community moderation + a content pipeline is a heavy ongoing burden for one person | 8 — mostly polish/wiring, but the UX-perfection scope can sprawl |
| **Defensibility vs TTS & rivals** (20%) | 8 — reliability + free + OPR-native is a real moat | 9 — the flywheel deepens the moat with every contributed asset (Vassal's lesson) | 8 — "out-delight, don't out-feature" is a durable, hard-to-copy edge |
| **Risk** (15%, higher = lower risk) | 9 — smallest surface, cheapest-blocker-first, explicit cut list | 5 — Tabletop Playground died of the empty-library chicken-and-egg; LFG needs critical mass | 7 — web visual-tier and "buttery UX" can over-run a solo budget |
| **Weighted score** | **9.15** | **6.95** | **8.30** |

**Verdict.** The **Pragmatist core wins** — it is the only plan whose sequencing matches solo-maintainer reality (cheapest blocker first, ruthless cut list, no new subsystems) and whose Definition of Done is a single witnessed acceptance test rather than a feature pile. But it is too austere on two points the research proves matter:

- The **Experience Designer** is right that players abandon VTTs for *experience* reasons, not missing features (loss of tactile/social warmth, clunky primitives), and that Niemandsland's edge is to **out-delight** the one game TTS serves clunkily — not just to be reliable. Its grafts: a designed (not broken-looking) web visual tier, best-in-class measuring/placement, and surfacing the already-existing `los_rules.gd` and `undo_manager.gd`.
- The **Platform Builder** is right that what converts *curious → regular* is reliably finding an opponent and fresh content — retention, not onboarding — and that server-side model-bundling is the structural escape from the empty-mod-library trap that killed Tabletop Playground. Its grafts: the lightweight LFG/"open table" + Discord-clean share link, and map-layout sharing as the cheapest user-generated content.

The synthesis below takes the **Pragmatist spine and acceptance-test discipline**, grafts the **Experience Designer's delight bar** into the core loop, and grafts the **Platform Builder's lightest retention levers** (shareable/discoverable games, shareable maps) — while deferring the heavy community-content ecosystem to *beyond 1.0*, because a solo maintainer cannot moderate a living ecosystem while the core loop is still being hardened.

---

## 3. Strategic thesis — why this is the right bet

**The whitespace is real, the moat already exists in the repo, and the remaining work is wiring — not invention.**

1. **The market is wide-open and OPR will not fill it.** OPR has ~48k Patreon members but every 2025–2026 announcement (Ready-to-Play Lists, PDF View, Army Forge Labs) is about list-building; there is no official VTT, no Foundry OPR module, and no stated intent to build one. *Niemandsland complements OPR — it is "the table for the lists you build in Army Forge."*
   → *Unmet need: a purpose-built, zero-setup online OPR table (Landscape findings 1–2; GTM finding 6).*

2. **The incumbent is brittle and decaying.** The dominant OPR-online path is a 7-step chain (Army Forge → Netlify tool → TTS importer mod → DIY models); the flagship "complete OPR collection" was **delisted** for guideline violations, and the most-used importer mod (~3,780 subs) is effectively abandoned ("the project's dead"), with documented bugs — wound counters that render "a massive oval" on round bases, broken link-pasting, missing rules. We are not fighting a strong incumbent; we are replacing a single-maintainer hobby project running on fumes.
   → *Unmet need: a reliable, actively-maintained, one-step alternative to the decaying TTS chain (Landscape findings 3–4; Needs finding 2).*

3. **Every differentiator is already built or one wiring step away.** One-click Army Forge import (full per-model `ModelInstance`/`GameUnit` data, equipment distribution, coherency); 113 IP-safe CC-BY-SA models that load from content-addressed R2 and **never rot** (the structural fix to TTS's #1 chronic pain — broken/expired asset links); inch-native measuring; base-correct, physics-free placement so minis **stay exactly where dropped** (TTS's worst failure for minis); synced wounds/Fatigue/Shaken/Activated/caster tokens; a free relay with 6-char room codes. The transport is already `WebSocketPeer` (the one networking class Godot supports in HTML5 export) with zero ENet, and `asset_download_manager.gd` already streams + sha256-verifies over HTTPRequest (works in-browser). The two real gaps are **host-drop reconnect** (fully specced in `relay/HOST_RECONNECT.md`) and **wiring the web build to stream R2 models** (no new subsystem).
   → *Unmet needs: never-broken included models; one-step import; precise physics-free placement; zero-install browser entry (Competitor findings 2–5; Tech findings 1, 3, 12).*

4. **The free, no-Steam, in-browser entry occupies a quadrant nobody holds.** TTS = paid + install ($20 × 2); Vassal = free + install + dated UI; TaleSpire = paid seats; Warhall = "pretty steep" subscription with paywalled features; Tabletopia/BGA = browser but not wargame-physics. *Free + browser + wargame-grade 3D is empty.* This aligns exactly with OPR's "free and accessible" brand and removes the paywall that filters out the curious.
   → *Unmet need: zero-cost, zero-install entry for the second player (Needs finding 5; Competitor findings 6–7; Tech finding 4).*

5. **The audience is large, growing, ideologically aligned, and reachable in one place.** ~85% of OPR players play at home; ~70% 3D-print; **over 50% are not interested in physical minis** — a home-based, proxy-friendly, model-light audience that an on-demand-model, free, zero-install table serves better than any incumbent can. The community is concentrated on Discord/Reddit/Patreon, was burned by BattleScribe's abandonment, and now *explicitly values* an open, non-rent-seeking tool. Single-digit penetration of one Discord = thousands of users.
   → *Unmet needs: an OPR-native home; a trustworthy non-abandonable open tool; help finding an opponent (Needs finding 8; Competitor findings 11–13; GTM findings 5, 8).*

6. **The deliberate no-automation design is correct and must be protected.** The documented churn drivers are friction, "feels impersonal," and "can't find a game" — *never* "needs more automation." Players want a table they apply the rules to (like TTS), not an AI game (like Eternals). The removed ~5,500-line AI/battle-sim was the right call. *Out of scope by design and reaffirmed here: turn/phase/activation automation, combat/damage/save resolution, AI opponent.*
   → *Unmet need: presence and spectacle to narrow the "impersonal" gap, NOT automation (Needs finding 3; Landscape finding 11).*

**The moat, stated plainly:** Niemandsland can legally *ship the models with the product* (CC-BY-SA, AI-generated, visibly distinct from GW silhouettes) where TTS and Warhall structurally cannot; it owns the OPR domain (Army Forge import, coherency, deployment zones, inch measuring) that a generic sandbox will never build; and it is free + browser-reachable where every rival is gated. Depth in one niche, owned end-to-end, beats breadth — the lesson of Vassal's two-decade survival and Tabletop Playground's death.

---

## 4. Phased roadmap (0.4 → 1.0 → beyond)

**Sequencing rule:** each phase makes one more line of THE ZIELMARKE reliably true, ordered by *experience leverage per hour*, doing the **cheapest blocker first**. Nothing here builds a new subsystem; everything wires, hardens, or polishes parts that already exist. The OUT-OF-SCOPE line (no rules automation / AI opponent) is absolute in every phase.

---

### 0.4 — "The game doesn't die." (Reliability foundation)
*Theme: a session survives the real world, so the hero flow is safe to show publicly. Highest leverage because a dying room kills every word-of-mouth recommendation.*

| # | Deliverable | User need served (cited) |
|---|---|---|
| 1 | **Stand up a staging Fly relay app** before touching anything multiplayer. | De-risks every later relay change; the gating risk is *operational*, not technical (Tech finding 7). The single most capacity-protecting move in the plan. |
| 2 | **Implement host-drop reconnect** per `relay/HOST_RECONNECT.md` (`HOST_REJOIN_WINDOW_SECONDS`, `host_disconnected_at`, send guests `host_paused` instead of deleting the room, rehost as `peer_id 1`, drop the client's reconnect refusal). Deploy to staging first; gate on the existing 30 pytest cases. | "Room dies if host drops" is the last open reliability gap; the reliability bar remote players actually judge a VTT on (Tech finding 7; GTM finding 9). |
| 3 | **Robust undo + seamless save/resume across a disconnect.** Wire "resume the autosave on rejoin" using existing `undo_manager.gd` (already MP-rebroadcasting), `save_manager.serialize_game_state()` and the `.nml` format. | Frictionless undo + save/resume are concrete, cheap wins where TTS visibly frustrates (multi-click undo with load stalls; host must reload an autosave) (Needs finding 9). |
| 4 | **Measure the relay's 1 MB message cap against a full 120-mini state sync.** A late-joiner gets the whole board in one `serialize_game_state()` message; a full army may approach the cap. Cheap to measure now, expensive to discover at 1.0. | De-risks the synced full-game loop and web perf (Tech finding 10). |

**Exit criterion:** On the staging relay, a host can kill their connection mid-game and rejoin within the window with full state intact while the guest sees "host reconnecting…" (not a dead room); a session can be saved, closed, and resumed to completion on another night; the largest realistic state sync fits the relay message cap (or is chunked). *(THE ZIELMARKE: "pauses and resumes instead of dying" + "play a complete game".)*

---

### 0.5 — "A free stranger joins in a browser." (The zero-install wedge)
*Theme: prove the quadrant nobody occupies. This is the marketing hero moment and the structural acquisition advantage.*

| # | Deliverable | User need served (cited) |
|---|---|---|
| 1 | **Validate WebSocket multiplayer in-browser and turn it on.** The transport is already `MultiplayerPeerExtension` over `WebSocketPeer` with zero ENet/threads — the project's own `docs/WEB_EXPORT.md` underestimates this. **Test it, don't assume it away**; likely near-zero code change. | "Send a link, opponent plays in-browser, no purchase" — the sharpest pitch in the category (Tech finding 1; Needs finding 5). |
| 2 | **Stream R2 models to the web build.** GLBs are already excluded from the web `.pck` (which would balloon to ~1.3 GB); drive the web build through `asset_download_manager.gd` (HTTPRequest + sha256, works in-browser) + a **download-progress UI** + **LRU cache eviction** for the smaller browser storage cap. No fallback cylinders in a real game. | Never-broken, included models — the structural fix to TTS's #1 chronic pain; armies arrive already modelled (Tech finding 3; Competitor findings 2 & 9). |
| 3 | **Design the deliberate "web-grade" visual tier.** Web forces `gl_compatibility` (no SSAO/glow/soft-shadows; desktop is Forward+ with SSAO on). Ship a flat-lit tier with a **non-glow selection/hover affordance** (rim/outline) so the browser build looks *intentional, not broken*. Treat this as a design deliverable with its own DoD screenshot. | Closing the "feels impersonal / looks broken" gap with spectacle, not automation; the experience guardrail for the whole web pivot (Tech finding 2; Needs finding 3). |
| 4 | **Fix the itch.io deploy config** (`BUTLER_API_KEY` + `ITCH_TARGET` are unset). A 10-minute secrets task that unblocks the entire web GTM. | Zero-install browser onboarding is the lowest possible adoption barrier and the launch on-ramp (GTM finding 9; Tech finding 12). |

**Exit criterion:** A second player opens a shared link in a browser (no Steam, no purchase, no account, no download prompt), reaches first pixel in under 30 s on a mid laptop, joins a room by 6-char code, and plays a synced game with full R2-streamed models and a coherent flat-lit look. *(THE ZIELMARKE: "one browser tab… free… no Steam, no install, no account".)*

---

### 0.6 — "It loads every time, fast, and the primitives feel like silk." (Moat hardening + delight)
*Theme: make the one-step import and the wargaming primitives bulletproof and best-in-class, because reliability AND delight are the moat vs the decaying TTS chain.*

| # | Deliverable | User need served (cited) |
|---|---|---|
| 1 | **Performance pass: 120 minis + terrain at 60 fps, web + Safari/iPad.** Bake Basis-Universal/KTX2 textures (a web low-VRAM variant), decimate LODs, and **MultiMesh-batch identical minis** (currently spawned individually — the highest-leverage web-perf win). Use the existing 1000-mini perf harness in `main.gd` to test. | Performance is a documented session-killer at full army count; Safari/iOS is the early compatibility risk (Needs finding 7; Tech finding 6). |
| 2 | **Harden the one-step Army Forge import to "just works."** Defensive caching, integration versioning, graceful degradation, and a **conservative 1–2 req/s rate limit** — the OPR API is undocumented/reverse-engineered and can change without notice. | One-step import that doesn't hard-fail the onboarding clip; the hero feature and the largest silent technical/relationship risk (GTM finding 2). |
| 3 | **Fix the exact bugs OPR-in-TTS users complain about, as visible proof points:** correct **wound/token display on round bases** (TTS makes "a massive oval" that blocks measuring), coherency visible *live during movement*, base-snapped placement. | The precise, named pains that make minis-in-TTS feel clunky (Needs finding 2; Landscape finding 4; Competitor finding 4). |
| 4 | **Buttery primitives + true line-of-sight.** Surface the already-existing `los_rules.gd` (Asgard height categories; grid query in `terrain_overlay.gd`) as a one-click "can A see B?" check with a visible model-eye line. Sub-pixel nudge, snap-to-base, persistent measuring "ghost" rings. Match Warhall's measurement/movement UX as the bar to clear. | Precise placement + true LOS is the single thing every general VTT does badly and TTS has *no* automation for (Needs finding 4; Competitor finding 4). |
| 5 | **Shareable room link + Discord-clean presence + a minimal "open table" list.** Make "Invite" produce a link that unfurls cleanly in Discord; add the thinnest public list of open rooms. | Reliably getting a willing opponent is what converts curious → regular; the social step nobody handles (Landscape findings 7–8; Needs finding 6). |

**Exit criterion:** Two full armies import in one step with zero missing-model errors and hold 60 fps on a 5-year-old laptop and on iPad/Safari; measuring, base-snapped placement, live coherency, and a one-click LOS check are demonstrably smoother than TTS; an invite link posts cleanly to Discord and a stranger can find and join an open table. *(THE ZIELMARKE: "under five minutes… no missing-model errors, ever".)*

---

### 1.0 — "Definition of Done, witnessed." (Proof, the IP gate, launch)
*Theme: no new subsystems — polish, the legal gate, and proof. THE ZIELMARKE acceptance test IS the 1.0 gate.*

| # | Deliverable | User need served (cited) |
|---|---|---|
| 1 | **Run THE ZIELMARKE acceptance test with two real strangers** from the OPR Discord — full game, browser, under 5 min to first model, host-drop survived, three sessions in a row, unedited. This recording *is* the 1.0 gate. | The "link + friend → playing in under 5 minutes" journey that is broken everywhere else (Landscape finding 9). |
| 2 | **Clear the IP/legal gate (mandatory, not housekeeping):** the `docs/PRE_RELEASE_LICENSING.md` lawyer review; the **git-history scrub of any previously-bundled OPR data** (public ≠ licensed — OPR data is all-rights-reserved); a hard art pass so minis lean *visibly away from GW silhouettes*; an airtight CC-BY-SA provenance trail; keep the IP-strict faction gate mandatory. | GW is at peak litigiousness against 3D-model makers (200+ defendants, $10.2M judgment, 2025–26); the biggest exposure is minis that look like GW units (GTM findings 1 & 4). |
| 3 | **Faction completeness pass:** cover the popular Grimdark Future armies first, then Age of Fantasy, as IP-safe CC-BY-SA models, via the existing Model Forge pipeline (39 design-language profiles, content-addressed R2). | Own the OPR-on-a-3D-table niche end-to-end; every faction's models is the unglamorous completeness that defines the niche (Competitor finding 13). |
| 4 | **Trust & sustainability surface:** prominent "not affiliated with OPR" disclaimer; a transparent published hosting-cost page (Fly.io ~$2–5/mo, R2 egress free); a Ko-fi/optional-supporter framing that **never gates core play**; a courtesy heads-up to OPR before launch. | A trustworthy, non-abandonable open tool funded ethically — exactly what the BattleScribe-burned community values (GTM findings 3, 5, 7). |
| 5 | **Seed launch in OPR's own channels:** a 60-second "paste your link → play a remote game in 2 minutes" clip; recruit 1–2 OPR battle-report YouTubers to play a remote game on it. Launch web + itch.io; **hold Steam** until robust. | Growth comes from embedding in the community and creators, not store algorithms (GTM finding 9). |

**Exit criterion:** THE ZIELMARKE recording exists, unedited, three sessions; the IP gate is signed off; the popular Grimdark Future factions are covered; the tool is publicly launched on web + itch.io with a sustainability surface and an OPR courtesy notice. **This is "we have arrived."**

---

### Beyond 1.0 (one line)
**Light the community-content flywheel** — open the Model Forge faction-submission pipeline (one YAML → models → manifest) with an in-app asset browser, shareable map layouts from the existing editor, and richer LFG/matchmaking — so every contributed asset makes the next player's table stronger (the Platform-Builder bet, deferred until the core loop is proven and a solo maintainer can sustain moderation). Still no rules automation, ever.

---

## 5. Success metrics / KPIs per phase

The North-Star metric across all phases: **completed-game rate** = % of started multiplayer sessions that reach a player-marked "game over" (or ≥ 4 turns). Everything else is a leading indicator of that.

| Phase | Primary KPI(s) | Target | How to instrument |
|---|---|---|---|
| **0.4** | Host-reconnect success rate; save/resume success rate; relay crash-free sessions | ≥ 95% of host blips recover within window; ≥ 99% relay sessions crash-free | Relay-side structured logs (room lifecycle, `host_paused`/rejoin events) already in the Python relay; pytest gate on the 30 existing cases; a local two-instance smoke test before each staging deploy. |
| **0.5** | Time-to-first-model (TTFM) for a browser guest; second-player drop-off in onboarding funnel; web-build start success rate across Chrome/Firefox/Safari | TTFM ≤ 30 s mid laptop; ≥ 80% of link-openers reach a joined table; web start succeeds on the 3 major browsers | A privacy-light, opt-in client event ping (anonymous, no PII): link-opened → models-streaming → joined-room → first-model-spawned, with timestamps; funnel reconstructed relay-side from room-join events. |
| **0.6** | Frame rate at 120 minis (desktop + iPad/Safari); missing-model error rate; import success rate; median import latency | ≥ 60 fps desktop / ≥ 45 fps iPad; **0** missing-model errors in a real game; ≥ 98% imports succeed | In-app perf overlay logging fps at spawn-count milestones (reuse `main.gd` harness); client counter for any GLB load failure or fallback-shape spawn (alert if > 0); import success/latency logged per attempt with the rate-limiter. |
| **1.0** | **Completed-game rate**; 7-day return rate; weekly active rooms; infra cost/month; first-1000-users count | ≥ 50% completed-game rate; ≥ 25% of players return within 7 days; infra ≤ $10/mo; 1,000 users from OPR channels | Relay aggregates rooms/week and game-over markers; return rate from anonymous install-id over a rolling window; Fly.io + Cloudflare R2 dashboards for cost (published transparently); itch.io + relay counts for the user tally. |

**Instrumentation principles (ethos-aligned):** all telemetry is anonymous, aggregate, opt-in, and self-hosted (relay logs + an opt-in client ping) — never a third-party tracker, never PII, never login-walled. Publish the hosting cost and the headline KPIs openly to build trust, mirroring UnitCrunch/Foundry.

---

## 6. Top 5 strategic risks + mitigations

1. **Technical — the browser build (MP, model-streaming, or 60 fps with 120 textured GLBs) proves harder than the transport suggests.** Safari/iOS WebGL2 quirks, browser storage caps, and `gl_compatibility` perf are genuine unknowns; THE ZIELMARKE's zero-install wedge rides on all three.
   *Mitigation:* 0.5's first task is to **test, not assume** (the relay is WebSocket-clean and the downloader uses HTTPRequest, so it *should* work). If browser MP/perf proves intractable, the **desktop build still satisfies the entire loop minus the zero-install wedge** — degrade THE ZIELMARKE to "free desktop download," do not sink the project. Test iPad/Safari early because it is the long-pole compatibility risk (Tech findings 1, 6).

2. **IP/legal — Games Workshop, not OPR, is the clear-and-present danger,** landing squarely on the AI-generated, grimdark-adjacent minis. GW's 2024–26 litigation wave against 3D-model/STL makers has real teeth (200+ defendants, a $10.2M judgment, 200+ Cults3D takedowns).
   *Mitigation:* keep the **IP-strict faction gate mandatory** (no GW/OPR names, no "grimdark," humanoid-only cues, positive-only prompts); steer art *visibly away from GW silhouettes*; keep an airtight CC-BY-SA provenance trail; treat the `docs/PRE_RELEASE_LICENSING.md` lawyer review and the **git-history scrub of previously-bundled OPR data** as hard 1.0 launch blockers, not housekeeping. Public OPR data is **not** licensed — never relax the "API-only, never bundle" posture (GTM findings 1, 4).

3. **Community/dependency — the unofficial OPR API breaks or rate-limits the hero import flow.** No official API exists; endpoints can change without notice; hammering OPR's servers is the fastest way to lose the privilege and any goodwill.
   *Mitigation:* aggressive caching, a versioned integration layer, graceful degradation, a conservative 1–2 req/s rate limit, and a **friendly courtesy dialogue with OPR before launch** — while designing the roadmap to survive *without* any official endorsement (OPR keeps fan projects at arm's length by design) (GTM findings 2, 3).

4. **Sustainability — funding/ethos drift.** The competitor's loudest complaint is paywalled core features and subscription fatigue (Warhall, TaleSpire seats); betraying the free ethos would forfeit the exact moat that aligns with OPR's brand and the BattleScribe-burned community's values.
   *Mitigation:* keep the simulator **100% free and open**; fund it via transparent "keep the relay + R2 on" Ko-fi/Patreon donations (infra is genuinely ~$2–5/mo; R2 egress is free; Fly scales to $0 idle) plus genuinely optional, never-core-gating extras (curated premium model packs, table themes) à la UnitCrunch. **Never** a subscription, login-wall, or play-gate (GTM findings 5, 7, 10).

5. **Maintainer capacity — a solo + AI-agent team stalls the live-ops loop, or over-scopes.** The riskiest line item is any redeploy of the single live relay that currently serves real games; a botched push kills the active session. Over-scoping the platform/UX ambitions is the secondary trap (Tabletop Playground died technically-superior but over-extended).
   *Mitigation:* the **staging Fly relay (0.4, task 1)** is the single most important capacity-protecting move — it converts every high-stakes blind deploy into a routine one. Keep every phase scoped to "wire existing parts," hold the explicit cut list (no in-app matchmaking beyond a thin open-table list, no touch-first mobile, no heavy community ecosystem before 1.0), and defer the content flywheel to *beyond 1.0* (Tech findings 7, 12; Competitor finding 5).

---

## 7. The immediate next 3 moves

1. **Stand up a staging Fly relay app** (a duplicate of the production `fly.toml`, separate app name). This unblocks and de-risks *every* subsequent multiplayer change and is the prerequisite for safely shipping host-reconnect. Nothing else touches the relay until this exists.

2. **Implement host-drop reconnect** exactly as specced in `relay/HOST_RECONNECT.md` (Task #43), deploy it to the staging relay, and gate it on the existing 30 pytest cases plus a local two-instance smoke test. This closes the last open reliability gap — the one that currently kills rooms — and makes the most important line of THE ZIELMARKE true.

3. **Test WebSocket multiplayer in an actual browser export.** Build the web target, open it in Chrome and Safari, and attempt a real two-peer game against a desktop host through the staging relay. This is a cheap, high-impact experiment that likely turns the project's single biggest assumed-hard unknown into a near-term deliverable — and it tells us immediately whether the zero-install wedge is days away or needs a fallback to "free desktop download."

---

*Load-bearing files referenced (all verified this session, version `0.3.1-alpha`):*
- `/home/andreaskesberg/openTTS/relay/HOST_RECONNECT.md` — host-reconnect spec (0.4)
- `/home/andreaskesberg/openTTS/relay/test_relay_server.py` — 30 pytest cases gating relay changes
- `/home/andreaskesberg/openTTS/scripts/relay_multiplayer_peer.gd` — WebSocket transport, ENet-free (browser-ready)
- `/home/andreaskesberg/openTTS/scripts/asset_download_manager.gd` — R2 HTTPRequest + sha256 streaming (web-capable)
- `/home/andreaskesberg/openTTS/scripts/los_rules.gd` + `terrain_overlay.gd` — line-of-sight, exists today (0.6)
- `/home/andreaskesberg/openTTS/scripts/undo_manager.gd` — MP-rebroadcasting undo (0.4)
- `/home/andreaskesberg/openTTS/scripts/save_manager.gd` — `.nml` + `serialize_game_state()` (save/resume + full-state sync)
- `/home/andreaskesberg/openTTS/assets/model_manifest.json` — 113 models, content-addressed, `base_url https://assets.akesberg.de/`
- `/home/andreaskesberg/openTTS/tools/model_forge/design_languages/` — 39 IP-safe faction profiles (1.0 completeness, beyond-1.0 flywheel)
- `/home/andreaskesberg/openTTS/docs/PRE_RELEASE_LICENSING.md` — IP/legal gate (1.0 blocker)
- `/home/andreaskesberg/openTTS/docs/WEB_EXPORT.md` — renderer caveats + the likely-wrong "MP won't work in-browser" line (re-test)
- `/home/andreaskesberg/openTTS/project.godot` — Forward+/SSAO desktop, `gl_compatibility` web
