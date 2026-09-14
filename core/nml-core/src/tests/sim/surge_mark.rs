use super::*;
use crate::state::Weapon;

// ---- sweep C 2026-09-14, row `Surge Mark` — the once-per-activation pick ----
//
// The book: "Once per activation, before attacking, pick one enemy unit
// within 18" in line of sight, which friendly units get Surge against once."
// The registry models the name as a plain Surge alias, so both layers make the
// bearer a permanent extra-hits machine against EVERYONE — melee and shooting,
// every attack, the whole game — and no enemy is ever marked (the pick is dead
// data). The fix (epoch 44): the entry becomes a vs_target mark like its
// siblings (the Precision marks #929, the Piercing marks #936) — the attack
// seam places it, the Surge fold reads the grant against the marked target
// only, and the exchange spends it. Below 38 every recorded corpus replays the
// permanent self-Surge.

/// The carrier: an "a" whose rules are swapped in, read off the REAL registry
/// (aof/chivalrous_kingdoms prints Surge Mark — the boost_aura_tail stamp
/// test's own pair), so the RED leg exercises today's Surge-alias entry and
/// the GREEN leg the flipped vs_target mark.
fn surge_carrier(rules: &[&str], rules_epoch: u32) -> UnitStatic {
    let p = Profile {
        unit_id: "a".into(),
        name: "a".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1, 1],
        model_count: 2,
        weapons: vec![
            Weapon {
                name: "Rifle".into(),
                range: 24.0,
                attacks: 8,
                count: 1,
                ap: 0,
                rules: vec![],
            },
            Weapon {
                name: "Blade".into(),
                range: 0.0,
                attacks: 1,
                count: 1,
                ap: 0,
                rules: vec![],
            },
        ],
        special_rules: rules.iter().map(|s| s.to_string()).collect(),
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "aof".into(),
        faction_folder: "chivalrous_kingdoms".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    };
    let mut reg = crate::rules::Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, rules_epoch)
}

fn surge_mark_carrier(rules_epoch: u32) -> UnitStatic {
    surge_carrier(&["Surge Mark"], rules_epoch)
}

/// `buff_line` with the carrier on "a" (eight shots so the unmodified 6s are
/// always in the roll) and a hardened "b" — three models of three wounds each,
/// so the marked volley can never wipe the target before the spent one fires.
fn surge_mark_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    let carrier = surge_mark_carrier(rules_epoch);
    let mut a = UnitStatic { model_count: 2, wounds_max: vec![1, 1], ..carrier };
    a.shoot = vec![gun("Rifle", 8, 24)];
    statics[0] = a;
    statics[2].wounds_max = vec![3, 3, 3];
    st.wounds[2] = vec![3, 3, 3];
    (st, statics)
}

/// The defense rolls the volley drew, summed — the hit count the saves ran on
/// (the pierce_mark_grants precedent reads the save batches' targets; the
/// Surge bonus lives in the same count).
fn defense_count(r: &ShootResult) -> i64 {
    r.rolls.iter().filter(|x| x.kind == "defense").map(|x| x.count).sum()
}

/// `run_buff` with the record's own `rules_epoch` (Seams::default() rides
/// epoch 0, which no mark leg under test here lives at).
fn run_surge_epoch(
    st: &State,
    statics: &[UnitStatic],
    action: &Action,
    seed: i64,
    epoch: u32,
) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(
        statics,
        st,
        action,
        &terrain,
        Seams { rules_epoch: epoch, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .unwrap()
}

/// NEW leg at the frozen `EPOCH_44_SURGE_MARK`: the bearer's volley marks the
/// enemy it attacks — the mark is placed at the attack seam, the granted
/// "Surge" reaches the volley fold (seed 9's eight faces carry two unmodified
/// 6s), and the exchange SPENDS it, so the second volley on the same target
/// rolls no bonus and the mark does not re-place within the round. OLD leg at
/// the frozen `EPOCH_34_UNSTOPPABLE_MARK` (the epoch immediately below this
/// bump): the recorded permanent self-Surge replays — both volleys carry the
/// bonus, and the mark never exists.
#[test]
fn surge_mark_hits_the_marked_target_once_at_epoch_41_and_never_the_unmarked() {
    use crate::acts::{EPOCH_43_BATTLEBORN_ROLL, EPOCH_44_SURGE_MARK};
    // ----- epoch 44: the fix -----
    let (st, statics) = surge_mark_line(EPOCH_44_SURGE_MARK);
    let action = buff_action(Some("b"));
    let (next1, r1) = run_surge_epoch(&st, &statics, &action, 9, EPOCH_44_SURGE_MARK);
    assert_eq!(next1.vs_mark_round[0], st.round, "the attack seam placed the mark");
    let v1 = defense_count(&r1);
    assert!(
        r1.log.iter().any(|l| l.contains("Surge Mark")),
        "rules-must-log: the consumed mark names itself, got {:?}",
        r1.log
    );
    let (next2, r2) = run_surge_epoch(&next1, &statics, &action, 9, EPOCH_44_SURGE_MARK);
    let v2 = defense_count(&r2);
    assert!(v1 > v2, "the marked volley out-hits the spent one: {} vs {}", v1, v2);
    assert!(v2 >= 1, "the spent volley still rolls its plain hits");
    assert_eq!(
        next2.vs_mark_round[0], next1.vs_mark_round[0],
        "once per round: the mark does not re-place"
    );

    // ----- the OLD leg: the permanent self-Surge replays below 44 -----
    let old = EPOCH_43_BATTLEBORN_ROLL;
    let (st34, statics34) = surge_mark_line(old);
    let (next34a, r34a) = run_surge_epoch(&st34, &statics34, &action, 9, old);
    let (_, r34b) = run_surge_epoch(&next34a, &statics34, &action, 9, old);
    assert_eq!(
        defense_count(&r34a),
        defense_count(&r34b),
        "the old leg: every volley carries the permanent self-Surge, the mark never exists"
    );
    assert_ne!(
        next34a.vs_mark_round[0], st34.round,
        "the old leg: no mark is ever placed"
    );
}

/// The stamp leg through the REAL registry: at 44 the entry is the vs_target
/// mark — no self-Surge on any profile, shooting or melee — and below 44 the
/// recorded permanent self-Surge replays on both. The rule-less control pins
/// the absent leg (the boost_aura_tail precedent).
#[test]
fn surge_mark_stamps_itself_below_41_and_never_again() {
    use crate::acts::{EPOCH_43_BATTLEBORN_ROLL, EPOCH_44_SURGE_MARK};
    let at_44 = surge_mark_carrier(EPOCH_44_SURGE_MARK);
    assert!(
        !at_44.shoot[0].surge && !at_44.melee[0].surge,
        "the mark is not a self-Surge at 44, neither facet"
    );
    assert_eq!(at_44.utility_buffs.len(), 1, "the mark reads as the vs_target Utility Buff");
    assert!(at_44.utility_buffs[0].vs_target, "the mark rides the attack seam");

    let at_old = surge_mark_carrier(EPOCH_43_BATTLEBORN_ROLL);
    assert!(
        at_old.shoot[0].surge && at_old.melee[0].surge,
        "below 44 the recorded self-Surge replays, both facets"
    );
    assert!(at_old.utility_buffs.is_empty(), "below 44 the mark cannot exist yet");

    let none = surge_carrier(&[], EPOCH_44_SURGE_MARK);
    assert!(!none.shoot[0].surge && !none.melee[0].surge, "no rule, no surge");
}
