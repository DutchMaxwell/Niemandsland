# Standalone sweep E — measured rows for 53 rule names resting on older prose audits

Measured 2026-09-14 on the farm box (read-only; no code changed), at `d60ba065` (origin/main).
Scope: constitution C8 lane A stage 2 — the 53 names of `farm/wave6/sweep_lists/sweep_E.txt`
(previously only "mentioned" in the older audit prose), each now given a measured row:
registry / core / table / verdict.

Method per name: (1) registry entry from `assets/solo/rules_mechanics_<system>.json` (keyed
system/faction; the most representative entry shown), (2) CORE = the Rust core's dispatch of that
primitive or the name (`core/nml-core/src/`), read, not grepped, (3) TABLE = the Godot runtime's
handler (`scripts/main.gd`, `scripts/solo/`), read, (4) verdict
∈ {CORRECT, DERIVES, CORE-ONLY, TABLE-ONLY, DIVERGES, INERT, N/A}.

Book text: the registry is deliberately text-free (its `_meta.contract` says "no rule texts") and no
rulebook PDFs exist on this box, so every row reads **NO BOOK TEXT ON DISK** — the printed-word
column is deferred to the laptop, which has the PDFs. A DIVERGES/-ONLY/INERT row says in one
sentence what a player would notice.

**Tally: 30 CORRECT · 13 DERIVES · 1 TABLE-ONLY · 9 DIVERGES · 0 CORE-ONLY · 0 INERT · 0 N/A.**
The 10 non-OK rows are listed in "Fix first" at the bottom. Every citation below was verified by
reading the cited lines.

## The 53 rows (TAB-separated: name / book text / registry primitive+params / CORE / TABLE / verdict)

```
+1 to Defense	NO BOOK TEXT ON DISK	Shielded | defense_bonus=1 [gf/wormhole_daemons_of_war]	CORE core/nml-core/src/sim.rs:2582 name-stamps the Shielded alias; combat.rs:145-147 folds +1 defense vs non-spell hits (const +1, combat.rs:26)	TABLE scripts/main.gd:5577 Shielded wave reads defense_bonus into the defense-parts seam	CORRECT
AP	NO BOOK TEXT ON DISK	AP | rating=X [gf/common]	CORE core/nml-core/src/unit.rs:1132 AP(X) stamped into ShootProfile.ap; dice.rs:377-387 save_target = Defense+AP	TABLE scripts/solo/ai_combat_math.gd:126-127 save_target(defense, ap) on both dice and EV paths	CORRECT
Agile	NO BOOK TEXT ON DISK	Quick | advance_mod=1, rush_mod=2 [gf/dark_elf_raiders]	CORE core/nml-core/src/unit.rs:4722 "Agile" in move_rule_mods_of; advance_mod/rush_mod read :4744-4745 into move bands	TABLE scripts/movement_range_controller.gd:159-161 Quick-primitive registry pass adds advance_mod/rush_mod	CORRECT
Aircraft	NO BOOK TEXT ON DISK	Aircraft | cannot_be_charged, cannot_seize, straight_move, target_range_penalty_in=12, solo_move_in=30 [gf/common]	CORE core/nml-core/src/unit.rs:1835 aircraft flag; sim.rs:3138 (-12" range penalty), sim.rs:1593 (cannot seize), sim.rs:1841 (excluded from melee)	TABLE scripts/solo/solo_controller.gd:5746 target_range_penalty_in from registry; solo_move_in :5829; straight flight logged scripts/main.gd:1004	CORRECT
Ambush	NO BOOK TEXT ON DISK	Ambush | (none) [gf/common]	CORE core/nml-core/src/deployment.rs:217 ambush specs held out of placement, in reserve (:1197)	TABLE scripts/solo/solo_controller.gd:9395-9399 unit_has_ambush (:10735) stages carriers into ambush_reserve	CORRECT
Ambush Beacon	NO BOOK TEXT ON DISK	Ambush | beacon_in=6 [gf/dao_union]	CORE core/nml-core/src/unit.rs:3807-3809 beacon_radius_in from beacon_in; arrival waiver deployment.rs:2712-2750	TABLE scripts/main.gd:11055-11062 beacon circle waives the 9" enemy-distance rule; radius read solo_controller.gd:10336-10337	CORRECT
Ambushing Piercing Shot	NO BOOK TEXT ON DISK	Ambush | counts_as=Ambush [gf/jackals]	CORE core/nml-core/src/unit.rs:3803-3805 counts_as stamps reserve deploy + arrival AP(+1) (sim.rs:2633-2634, dice.rs:1091)	TABLE scripts/solo/solo_controller.gd:10741-10747 counts_as claims the reserve via params_claim_ambush (rules_registry.gd:237-238)	CORRECT
Angelic Blessing	NO BOOK TEXT ON DISK	Regeneration | all_models=true, ignore_target=6, ignore_target_spell=4 [aof/kingdom_of_angels]	CORE core/nml-core/src/unit.rs:1926-1953 Regeneration alias wave folds ignore_target/ignore_target_spell/all_models into the MIN; dice.rs:1170	TABLE scripts/main.gd:6747-6759 same primitive walk in _solo_regen_pick	DERIVES
Angelic Blessing Boost	NO BOOK TEXT ON DISK	Regeneration | all_models=true, ignore_target_spell=2, spell_only=true [aof/kingdom_of_angels]	CORE core/nml-core/src/unit.rs:1926-1953 same alias wave; spell wounds ignore on 2+	TABLE scripts/main.gd:6747-6759 same walk; spell-wound key picks ignore_target_spell	DERIVES
Armor	NO BOOK TEXT ON DISK	Armor | best_of=true, defense_value=X, rating=X [gf/common]	CORE core/nml-core/src/unit.rs:2024-2025 Armor rating stamped; armored_defense combat.rs:261-266 (defense=min(D,X))	TABLE scripts/main.gd:5674-5682 unit_rule_active + rating into AiCombatMath.armored_defense (ai_combat_math.gd:547-550)	CORRECT
Artillery	NO BOOK TEXT ON DISK	Artillery | hold_only=true, over_in=9, shooter_hit_bonus=1, target_hit_penalty=2 [gf/common]	CORE core/nml-core/src/unit.rs:2149 artillery flag; combat.rs:117-127 +1 shooter / -2 target over 9" (consts 22-23)	TABLE scripts/main.gd:5784-5786 has_special_rule("Artillery") into ai_combat_math.gd:235-239 (+1/-2 over 9")	CORRECT
Bane	NO BOOK TEXT ON DISK	Bane | bypass_regen=true, reroll_save_sixes=true [gf/common]	CORE core/nml-core/src/unit.rs:2509,2521 Bane prefix stamps bane+bypass; dice.rs:400-403 defender save-six re-roll; bypass dice.rs:1143-1170	TABLE scripts/main.gd:6635-6657 _solo_striker_has_bane; re-roll :6601-6605; bypass :7104; params :6666-6670	CORRECT
Bane Mark	NO BOOK TEXT ON DISK	Bane | bypass_regen=true, reroll_save_sixes=true [gf/saurian_starhost]	CORE core/nml-core/src/unit.rs:2521 "Bane Mark" named in the plain-Bane prefix stamp (same sixes re-roll + bypass)	TABLE scripts/main.gd:6648 begins_with("Bane") covers Bane Mark in _solo_striker_has_bane	CORRECT
Bane in Melee	NO BOOK TEXT ON DISK	Bane | bypass_regen=true, reroll_save_sixes=true [gf/common]	CORE core/nml-core/src/unit.rs:2514 melee-scoped prefix arm (2618-2624); dice.rs:399-416 sixes re-roll; bypass dice.rs:1157/:1758	TABLE scripts/main.gd:6650 melee-scoped re-roll (6590-6607); but _solo_ignores_regen (:7104) scans only weapon-printed Bane*	DIVERGES
Bane in Melee Buff	NO BOOK TEXT ON DISK	Bane | bypass_regen=true, reroll_save_sixes=true [gf/human_defense_force]	CORE core/nml-core/src/unit.rs:2514 same "Bane in Melee" prefix arm; melee re-roll + regen bypass on unit-level name	TABLE scripts/main.gd:6650 matches the same begins_with("Bane in Melee") branch for the re-roll; regen bypass stays weapon-prefix-only	DIVERGES
Banner	NO BOOK TEXT ON DISK	Banner | morale_bonus=1, scope=unit [gf/common]	CORE core/nml-core/src/unit.rs:2029 ctx morale_bonus from the named entry (banner_bonus_of :1654-1671); dice.rs:1962 morale target	TABLE scripts/solo/solo_controller.gd:5631 morale_bonus_of reads unit_param + primitive loop; morale test main.gd:8572-8589	CORRECT
Battleborn	NO BOOK TEXT ON DISK	Battleborn | recover_target=4 [gf/battle_brothers]	CORE core/nml-core/src/rollout.rs:550 battleborn_active clears Shaken FREE at round start; die leg :574-580 needs battleborn_recover_target, stamped only for four aliases (unit.rs:1365 — "Battleborn" absent)	TABLE scripts/main.gd:10717 _solo_battleborn_recovery rolls a real tray die, recovers on 4+	DIVERGES
Bestial	NO BOOK TEXT ON DISK	Bane | bypass_regen=false, reroll_save_sixes=true [aof/beastmen]	CORE core/nml-core/src/unit.rs:2554-2568 Bane-alias scan stamps bane off reroll_save_sixes (bypass_regen:false honored :2574-2576); dice.rs:399-416	TABLE scripts/main.gd:6666 _solo_bane_facet_name picks the alias; re-roll :6590-6607; per-alias bypass ai_ev.gd:348-360	DERIVES
Bestial Boost	NO BOOK TEXT ON DISK	Bane | bypass_regen=false, over_in=9, reroll_save_low=5, upgrades=Bestial [aof/beastmen]	CORE core/nml-core/src/unit.rs:5304 stamp_bane_boost by name (gate 4478-4503); window consumed dice.rs:1036 past over_in	TABLE scripts/solo/ai_ev.gd:225 bane_boost_window scans the Bane primitive; applied main.gd:6593-6607	CORRECT
Blast	NO BOOK TEXT ON DISK	Blast | ignores_cover=true, rating=X [gf/common]	CORE core/nml-core/src/combat.rs:545 hits ×= clamp(blast, models); cover skipped :553; rating unit.rs:1143; dice.rs:1015-1016/:1059	TABLE scripts/main.gd:4579 blast_hits ×min(X, models) with cap log; cover skipped :3299/:3136	CORRECT
Bounding	NO BOOK TEXT ON DISK	Bounding | place_d3_plus=1 [gf/eternal_dynasty]	CORE core/nml-core/src/unit.rs:4557 bounding_of reads place_d3_plus; move bands sim.rs:5262/:5320, fresh placement sim.rs:5251	TABLE scripts/solo/solo_controller.gd:1674-1698 longest-D3 alias wave rolls D3 on the seeded RNG; EV bands :5690-5706	CORRECT
Breath Attack	NO BOOK TEXT ON DISK	Breath Attack | ap=1, blast=3, range_in=6.0, trigger_target=2 [gf/alien_hives]	CORE core/nml-core/src/sim.rs:448 tray_breath_attack gated on breath_attack_active (unit.rs:5529); params as consts sim.rs:407-410	TABLE scripts/main.gd:5410-5418 _solo_apply_breath_attack reads range_in/blast/ap/trigger_target; save path :5448-5449	CORRECT
Buccaneer	NO BOOK TEXT ON DISK	Shot Modifier | hit_bonus=1, over_in=9 [aof/sky_city_dwarves]	CORE core/nml-core/src/unit.rs:2889 name-stamped in stamp_shot_modifier; over_in routes +1 into hit_bonus_over9 (:2905-2906); combat.rs:128, dice.rs:829	TABLE scripts/main.gd:5819 Shot Modifier scan with over_in gate (:5826-5828); +hit_bonus :5834-5836	CORRECT
Buccaneer Boost	NO BOOK TEXT ON DISK	Shot Modifier | hit_bonus=1 [aof/sky_city_dwarves]	CORE core/nml-core/src/unit.rs:2890 name-stamped; no over_in → flat hit_bonus (:2908)	TABLE scripts/main.gd:5834 primitive scan; gate=0 so flat +1 at any range	CORRECT
Caster	NO BOOK TEXT ON DISK	Caster | aura_in=18, boost_per_token=1, cast_target=4, rating=X, token_cap=6 [gf/common]	CORE core/nml-core/src/unit.rs:5463 is_caster name-gate grants spells; cast target const 4 (spell.rs:16/:36-38); token cap const 6 (rollout.rs:49/:547); no boost/interference seam (spell.rs:8-9)	TABLE scripts/solo/solo_controller.gd:2807 Caster gate; cast_target :4331; aura_in :4568; boost tokens :4336; cast resolution main.gd:3357-3455	DIVERGES
Casting Buff	NO BOOK TEXT ON DISK	Utility Buff | casting_mod=1, once=true, range_in=12, target=friendly_caster [gf/eternal_dynasty]	CORE core/nml-core/src/sim.rs:1058 tray_utility_buff records casting_mod (record_buff :1078-1097); casting_net_of sim.rs:4086-4105 into cast_phase sim.rs:4210 (EPOCH_6)	TABLE scripts/main.gd:16988 _solo_apply_utility_buffs reads casting_mod (:17036), target/range honored; once-stamp :16978-16980; consumed main.gd:3406/:3451-3452	CORRECT
Casting Debuff	NO BOOK TEXT ON DISK	Utility Buff | casting_mod=-1, needs_los=true, once=true, range_in=18, target=enemy [gf/blessed_sisters]	CORE core/nml-core/src/sim.rs:4086 casting_net_of sums Utility-Buff casting_mod (stamped unit.rs:3602; picked via utility_targets sim.rs:1140 honoring range/LOS/max_targets)	TABLE scripts/main.gd:3452 cast phase clamps by recorded casting_mod; record picked at :17037 via _solo_apply_utility_buffs (:16987)	CORRECT
Changebound	NO BOOK TEXT ON DISK	Stealth | applies_charged=true, hit_penalty=1, over_in=9 [gf/change_disciples]	CORE core/nml-core/src/unit.rs:1290 Stealth-alias scan reads hit_penalty/over_in/applies_charged (:1304-1306); combat.rs:130, dice.rs:1328 (charged melee leg)	TABLE scripts/main.gd:5724 _solo_hit_mod_info Stealth-alias loop applies -1 past the over_in gate	DERIVES
Changebound Boost	NO BOOK TEXT ON DISK	Stealth | applies_charged=true, hit_penalty=1, upgrades=Changebound [gf/change_disciples]	CORE core/nml-core/src/unit.rs:1304 same alias leg; no over_in → 0.0; combat.rs:132 treats over_in<=0 as unconditional -1	TABLE scripts/main.gd:5724 same alias loop; :5734 gate<=0.0 applies -1 at any range	DERIVES
Clan Warrior	NO BOOK TEXT ON DISK	Surge | extra_attack=true [gf/eternal_dynasty]	CORE core/nml-core/src/unit.rs:2336 Surge-alias loop stamps surge_attack (:2352); dice.rs:229 surge_attack_hits	TABLE scripts/solo/ai_ev.gd:309 Surge-alias loop stamps surge_attack; extra attack dice main.gd:4546	DERIVES
Counter	NO BOOK TEXT ON DISK	Counter | impact_reduction_per_model=1, strikes_first=true [gf/common]	CORE core/nml-core/src/unit.rs:1154 Counter weapons stamp counter; strike-first dice.rs:1581; impact cut via counter_models (unit.rs:2260) dice.rs:1816	TABLE scripts/solo/solo_controller.gd:7606 has_counter gates strike-first (main.gd:5989); counter_models_of :7620 cuts Impact main.gd:6385	CORRECT
Counter in Melee	NO BOOK TEXT ON DISK	Counter | impact_reduction_per_model=1, strikes_first=true [aof/common]	CORE core/nml-core/src/unit.rs:5113 rule_on_all_models("Counter in Melee") stamps every melee profile counter (dice.rs:1581)	TABLE scripts/main.gd:6003 Counter-alias loop inside _solo_has_counter (:5989) grants strike-first	CORRECT
Counter-Attack	NO BOOK TEXT ON DISK	Counter | impact_reduction_per_model=1, strikes_first=true [gf/dao_union]	CORE core/nml-core/src/unit.rs:5113 rule_on_all_models("Counter-Attack") stamps melee counter (dice.rs:1581)	TABLE scripts/solo/solo_controller.gd:7608 begins_with("Counter") match (plus main.gd:6003 alias loop) grants strike-first	CORRECT
Courage Aura	NO BOOK TEXT ON DISK	Banner | morale_bonus=1 [gf/battle_brothers]	CORE core/nml-core/src/unit.rs:1672 banner_bonus_of alias leg reads morale_bonus; CaptureReads.morale_bonus (unit.rs:1829) into morale target sim.rs:3624	TABLE scripts/solo/solo_controller.gd:5636 morale_bonus_of scans Banner-alias entries for morale_bonus	DERIVES
Courage Buff	NO BOOK TEXT ON DISK	Utility Buff | morale_mod=1, once=true, range_in=12, target=friendly [gf/blessed_sisters]	CORE core/nml-core/src/sim.rs:1038/:1090 utility_targets picks friendly targets, records morale_mod; morale net sim.rs:3625	TABLE scripts/main.gd:17037 Utility Buff loop records morale_mod; morale test main.gd:8581	CORRECT
Courageous	NO BOOK TEXT ON DISK	Banner | morale_bonus=1, scope=unit [gf/alien_hives]	CORE core/nml-core/src/unit.rs:1672 Banner-alias scan reads morale_bonus; sim.rs:3624	TABLE scripts/solo/solo_controller.gd:5636 same generic Banner-alias scan	DERIVES
Cursed Undead	NO BOOK TEXT ON DISK	Regeneration | all_models=true, ignore_target=6 [aof/vampiric_undead]	CORE core/nml-core/src/unit.rs:1943 regen_targets alias wave folds ignore_target=6 into the MIN; dice.rs:1232 apply_regeneration	TABLE scripts/main.gd:6747 Regeneration-alias loop folds ignore_target (all_models-gated) into the regen pick	DERIVES
Cursed Undead Boost	NO BOOK TEXT ON DISK	Regeneration | all_models=true, ignore_target=5 [aof/vampiric_undead]	CORE core/nml-core/src/sim.rs:2541 granted "Cursed Undead Boost" sets the 5+ regen target; printed alias rides unit.rs:1943	TABLE scripts/main.gd:6747 same Regeneration-alias loop folds ignore_target=5	DERIVES
Dash	NO BOOK TEXT ON DISK	Bounding | per_round=true, place_d3_plus=1, timing=end_of_activation [gf/custodian_brothers]	CORE core/nml-core/src/unit.rs:4611 bounding_place_of scans Bounding aliases (:4615); consumed sim.rs:5251 (epoch-26 gate)	TABLE scripts/solo/solo_controller.gd:1684 move-band builder scans Bounding aliases for the longest D3+ placement	DERIVES
Deadly	NO BOOK TEXT ON DISK	Deadly | rating=X, tough_capped=true [gf/common]	CORE core/nml-core/src/combat.rs:245 deadly_multiplier clamps X to target Tough; stamped unit.rs:1141; per-model wounds sim.rs:914-916	TABLE scripts/main.gd:6783 _solo_land_deadly_wounds resolves Deadly(X) per model, no carry-over; EV mirror ai_ev.gd:546	CORRECT
Defense	NO BOOK TEXT ON DISK	Shielded | defense_bonus_from_rating=true, rated [gf/common]	CORE NOT FOUND — the Shielded-alias walk (core/nml-core/src/unit.rs:1771-1786) lists only five alias names; "Defense" absent; no code reads defense_bonus_from_rating	TABLE scripts/main.gd:5577 Shielded-alias walk takes the bonus from the rule's rating when defense_bonus_from_rating is set	TABLE-ONLY
Defense Buff	NO BOOK TEXT ON DISK	Utility Buff | def_mod=1, max_targets=1, once=true, range_in=12, target=friendly [aof/human_empire]	CORE core/nml-core/src/unit.rs:3610 def_mod parsed; recorded sim.rs:1078-1100; folded into save rung sim.rs:2460 / dice.rs:379	TABLE scripts/main.gd:17036-17037 the resolver picks the friendly target but builds the record without def_mod; all-zero row dropped at :3785-3788	DIVERGES
Defense Debuff	NO BOOK TEXT ON DISK	Utility Buff | defense_mod=-1, needs_los=true, once/max_targets=4, range_in=18, target=enemy [gf/ratmen_clans]	CORE core/nml-core/src/unit.rs:3611 defense_mod parsed (epoch 7); landed on the enemy ledger sim.rs:1148/:1057-1058; folded sim.rs:2460 → dice.rs:384	TABLE scripts/main.gd:16988-17015 enemy target picked with range/LOS, but the record (:17036-17037) omits defense_mod; dropped at :3785-3788	DIVERGES
Defensive Frenzy	NO BOOK TEXT ON DISK	Growth Markers | defense_per_marker=1, max_markers=2, on_kill=true [gf/wormhole_daemons_of_war]	CORE core/nml-core/src/sim.rs:2730-2749 growth_on_kill gains a capped marker per kill; defense folded sim.rs:2612-2616 (params unit.rs:3965-3979)	TABLE scripts/main.gd:17569-17586 on-kill marker gain capped at max_markers; facet bonus :17595-17612 into defense-parts seam :5585-5588	CORRECT
Destroyer	NO BOOK TEXT ON DISK	Shred | extra_wound_per_save_one=1 [aof/ogres]	CORE core/nml-core/src/unit.rs:2419-2442 rides the ungated Shred-family walk onto shred_alias; dice.rs:417-424 (+wound per failed save 1)	TABLE scripts/main.gd:4417-4418 unit-level Shred-or-facet stamp marks every profile; extra wound counted :6610-6616	DERIVES
Destroyer Boost	NO BOOK TEXT ON DISK	Shred | extra_wound_per_save_one=1, over_in=9, save_fail_max=2, upgrades=Destroyer [aof/ogres]	CORE core/nml-core/src/unit.rs:2449-2461 upgrades-gated stamp widens the window (shred_low 2, shred_over_in 9); dice.rs:1025-1027	TABLE scripts/main.gd:6610-6616 save-1-only Shred window; no save_fail_max/Boost reader exists in scripts (grep empty)	DIVERGES
Devout	NO BOOK TEXT ON DISK	Surge | bonus_hits_per_six=1 [gf/blessed_sisters]	CORE core/nml-core/src/unit.rs:5131-5148 named Surge arm stamps surge on all profiles; counted dice.rs:984-988	TABLE scripts/solo/ai_ev.gd:280-291 Surge-alias loop stamps Devout by exact name; dice fold main.gd:4527-4538	CORRECT
Devout Boost	NO BOOK TEXT ON DISK	Surge | over_in=9, surge_low=5, upgrades=Devout [gf/blessed_sisters]	CORE core/nml-core/src/unit.rs:2369-2386 upgrade entry (requires carried Devout) stamps surge_low/surge_over_in; 5s past 9" dice.rs:989-991	TABLE scripts/solo/ai_ev.gd:323-329 upgrade entries stamp surge_low/surge_over_in; consumed main.gd:4534-4538	CORRECT
Disintegrate	NO BOOK TEXT ON DISK	Disintegrate | ap_bonus=2, bypass_regen=true, condition=vs_armor, threshold=3 [gf/blessed_sisters]	CORE core/nml-core/src/combat.rs:401-409 vs_armor leg pays ap_bonus at Defense ≤ threshold via cond_ap_of (unit.rs:3994-4014); dice.rs:1126/:1677; bypass_regen never read	TABLE scripts/main.gd:7006-7015 _solo_conditional_ap applies +2 AP vs Defense ≤ 3; :7110-7116 also honors bypass_regen	DIVERGES
Empyrean Spirit	NO BOOK TEXT ON DISK	Stealth | applies_charged=true, hit_penalty=1, over_in=9 [aof/ghostly_undead]	CORE core/nml-core/src/unit.rs:1285-1308 Stealth-alias walk → Ctx 2180-2182; consumed dice.rs:814-828	TABLE scripts/main.gd:5724-5742 same primitive walk with the over-9"/charged gates into the to-hit modifier	DERIVES
Empyrean Spirit Boost	NO BOOK TEXT ON DISK	Evasive | hit_penalty=1 [aof/ghostly_undead]	CORE core/nml-core/src/unit.rs:2049-2058 named gate makes the Boost an unconditional Evasive (stamped 2186-2188) and stands down the base's conditional alias (:2073)	TABLE scripts/main.gd:5709-5717 generic Evasive-alias grants the -1, but no stand-down: the base's over-9" alias still subtracts at :5801	DIVERGES
Entrenched	NO BOOK TEXT ON DISK	Stealth | hit_penalty=2, over_in=9, requires_stationary=true [gf/common]	CORE core/nml-core/src/unit.rs:2068-2069 epoch-7 walk keeps requires_stationary entries in stationary_alias_penalty (:2185); applied dice.rs:816-817; grant leg sim.rs:2488-2496	TABLE scripts/main.gd:5733-5741 requires_stationary checked against moved_round (written :7857/:10201)	CORRECT
Fast	NO BOOK TEXT ON DISK	Fast | advance_mod=2, rush_mod=4 [gf/common]	CORE core/nml-core/src/unit.rs:4900-4905 reads the entry's advance_mod/rush_mod onto both bands; grant leg sim.rs:4902-4903, mods.rs:251-252	TABLE scripts/movement_range_controller.gd:159-162 registry-param pass (+2/+4 name-level fallback :110-115)	CORRECT
```

## Verdict counts

| verdict | count |
|---|---|
| CORRECT | 30 |
| DERIVES | 13 |
| DIVERGES | 9 |
| TABLE-ONLY | 1 |
| CORE-ONLY | 0 |
| INERT | 0 |
| N/A | 0 |

53 rows measured; no name left NOT REACHED.

## The rows I would fix first

1. **Defense Buff / Defense Debuff (DIVERGES — one shared seam).** The table's utility-buff
   resolver picks the target, spends the once-per-round use and announces the buff in the log
   (`scripts/main.gd:17036-17037`), but builds the record without `def_mod`/`defense_mod` so the
   all-zero check drops it at `scripts/main.gd:3785-3788`. A player sees the buff fire and then do
   nothing, while the core raises/lowers the save rung (sim.rs:2460). One seam, two named rules —
   highest player-visible defect density per line fixed.
2. **Battleborn (DIVERGES).** Core clears Shaken free at round start (`rollout.rs:550`) while the
   table rolls a 4+ (`main.gd:10717`); the core's own die leg (`rollout.rs:574-580`) never gets the
   alias stamped (`unit.rs:1365` lists four aliases, not "Battleborn"). Both sides are plausible
   readings of the book, but the two engines disagree in every game fielding Battle Brothers —
   morale outcomes diverge silently.
3. **Empyrean Spirit Boost (DIVERGES).** The core deliberately stands down the base rule when the
   Boost is present (`unit.rs:2049-2058`, one -1 total); the table has no stand-down, so shots past
   9" stack base + Boost to -2 to hit (`main.gd:5801` + `:5709-5717`). A player firing at a
   Boosted wraith feels a −2 that no book reading supports.

Honourable mention: **Disintegrate** (core never reads `bypass_regen`, `combat.rs:401-409`, so
Regeneration still heals what the table would refuse to heal) and **Bane in Melee / Buff** (the
table's regen bypass only scans weapon-printed Bane*, `main.gd:7104`).
