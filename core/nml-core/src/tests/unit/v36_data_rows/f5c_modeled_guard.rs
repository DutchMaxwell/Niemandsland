//! W31-F5c structural guard (release 0.3.15): a book must not carry a rule that the static `modeled` list calls
//! automated while the book has no registry row for it and no explicit by-name entry. The "is it automated?" test
//! reads the `modeled` list for every book, while the readers ask the registry per book, so such a pair silently does
//! nothing: no effect and no "apply manually" note. Twelve pairs hid like that until F5a/F5b (W3.1 gap report, item 1
//! and 3, "Structural"). A new unmapped name on the list would hide the same way, so this test fails on it.
//!
//! Carriers come from the names-only fixture `test/fixtures/book_rule_carriers_v36.json` (per book, the distinct non-core
//! rule names its units carry in the 3.6 army books; no rule text). A pair is resolved when the book's registry section
//! or the system's `common` section names the rule (the gap tool's own definition), or the rule is in `BY_NAME`.
use super::super::*;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// Rules served WITHOUT a row, by name in BOTH engines (a row would only change a log line). Each entry is checked
/// below to stay modeled and carried, so a stale entry cannot hide a future gap.
const BY_NAME: [(&str, &str); 5] = [
    ("Hazardous", "weapon rule: core `weapon_has(w, \"Hazardous\")`, table `_has_rule(w, \"Hazardous\")`"),
    ("Lacerate", "weapon rule: core Bane stamp via `weapon_has(w, \"Lacerate\")`, table `begins_with(\"Lacerate\")`"),
    ("Shielded", "exact name: core `carries([\"Shielded\"])`, table `rule_on_defence_family(.., \"Shielded\")`"),
    ("Regeneration Aura", "import expansion grants the base `Regeneration`, which has a common row"),
    ("Shred when Shooting Aura", "import expansion grants the base `Shred when Shooting`, which has a common row"),
];

/// Pairs the guard still reports on the current data and that an open PR resolves. Empty = nothing is hidden.
/// The F5a pairs landed in #2545 and #2547. The Ravage row of #2549 empties the last entry: when that PR merges, delete
/// it here (the test names every stale entry). The same edit is needed whichever of the two merges second.
const EXPECTED_OFFENDERS: [&str; 1] = ["aof/duchies_of_vinci Ravage"];

fn names_of(v: &Value) -> BTreeSet<String> {
    v.as_array().map(|a| a.iter().filter_map(|n| n.as_str().map(String::from)).collect()).unwrap_or_default()
}

/// Every carried `modeled` name with neither a row (faction section or `common`) nor a by-name entry, as
/// "system/book Rule", sorted.
fn unmapped_modeled(carriers: &Value, regs: &BTreeMap<String, Value>, by_name: &[&str]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for (system, reg) in regs {
        let modeled = names_of(&reg["modeled"]);
        let Some(books) = carriers[system.as_str()].as_object() else { continue };
        for (book, names) in books {
            for name in names_of(names) {
                let row = reg["factions"][book.as_str()].get(&name).is_some() || reg["common"].get(&name).is_some();
                if modeled.contains(&name) && !row && !by_name.contains(&name.as_str()) {
                    out.push(format!("{system}/{book} {name}"));
                }
            }
        }
    }
    out.sort();
    out
}

fn load(rel: &str) -> Value {
    let text = std::fs::read_to_string(format!("{}/{rel}", repo_root())).unwrap_or_else(|e| panic!("{rel}: {e}"));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("{rel}: {e}"))
}

fn repo_regs() -> BTreeMap<String, Value> {
    ["gf", "aof"].iter().map(|s| (s.to_string(), load(&format!("assets/solo/rules_mechanics_{s}.json")))).collect()
}

#[test]
fn f5c_no_book_carries_a_modeled_rule_without_a_row_or_a_by_name_entry() {
    let carriers = load("test/fixtures/book_rule_carriers_v36.json");
    let by_name: Vec<&str> = BY_NAME.iter().map(|(n, _)| *n).collect();
    let found = unmapped_modeled(&carriers, &repo_regs(), &by_name);
    let expected: Vec<String> = EXPECTED_OFFENDERS.iter().map(|s| s.to_string()).collect();
    let new: Vec<&String> = found.iter().filter(|f| !expected.contains(f)).collect();
    let stale: Vec<&String> = expected.iter().filter(|e| !found.contains(e)).collect();
    assert!(new.is_empty(), "carried `modeled` rules with no row and no by-name entry (add the row): {new:#?}");
    assert!(stale.is_empty(), "these pairs are resolved now, delete them from EXPECTED_OFFENDERS: {stale:#?}");
}

/// The check can fail: each protection removed in turn makes exactly its pair show up.
#[test]
fn f5c_the_guard_reports_a_pair_when_a_protection_is_removed() {
    let carriers = json!({"gf": {"book_a": ["Foo", "Bar", "Baz", "Qux"]}});
    let reg = |faction_row: bool, common_row: bool, modeled: &[&str]| {
        let mut r = json!({"modeled": modeled, "factions": {"book_a": {}}, "common": {}});
        if faction_row { r["factions"]["book_a"]["Foo"] = json!({"primitive": "X"}); }
        if common_row { r["common"]["Bar"] = json!({"primitive": "X"}); }
        BTreeMap::from([("gf".to_string(), r)])
    };
    let all = ["Foo", "Bar", "Baz"];
    assert!(unmapped_modeled(&carriers, &reg(true, true, &all), &["Baz"]).is_empty(), "all protected: nothing to report");
    assert_eq!(unmapped_modeled(&carriers, &reg(false, true, &all), &["Baz"]), ["gf/book_a Foo"], "no faction row");
    assert_eq!(unmapped_modeled(&carriers, &reg(true, false, &all), &["Baz"]), ["gf/book_a Bar"], "no common row");
    assert_eq!(unmapped_modeled(&carriers, &reg(true, true, &all), &[]), ["gf/book_a Baz"], "no by-name entry");
    assert!(unmapped_modeled(&carriers, &reg(true, true, &["Foo", "Bar"]), &["Baz"]).is_empty(), "a name off the list is not this guard's");
}

/// A by-name entry must stay modeled and carried by some book, or it could hide a future gap for nothing.
#[test]
fn f5c_every_by_name_entry_is_still_modeled_and_carried() {
    let carriers = load("test/fixtures/book_rule_carriers_v36.json");
    let regs = repo_regs();
    let mut stale: Vec<&str> = Vec::new();
    for (name, _why) in BY_NAME {
        let modeled = regs.values().any(|r| names_of(&r["modeled"]).contains(name));
        let carried = ["gf", "aof"].iter().any(|s| {
            carriers[*s].as_object().is_some_and(|b| b.values().any(|n| names_of(n).contains(name)))
        });
        if !modeled || !carried {
            stale.push(name);
        }
    }
    assert!(stale.is_empty(), "BY_NAME entries no book carries or the list no longer models: {stale:?}");
}
