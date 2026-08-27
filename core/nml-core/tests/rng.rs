//! GATE R (NML-1073 M2-4) — the Rust twin of Godot's `RandomNumberGenerator`
//! against `tests/fixtures/rng_godot.json`, dumped by `tools/rng_fixture.gd`
//! from a live 4.6 engine.
//!
//! Three seeds x (1000 `randf()` + 1000 `randi_range(1, 6)`) + the PCG32 state
//! after all 2000 draws = 6003 values, and the bar is EXACT for every one of
//! them. Not "within 1e-9": `randf()` is a float32 built out of two 32-bit
//! draws, so any wrong bit is a wrong number, and any wrong number sends the
//! playout it feeds down a different game.
//!
//! This gate is the foundation of GATE G5. The arbitration's sums are the
//! outcome of dozens of stochastic activations per playout; if the stream
//! drifted at draw 3, no amount of correct rules code downstream would
//! reproduce them.
//!
//! THE FIXTURE IS READ AT LITERAL LEVEL, not through `serde_json`. The pinned
//! `serde_json` 1.0.151 parses some 17-significant-digit literals one ULP off
//! (`0.18379618227481842` -> `0x3fc786a21fffffff` instead of `..20000000`);
//! 306 of these 3000 recorded draws land on such a literal. Rust's own
//! `str::parse::<f64>()` is correctly rounded, so the fixture is read with it
//! and the gate stays an EXACT comparison instead of being relaxed to 1e-9 to
//! hide a reader defect. The defect itself is pinned below, so a later
//! dependency bump that fixes it fails THAT test rather than this gate.

use nml_core::GodotRng;

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/rng_godot.json");

/// The seed object `{"randf":[..],"randi_range_1_6":[..],"state":N}` of one
/// seed. `JSON.stringify(.., indent="")` writes it without whitespace and
/// without nested braces, so "up to the next `}`" is the whole object.
fn seed_block<'a>(raw: &'a str, seed: &str) -> &'a str {
    let open = format!("\"{seed}\":{{");
    let i = raw.find(&open).unwrap_or_else(|| panic!("fixture: no seed {seed}"));
    let rest = &raw[i + open.len()..];
    let j = rest.find('}').unwrap_or_else(|| panic!("fixture: seed {seed} unterminated"));
    &rest[..j]
}

fn array_literals<'a>(block: &'a str, name: &str) -> Vec<&'a str> {
    let open = format!("\"{name}\":[");
    let i = block.find(&open).unwrap_or_else(|| panic!("fixture: no {name}"));
    let rest = &block[i + open.len()..];
    let j = rest.find(']').unwrap_or_else(|| panic!("fixture: {name} unterminated"));
    rest[..j].split(',').collect()
}

fn state_literal(block: &str) -> i64 {
    let open = "\"state\":";
    let i = block.find(open).unwrap_or_else(|| panic!("fixture: no state"));
    block[i + open.len()..].trim().parse().expect("state is an int")
}

#[test]
fn gate_r_reproduces_godots_stream_exactly() {
    let raw = std::fs::read_to_string(FIXTURE).unwrap_or_else(|e| panic!("{FIXTURE}: {e}"));
    // The three seeds `tools/rng_fixture.gd` dumps: 1, a mid-range value and one
    // past 2^32, so a 32-bit truncation anywhere in the seeding cannot hide.
    let seeds: [i64; 3] = [1, 12345, 1_099_511_627_783];
    let mut checked = 0usize;
    let mut bad: Vec<String> = Vec::new();
    for seed in seeds {
        let block = seed_block(&raw, &seed.to_string());
        let mut rng = GodotRng::new(seed);

        let want_f = array_literals(block, "randf");
        assert_eq!(want_f.len(), 1000, "seed {seed}: 1000 randf draws");
        for (i, lit) in want_f.iter().enumerate() {
            let want: f64 = lit.parse().unwrap_or_else(|e| panic!("randf[{i}] {lit}: {e}"));
            let got = rng.randf();
            checked += 1;
            if got != want {
                bad.push(format!("seed {seed} randf[{i}]: {got:?} != {want:?}"));
            }
        }

        let want_i = array_literals(block, "randi_range_1_6");
        assert_eq!(want_i.len(), 1000, "seed {seed}: 1000 randi_range draws");
        for (i, lit) in want_i.iter().enumerate() {
            let want: i64 = lit.parse().unwrap_or_else(|e| panic!("randi[{i}] {lit}: {e}"));
            let got = rng.randi_range(1, 6);
            checked += 1;
            if got != want {
                bad.push(format!("seed {seed} randi[{i}]: {got} != {want}"));
            }
        }

        // The cheap second check the fixture was built for: the internal PCG
        // state after all 2000 draws. A stream that matched every value but
        // advanced the state differently would break on the NEXT draw.
        let want_state = state_literal(block);
        checked += 1;
        if rng.state_i64() != want_state {
            bad.push(format!("seed {seed} state: {} != {want_state}", rng.state_i64()));
        }
    }
    assert_eq!(checked, 6003, "GATE R checks 3 x (1000 + 1000) values plus 3 states");
    assert!(
        bad.is_empty(),
        "GATE R: {} mismatches of {checked}, first few: {:?}",
        bad.len(),
        &bad[..bad.len().min(8)]
    );
    println!(
        "GATE R: {checked}/{checked} exact \
         (3 seeds x 1000 randf + 1000 randi_range(1,6) + 3 post-draw states)"
    );
}

/// RED PROOF for GATE R: the classic wrong guess at Godot's `randf()` is
/// "`rand()` over the 32-bit range", one draw and a plain divide — the shape
/// most engines use. It is not what 4.6 does, and this counts how many of the
/// 3000 recorded draws that costs, so the gate's green is a measurement rather
/// than an assumption.
#[test]
fn red_proof_the_one_draw_randf_mapping_fails_gate_r() {
    let raw = std::fs::read_to_string(FIXTURE).unwrap_or_else(|e| panic!("{FIXTURE}: {e}"));
    let mut mismatches = 0usize;
    let mut checked = 0usize;
    for seed in [1i64, 12345, 1_099_511_627_783] {
        let block = seed_block(&raw, &seed.to_string());
        let mut rng = GodotRng::new(seed);
        for lit in array_literals(block, "randf") {
            let want: f64 = lit.parse().unwrap();
            // The WRONG mapping: one draw, divided by 2^32 - 1 as a float.
            let got = (rng.rand_u32() as f32 / 4_294_967_295.0f32) as f64;
            checked += 1;
            if got != want {
                mismatches += 1;
            }
        }
    }
    assert_eq!(checked, 3000);
    assert_eq!(mismatches, 3000, "the one-draw mapping must miss EVERY recorded randf");
    println!("RED PROOF (randf = rand()/RANDOM_MAX): {mismatches}/{checked} draws wrong");
}

/// The `proto == 0` branch of `randf()` returns 0.0 WITHOUT taking the
/// significand draw. A 1-in-2^32 event the fixture cannot be expected to hold,
/// so it is pinned directly: force the state that makes the next `rand()` zero
/// and prove the generator advanced exactly ONE step.
#[test]
fn randf_zero_exponent_draw_short_circuits() {
    let mut rng = GodotRng::new(1);
    // `state = 1` makes XSH RR emit 0: ((1 >> 18) ^ 1) >> 27 == 0, rot == 0.
    rng.state = 1;
    let mut probe = GodotRng { state: 1, inc: rng.inc };
    probe.rand_u32();
    assert_eq!(rng.randf(), 0.0);
    assert_eq!(rng.state, probe.state, "the zero branch takes ONE draw, not two");
}

/// `randi_range` with the range reversed is the engine's own branch, not an
/// error — `p_to + (ret % (p_from - p_to + 1))`.
#[test]
fn randi_range_reversed_matches_the_engine_branch() {
    let mut a = GodotRng::new(12345);
    let mut b = GodotRng::new(12345);
    for _ in 0..64 {
        assert_eq!(a.randi_range(1, 6), b.randi_range(6, 1));
    }
}

/// THE INSTRUMENT, pinned: `serde_json`'s default parser reads this 17-digit
/// literal one ULP LOW (0x3fc7_86a2_1fff_ffff), and every recorded position is
/// written with 17 digits by `JSON.stringify(.., full_precision = true)`. The
/// `float_roundtrip` feature (NML-1073 M3-1, `Cargo.toml`) turns that parser
/// into a correctly rounded one, which is what makes
/// `io::plain_of(io::state_from_json(x)) == x` hold EXACTLY on the act corpus.
///
/// This test fails the moment the feature is dropped — it is the only thing
/// standing between the corpus and a silent 1-ULP shift in every coordinate.
/// GATE R keeps its own `str::parse` reader regardless: a gate that reads its
/// fixture through the crate it is measuring proves less.
#[test]
fn serde_json_parses_a_17_digit_literal_exactly() {
    let lit = "0.18379618227481842";
    let via_serde: f64 = serde_json::from_str(lit).unwrap();
    let via_rust: f64 = lit.parse().unwrap();
    assert_eq!(via_rust.to_bits(), 0x3fc7_86a2_2000_0000, "Rust parses it correctly");
    assert_eq!(
        via_serde.to_bits(),
        via_rust.to_bits(),
        "serde_json must be correctly rounded — is the `float_roundtrip` feature still on?"
    );
}

// ------------------------------------------------- GATE R2: randf_range ---

const RANGE_FIXTURE: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/rng_range_godot.json");

/// GATE R2 (NML-1073 M3-5) — `RandomNumberGenerator.randf_range`, the draw
/// `tools/core_selfplay.gd:_deploy_zone` makes twice per unit, against
/// `tests/fixtures/rng_range_godot.json` (`tools/rng_range_fixture.gd`).
///
/// The engine's call is `RandomPCG::random(float, float)` — `randf() * (to -
/// from) + from` in SINGLE precision, with a rounding step per operation. The
/// bar is EXACT, like GATE R: one ULP here moves a deployed model by ~2e-9 m,
/// which is enough to flip a cell lookup and with it a whole game.
#[test]
fn gate_r2_reproduces_godots_randf_range_exactly() {
    let raw = std::fs::read_to_string(RANGE_FIXTURE).unwrap_or_else(|e| panic!("{RANGE_FIXTURE}: {e}"));
    let mut checked = 0usize;
    let mut bad: Vec<String> = Vec::new();
    for seed in [1i64, 27, 12345] {
        let block = seed_block(&raw, &seed.to_string());
        let mut rng = GodotRng::new(seed);
        for (name, from, to) in
            [("randf_range_m3_3", -3.0f64, 3.0f64), ("randf_range_1_9", 1.0, 9.0)]
        {
            let want_v = array_literals(block, name);
            assert_eq!(want_v.len(), 500, "seed {seed}: 500 {name} draws");
            for (i, lit) in want_v.iter().enumerate() {
                let want: f64 = lit.parse().unwrap_or_else(|e| panic!("{name}[{i}] {lit}: {e}"));
                let got = rng.randf_range(from, to);
                checked += 1;
                if got != want {
                    bad.push(format!("seed {seed} {name}[{i}]: {got:?} != {want:?}"));
                }
            }
        }
        let want_state = state_literal(block);
        checked += 1;
        if rng.state_i64() != want_state {
            bad.push(format!("seed {seed} state: {} != {want_state}", rng.state_i64()));
        }
    }
    assert_eq!(checked, 3003, "GATE R2 checks 3 x (500 + 500) values plus 3 states");
    assert!(
        bad.is_empty(),
        "GATE R2: {} mismatches of {checked}, first few: {:?}",
        bad.len(),
        &bad[..bad.len().min(8)]
    );
    println!("GATE R2: {checked}/{checked} exact (3 seeds x 500 randf_range(-3,3) + 500 randf_range(1,9) + 3 states)");
}

/// RED PROOF for GATE R2: the same two draws with the multiply-add done in
/// DOUBLE precision — one rounding instead of two, the shape a port writes
/// when it forgets `real_t` is a float. It reproduces the leading digits and
/// then misses, which is exactly the failure mode a 1e-9 tolerance would hide,
/// so the count is printed rather than assumed.
#[test]
fn red_proof_the_double_precision_randf_range_fails_gate_r2() {
    let raw = std::fs::read_to_string(RANGE_FIXTURE).unwrap_or_else(|e| panic!("{RANGE_FIXTURE}: {e}"));
    let mut checked = 0usize;
    let mut mismatches = 0usize;
    for seed in [1i64, 27, 12345] {
        let block = seed_block(&raw, &seed.to_string());
        let mut rng = GodotRng::new(seed);
        for (name, from, to) in
            [("randf_range_m3_3", -3.0f64, 3.0f64), ("randf_range_1_9", 1.0, 9.0)]
        {
            for lit in array_literals(block, name) {
                let want: f64 = lit.parse().unwrap();
                // The WRONG mapping: f64 arithmetic over the f32 draw.
                let got = rng.randf() * (to - from) + from;
                checked += 1;
                if got != want {
                    mismatches += 1;
                }
            }
        }
    }
    assert_eq!(checked, 3000);
    assert!(
        mismatches > 0,
        "the f64 form must miss at least one recorded draw, or the gate proves nothing"
    );
    println!("RED PROOF (randf_range in f64): {mismatches}/{checked} draws wrong");
}

// ----------------------------------------------------- GATE R3: the tray ---

/// GATE R3 (NML-1073 M5 D1-B3) — the dice `Tray` against the SAME engine
/// recording, not against the twin it is built on.
///
/// `tools/rng_fixture.gd` dumps, per seed, 1000 `randf()` and then 1000
/// `randi_range(1, 6)`. A tray face IS one `randi_range(1, 6)`
/// (main.gd:7152-7159), so a generator advanced past the 1000 recorded
/// `randf()` draws and handed to a `Tray` must roll the 1000 recorded faces —
/// in ONE `roll(1000)`, which is also the proof that a batch roll draws once
/// per die and in order.
#[test]
fn gate_r3_the_tray_rolls_the_recorded_engine_faces() {
    let raw = std::fs::read_to_string(FIXTURE).unwrap_or_else(|e| panic!("{FIXTURE}: {e}"));
    let mut checked = 0usize;
    let mut bad: Vec<String> = Vec::new();
    for seed in [1i64, 12345, 1_099_511_627_783] {
        let block = seed_block(&raw, &seed.to_string());
        let mut rng = nml_core::GodotRng::new(seed);
        for _ in 0..1000 {
            rng.randf(); // the fixture's randi block starts here
        }
        let want = array_literals(block, "randi_range_1_6");
        assert_eq!(want.len(), 1000, "seed {seed}: 1000 recorded faces");
        let faces = nml_core::Tray::from_rng(rng).roll(want.len());
        for (i, lit) in want.iter().enumerate() {
            let w: u8 = lit.parse().unwrap_or_else(|e| panic!("face[{i}] {lit}: {e}"));
            checked += 1;
            if faces[i] != w {
                bad.push(format!("seed {seed} face[{i}]: {} != {w}", faces[i]));
            }
        }
    }
    assert_eq!(checked, 3000, "GATE R3 checks 3 x 1000 recorded faces");
    assert!(bad.is_empty(), "GATE R3: {} mismatches, first: {:?}", bad.len(), &bad[..bad.len().min(8)]);
    println!("GATE R3: {checked}/{checked} tray faces match the engine recording");
}
