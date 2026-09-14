use super::*;
use crate::acts::CURRENT_RULES_EPOCH;
use crate::state::Weapon;

// ---- TEST WAVE 2026-09-15 — the two `growth markers` rows of
// proven_vs_read_part2.tsv (Piercing Frenzy, Precision Growth) plus the
// boost bases' fifth row, Rapid Blink Boost (its window is the activation
// placement, not a save/to-hit). One test per row, by the rule's EXACT NAME
// through the REAL gf registry (the #489 lesson), at `CURRENT_RULES_EPOCH`
// — no epoch bump, nothing changes behaviour. The growth fixture rides the
// buff line: a one-model registry carrier shooting a 20-dice rifle (seed
// 27's 14 hits guarantee the save batch), the marker count preset the way
// the epoch-6 growth wave presets it.

fn growth_carrier(faction: &str, rules: &[&str]) -> Profile {
    Profile {
        unit_id: "a".into(),
        name: "a".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![Weapon {
            name: "Rifle".into(),
            range: 24.0,
            attacks: 20,
            count: 1,
            ap: 0,
            rules: vec![],
        }],
        special_rules: rules.iter().map(|s| s.to_string()).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: faction.into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    }
}

fn registry_unit(faction: &str, rules: &[&str]) -> UnitStatic {
    let mut reg = crate::rules::Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &growth_carrier(faction, rules), CURRENT_RULES_EPOCH)
}

/// The buff line with the carrier in the shooter slot, patched down to the
/// carrier's own single model.
fn volley_line(us: UnitStatic) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    statics[0] = us;
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.radii[0] = vec![IN2M];
    st.wounds[0] = vec![1];
    st.alive[0] = 1;
    (st, statics)
}

/// One fixture activation at `CURRENT_RULES_EPOCH` on a fresh tray.
fn run(st: &State, statics: &[UnitStatic], action: &Action, seed: i64) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics,
        st,
        action,
        &terrain,
        Seams { rules_epoch: CURRENT_RULES_EPOCH, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .unwrap()
}

/// Piercing Frenzy (gf dark_elf_raiders, `on_kill`, `max_markers: 2`,
/// `ap_per_marker: 1`): the bearer's own marker count times the entry's
/// rate — `growth_bonus_of`'s AP half reads 1 and 2 at one and two markers
/// (hit half 0, the entry prints no hit rate), and the volley's save target
/// shows it end to end: Defense 4+ reads 4+/5+/6+ at 0/1/2 markers.
#[test]
fn piercing_frenzy_pays_one_ap_per_marker_at_zero_one_and_two() {
    let us = registry_unit("dark_elf_raiders", &["Piercing Frenzy"]);
    assert_eq!(us.growth.len(), 1, "the exact name reads as the Growth Markers entry");
    assert_eq!(us.growth[0].name, "Piercing Frenzy");
    assert!(us.growth[0].on_kill, "the kill trigger");
    assert_eq!(us.growth[0].max_markers, 2, "the entry's own cap");
    assert_eq!(us.growth[0].ap_per_marker, 1, "the entry's own rate");
    assert_eq!(us.growth[0].hit_per_two, 0, "no hit rate on this entry");

    let (mut st, statics) = volley_line(us);
    for markers in [0i64, 1, 2] {
        st.growth_markers[0] = markers;
        st.round = 3;
        let (ap, hit) = growth_bonus_of(&statics, &st, 0);
        assert_eq!((ap, hit), (markers, 0), "{} marker(s): the entry's own rates", markers);
        let (_, shot) = run(&st, &statics, &buff_action(Some("b")), 27);
        assert_eq!(
            shot.rolls[1].target,
            4 + markers,
            "{} marker(s): AP(+{}) moves Defense 4+ to {}+",
            markers,
            markers,
            4 + markers
        );
    }
}

/// Precision Growth (gf infected_colonies, `per_round`, `max_markers: 4`,
/// `hit_per_two: 1`): the tick banks one marker per ROUND at the bearer's
/// own activation (two HOLD activations bank two markers, `growth_round`
/// gating a repeat), and the entry's per-TWO rate pays +1 to hit per pair —
/// the volley's attack target reads 4+ at 0 and 1 markers, 3+ at 2.
#[test]
fn precision_growth_pays_one_hit_per_two_markers_and_ticks_per_round() {
    let us = registry_unit("infected_colonies", &["Precision Growth"]);
    assert_eq!(us.growth.len(), 1, "the exact name reads as the Growth Markers entry");
    assert_eq!(us.growth[0].name, "Precision Growth");
    assert!(us.growth[0].per_round, "the round trigger");
    assert_eq!(us.growth[0].max_markers, 4, "the entry's own cap");
    assert_eq!(us.growth[0].hit_per_two, 1, "the entry's own per-two rate");
    assert_eq!(us.growth[0].ap_per_marker, 0, "no AP rate on this entry");

    let (mut st, statics) = volley_line(us);
    st.round = 1;
    let (next1, _) = run(&st, &statics, &buff_action(None), 11);
    assert_eq!(
        (next1.growth_markers[0], next1.growth_round[0]),
        (1, 1),
        "the per-round tick banks one marker at the bearer's own activation"
    );
    let mut st2 = next1;
    st2.round = 2;
    let (next2, _) = run(&st2, &statics, &buff_action(None), 12);
    assert_eq!(next2.growth_markers[0], 2, "a second round banks the second marker");

    for (markers, want) in [(0i64, 4i64), (1, 4), (2, 3)] {
        let mut stv = st.clone();
        stv.round = 3;
        // Hold the per-round tick off (the round gate reads this exact pair):
        // these volleys pin the RATE per marker count, not the tick.
        stv.growth_round[0] = 3;
        stv.growth_markers[0] = markers;
        let (_, shot) = run(&stv, &statics, &buff_action(Some("b")), 27);
        assert_eq!(
            shot.rolls[0].target, want,
            "{} marker(s): {} pair(s) -> {}+ to hit",
            markers,
            markers / 2,
            want
        );
    }
    let mut st3 = next2;
    st3.round = 3;
    let (_, shot) = run(&st3, &statics, &buff_action(Some("b")), 27);
    assert_eq!(shot.rolls[0].target, 3, "the two ticked markers are the pair that pays: 3+");
}

/// The Bounding activation hop's line: `hop_line` is place_d3.rs's shape —
/// a lone carrier at the origin, an objective 10" up +x drawing the
/// strictly-closer placement, an empty board.
fn hop_line(rules: &[&str]) -> (State, Vec<UnitStatic>) {
    let (mut st, _) = dangerous_line();
    for j in 1..4 {
        st.positions[j] = vec![];
        st.radii[j] = vec![];
        st.wounds[j] = vec![];
        st.alive[j] = 0;
    }
    st.objectives = vec![crate::state::Objective { pos: [10.0 * IN2M, 0.0, 0.0], owner: 0 }];
    (
        st,
        vec![
            registry_unit("elven_jesters", rules),
            UnitStatic { name: "ah".into(), ..Default::default() },
            UnitStatic { name: "b".into(), ..Default::default() },
            UnitStatic { name: "bh".into(), ..Default::default() },
        ],
    )
}

/// One fresh-sim ADVANCE far past the destination on the small board — a
/// placement needs a table.
fn run_hop(st: &State, statics: &[UnitStatic]) -> (State, ShootResult) {
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics,
        st,
        &advance_to(20.0),
        &small_board(),
        Seams { rules_epoch: CURRENT_RULES_EPOCH, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .unwrap()
}

/// Rapid Blink Boost (gf elven_jesters, the `Bounding` primitive's Boost —
/// `dice_count: 2`, `place_d3_plus: 0`): the activation placement's
/// longest-reach scan takes the UPGRADE (2 dice x 2 + 0 beats the base
/// "Rapid Blink" alias's 1 x 2 + 0), the hop rolls its own 2d3 from the
/// seeded stream BEFORE the move, and the rules-must-log line names
/// "Rapid Blink Boost". Without the Boost the base alias's single die wins
/// the scan and the line names "Rapid Blink".
#[test]
fn rapid_blink_boost_wins_the_bounding_scan_with_two_dice() {
    let (st, statics) = hop_line(&["Rapid Blink", "Rapid Blink Boost"]);
    let (next, shot) = run_hop(&st, &statics);
    let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
    assert!(
        shot.log.iter().any(|l| l.starts_with("Rapid Blink Boost:") && l.contains("rolled")),
        "rules-must-log: the Boost wins the longest-reach scan and names itself: {:?}",
        shot.log
    );
    assert!(moved_in > 7.5 && moved_in < 12.5, "the 6\" band plus a 2d3 hop: {}\"", moved_in);

    let (st0, statics0) = hop_line(&["Rapid Blink"]);
    let (next0, shot0) = run_hop(&st0, &statics0);
    let moved0 = (next0.positions[0][0][0] - st0.positions[0][0][0]) / IN2M;
    assert!(
        shot0.log.iter().any(|l| l.starts_with("Rapid Blink:") && l.contains("rolled")),
        "no Boost: the base alias's single die wins the scan: {:?}",
        shot0.log
    );
    assert!(moved0 > 6.5 && moved0 < 9.5, "the base 6\" band plus one d3: {}\"", moved0);
}
