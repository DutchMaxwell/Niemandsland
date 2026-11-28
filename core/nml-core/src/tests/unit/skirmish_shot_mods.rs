//! `EPOCH_109_SKIRMISH_SHOT_MODS` (plan SKIRMISH-CATALOGUE): Precision Charge and the unit-borne Imprecise read through the
//! REAL catalogues (`ctx_for` / `UnitStatic::build_for` on assets/solo) in the skirmish books as in their mass-battle
//! siblings from 109, and not below it. RED: the rows removed from the skirmish maps -> the 109 leg reads false / 0; the
//! `since_epoch` gate removed from `RulesMap::lookup` -> the 108 leg reads true / -1.
use super::*;
use crate::acts::{EPOCH_108_BLAST_EVEN, EPOCH_109_SKIRMISH_SHOT_MODS};

fn prof(system: &str, faction: &str, rules: &[&str], weapons: &str) -> Profile {
    let mut p: Profile = serde_json::from_str(&format!(r#"{{"unit_id":"u","name":"U","weapons":{weapons}}}"#)).unwrap();
    (p.game_system, p.faction_folder, p.model_count) = (system.into(), faction.into(), 5);
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    p
}

fn reg() -> Registries { Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR"))) }

const RIFLE: &str = r#"[{"name":"Rifle","range":24,"attacks":1,"count":1,"rules":[]}]"#;
const BLADE: &str = r#"[{"name":"Blade","range":0,"attacks":1,"count":1,"rules":[]}]"#;

/// (Precision Charge read, the Imprecise unit's rifle to-hit bonus) for a system's carrier faction at `epoch`.
fn reads(system: &str, charger: &str, imprecise: &str, epoch: u32) -> (bool, i64) {
    let pc = ctx_for(&mut reg(), &prof(system, charger, &["Precision Charge"], BLADE), epoch).precision_charge_base;
    let st = UnitStatic::build_for(&mut reg(), &prof(system, imprecise, &["Imprecise"], RIFLE), epoch);
    (pc, st.shoot[0].hit_bonus)
}

const CARRIERS: [(&str, &str, &str); 4] =
    [("gf", "orc_marauders", "robot_legions"), ("gff", "orc_marauders", "robot_legions"),
     ("aof", "dwarves", "shadow_stalkers"), ("aofs", "dwarves", "shadow_stalkers")];

#[test]
fn from_109_the_skirmish_books_read_precision_charge_and_imprecise_as_their_siblings() {
    for (sys, charger, imprecise) in CARRIERS {
        assert_eq!(reads(sys, charger, imprecise, EPOCH_109_SKIRMISH_SHOT_MODS), (true, -1), "{sys} at 109");
    }
}

#[test]
fn below_109_the_skirmish_books_stay_as_recorded() {
    for (sys, charger, imprecise) in CARRIERS {
        let want = if sys.ends_with('s') || sys == "gff" { (false, 0) } else { (true, -1) };
        assert_eq!(reads(sys, charger, imprecise, EPOCH_108_BLAST_EVEN), want, "{sys} at 108");
    }
}

/// Every Imprecise faction the 109 rows name reads -1 from 109 (gff: the four Firefight books that carry it).
#[test]
fn every_skirmish_imprecise_faction_reads_its_minus_one() {
    for f in ["alien_hives", "eternal_dynasty", "goblin_reclaimers", "robot_legions"] {
        assert_eq!(reads("gff", "orc_marauders", f, EPOCH_109_SKIRMISH_SHOT_MODS).1, -1, "gff {f}");
    }
}

/// A catalogue row's `since_epoch` is always a named epoch gate: today only 109 exists in the committed maps.
#[test]
fn every_since_epoch_in_the_catalogues_is_a_named_gate() {
    let root = format!("{}/../../assets/solo", env!("CARGO_MANIFEST_DIR"));
    for s in ["gf", "gff", "aof", "aofs", "aofr"] {
        let text = std::fs::read_to_string(format!("{root}/rules_mechanics_{s}.json")).unwrap();
        for (i, _) in text.match_indices("\"since_epoch\"") {
            let tail = &text[i + 14..];
            let n: u32 = tail.trim_start_matches([':', ' ']).split(|c: char| !c.is_ascii_digit()).next().unwrap().parse().unwrap();
            assert_eq!(n, EPOCH_109_SKIRMISH_SHOT_MODS, "{s}: since_epoch {n} is no named gate");
        }
    }
}
