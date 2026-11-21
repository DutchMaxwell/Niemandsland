//! Lines guard (lane linesaudit, 21.11.): the doors write the tray's lines (`Tray::say` and its helpers), never the recorded log
//! (`ShootResult.log`, pushed as `out.log.push` / `shot.log.push`). A rule sentence added to the recorded log alone is invisible to a
//! player: that is how the cover lines, Anti-Cover, the sight-blocker lift and Pierce shipped without a word (#3223 -> #3286).
//!
//! The guard reads the combat resolvers' source (`dice.rs`, `sim.rs`) and finds every `log.push(` site. A site is TWINNED when a tray
//! say (`say_rule`, `tray.say`, `say_melee`, ...) stands within a few lines of it, or a `// tray twin: <rule>` comment on the push line
//! (or the line above) names a tray rule that this file says. Every other site must be named in `UNTWINNED`
//! with a reason class; a new un-twinned sentence fails here until it gets its tray twin (or an entry that says why it needs none).
//! A stale entry (a twin was added) fails too, so the list only shrinks.
//!
//! Classes: `gap` = the table says it and the door does not (open work), `twin` = the tray says the same event elsewhere in the
//! function (to-hit note, defense lines, announce lines), `silent` = the table has no such line (core narration), `other` = not
//! compared against the table yet (movement-phase narration, spells, feats, melee legs). Keys are the first words of the sentence.

const SOURCES: [(&str, &str); 2] = [("dice.rs", include_str!("../../dice.rs")), ("sim.rs", include_str!("../../sim.rs"))];

/// Tray-say spellings: a push with one of these within `BEFORE`/`AFTER` lines counts as twinned.
const SAYS: [&str; 17] = [
    "say_rule(", "tray.say(", ".say(|", "say_at(", "say_wounds(", "say_at_mark(", "say_melee(", "say_marks_consumed(", "say_control_test(",
    "say_morale_bonus(", "say_versatile_pick(", "say_shaken_batteries(", "say(&mut dice", "tray_say(", "say_regen_bypass(", "say_pierce(", "say_scourge(",
];
const BEFORE: usize = 1;
const AFTER: usize = 8;

// (file, key, class): every recorded-log sentence without a tray say nearby, as of this change.
include!("log_twins_list.rs");

/// The key of the push that starts on line `i`: the first string literal of the call (its first 48 chars), else the expression.
fn key_of(lines: &[&str], i: usize) -> String {
    let mut text = String::new();
    for l in lines.iter().skip(i).take(5) {
        text.push_str(l.trim());
        text.push(' ');
    }
    let from = text.find(".push(").map_or(0, |p| p + ".push(".len());
    let rest = &text[from..];
    let chars: Vec<char> = rest.chars().collect();
    if let Some(open) = chars.iter().position(|&c| c == '"') {
        let head: String = chars[..open].iter().collect();
        let plain = head.trim().is_empty() || head.trim() == "format!(" || head.trim().ends_with("format!(");
        if plain {
            let mut lit = String::new();
            let mut j = open + 1;
            while j < chars.len() && chars[j] != '"' {
                if chars[j] == '\\' && j + 1 < chars.len() {
                    lit.push(chars[j]);
                    j += 1;
                }
                lit.push(chars[j]);
                j += 1;
            }
            return lit.chars().take(48).collect();
        }
    }
    rest.chars().take_while(|&c| c != ')').take(48).collect::<String>().trim().to_string()
}

/// Every un-twinned push of the two resolver files (their test modules live in `src/tests`, so nothing here is test code).
fn untwinned() -> Vec<(String, String)> {
    let mut out = Vec::new();
    for (file, src) in SOURCES {
        let lines: Vec<&str> = src.lines().collect();
        let end = lines.len();
        for i in 0..end {
            let t = lines[i].trim();
            let push = t.contains("log.push(") || (t.ends_with("log") && lines.get(i + 1).is_some_and(|n| n.trim().starts_with(".push(")));
            if !push || t.starts_with("//") {
                continue;
            }
            let lo = i.saturating_sub(BEFORE);
            let hi = (i + AFTER).min(lines.len() - 1);
            let named = [lines[i], lines.get(i.wrapping_sub(1)).copied().unwrap_or("")].iter().any(|l| {
                l.split("// tray twin: ").nth(1).is_some_and(|r| { let k = r.split_whitespace().next().unwrap_or("?"); src.contains(&format!("say_rule(tray, \"{k}\"")) || src.contains(&format!("rule: \"{k}\"")) })
            });
            let twinned = named || lines[lo..=hi].iter().any(|l| SAYS.iter().any(|s| l.contains(s)));
            if !twinned {
                out.push((file.to_string(), key_of(&lines, i)));
            }
        }
    }
    out
}

fn multiset(mut v: Vec<(String, String)>) -> Vec<(String, String)> {
    v.sort();
    v
}

/// Fails when a recorded-log sentence has no tray twin and no entry (a new rule line the doors would never write), and when an entry
/// is stale (its sentence got a twin, or went away). RED proof: push a sentence to `out.log` in `dice.rs` with no say beside it.
#[test]
fn every_recorded_log_sentence_has_a_tray_twin_or_a_listed_reason() {
    let found = multiset(untwinned());
    let listed = multiset(UNTWINNED.iter().map(|(f, k, _)| (f.to_string(), k.to_string())).collect());
    let unlisted: Vec<&(String, String)> = found.iter().filter(|f| found.iter().filter(|x| x == f).count() > listed.iter().filter(|x| x == f).count()).collect();
    let stale: Vec<&(String, String)> = listed.iter().filter(|l| listed.iter().filter(|x| x == l).count() > found.iter().filter(|x| x == l).count()).collect();
    assert!(
        unlisted.is_empty(),
        "a sentence goes to the recorded log (out.log / shot.log) with no tray say beside it, so no door writes it: say it on the tray \
         (`say_rule`, in the table's words) or, if the table never says it, list it in log_twins_list.rs: {unlisted:?}"
    );
    assert!(stale.is_empty(), "these log_twins_list.rs entries no longer match a recorded-log push (twinned now, or gone): delete them: {stale:?}");
}

/// The classes are the closed set the header names.
#[test]
fn the_listed_classes_are_the_known_ones() {
    assert!(UNTWINNED.iter().all(|(_, _, c)| ["gap", "twin", "silent", "other"].contains(c)));
}

/// Prints the current list in `log_twins_list.rs` shape (`cargo test --lib -p nml-core print_the_untwinned_list -- --ignored --nocapture`).
#[test]
#[ignore]
fn print_the_untwinned_list() {
    for (f, k) in multiset(untwinned()) {
        println!("LIST\t{f}\t{k}");
    }
}
