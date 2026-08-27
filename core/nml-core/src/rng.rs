//! Godot's `RandomNumberGenerator` — a bit-exact twin of `RandomPCG`
//! (core/math/random_pcg.h / .cpp, Godot 4.6-stable) and the three calls the
//! playout arbitration makes on it: `seed = x`, `randf()`, `randi_range(a, b)`.
//!
//! WHY a twin instead of any Rust PRNG: the arbitration seeds its generators
//! from a recorded signature (`sig * 31 + i * 2`) and the recorded corpus holds
//! the sums those exact dice produced. A different stream is a different game,
//! so "a good PRNG" is not a substitute for "Godot's PRNG".
//!
//! Nothing here was guessed. The mapping was DERIVED by matching
//! `tests/fixtures/rng_godot.json` (3 seeds x 1000 `randf()` + 1000
//! `randi_range(1, 6)` + the post-draw state, dumped by `tools/rng_fixture.gd`)
//! and cross-checked against a live 4.6 engine that printed `rng.state` around
//! every single draw. Three findings the header comment of a naive port would
//! have got wrong:
//!
//!   1. `seed = x` is NOT `state = x`. It is the reference `pcg32_srandom_r`:
//!      `state = 0; step(); state += x; step()`, with the stream increment
//!      `inc = (PCG_DEFAULT_INC_64 << 1) | 1` (Godot shifts in `RandomPCG`'s
//!      constructor, so the raw 1442695040888963407 is the WRONG increment).
//!   2. `randf()` draws TWICE, not once, and it is not `rand() / RANDOM_MAX`.
//!      The first draw sets the EXPONENT from its leading-zero count, the
//!      second is the significand with its top and bottom bit forced:
//!      `ldexpf((float)(rand() | 0x8000_0001), -32 - clz(proto))`.
//!      A `proto` of 0 short-circuits to 0.0 WITHOUT taking the second draw.
//!   3. `randi_range` is the biased modulo, one draw: `from + rand() % span`.

/// `PCG_DEFAULT_INC_64` (thirdparty/misc/pcg.h) — Godot's `RandomPCG::DEFAULT_INC`.
pub const PCG_DEFAULT_INC_64: u64 = 1442695040888963407;
/// `PCG_DEFAULT_MULTIPLIER_64`.
pub const PCG_DEFAULT_MULTIPLIER_64: u64 = 6364136223846793005;

/// The engine's `RandomNumberGenerator`, one `pcg32_random_t` wide.
#[derive(Debug, Clone, Copy)]
pub struct GodotRng {
    /// `pcg32_random_t.state` — what GDScript's `rng.state` reads and writes.
    pub state: u64,
    /// `pcg32_random_t.inc`, ALREADY shifted: `(initseq << 1) | 1`.
    pub inc: u64,
}

impl GodotRng {
    /// `RandomNumberGenerator.seed = p_seed` — `RandomPCG::seed`, which is the
    /// reference `pcg32_srandom_r(&pcg, p_seed, DEFAULT_INC)`.
    ///
    /// GDScript hands the seed as a SIGNED 64-bit int; the wrap to `u64` here is
    /// the same reinterpretation the engine's `uint64_t` parameter performs, so a
    /// negative signature seeds identically on both sides.
    pub fn new(seed: i64) -> GodotRng {
        let mut r = GodotRng { state: 0, inc: (PCG_DEFAULT_INC_64 << 1) | 1 };
        r.seed(seed);
        r
    }

    /// Re-seeds in place — same contract as `new`.
    pub fn seed(&mut self, seed: i64) {
        self.state = 0;
        self.rand_u32();
        self.state = self.state.wrapping_add(seed as u64);
        self.rand_u32();
    }

    /// `pcg32_random_r` — the XSH RR output function, state advanced first.
    pub fn rand_u32(&mut self) -> u32 {
        let old = self.state;
        self.state =
            old.wrapping_mul(PCG_DEFAULT_MULTIPLIER_64).wrapping_add(self.inc);
        let xorshifted = (((old >> 18) ^ old) >> 27) as u32;
        let rot = (old >> 59) as u32;
        xorshifted.rotate_right(rot)
    }

    /// `RandomPCG::randf()` as a `float` — see finding 2 in the module header.
    /// TWO draws in the common case, ONE when the exponent draw comes up zero.
    pub fn randf_f32(&mut self) -> f32 {
        let proto = self.rand_u32();
        if proto == 0 {
            return 0.0;
        }
        let significand = self.rand_u32() | 0x8000_0001;
        // ldexpf(x, -32 - clz) written as a division by an exact power of two:
        // `32 + clz` is 32..=63, so the divisor is exact in f32 and the quotient
        // is the ONE rounding step the C cast makes, in the same direction.
        let scale = (1u64 << (32 + proto.leading_zeros())) as f32;
        (significand as f32) / scale
    }

    /// What GDScript sees: `real_t` widened to a Variant float. Every comparison
    /// in `_apply_expected_wounds` is made on this f64.
    pub fn randf(&mut self) -> f64 {
        self.randf_f32() as f64
    }

    /// `RandomNumberGenerator::randf_range(from, to)` — `RandomPCG::random(float,
    /// float)`, i.e. `randf() * (to - from) + from` in SINGLE precision, with a
    /// rounding step per operation. GDScript widens the answer to a Variant
    /// float, which is why this returns `f64`.
    ///
    /// DERIVED, not guessed (NML-1073 M3-5): the double overload (`randd`, three
    /// draws) and a single-rounded f64 form were both tried against the deployed
    /// positions `tools/core_selfplay.gd:_deploy_zone` recorded for seed 27, and
    /// both put a unit one f32 ULP off. Two f32 roundings reproduce all 59 models.
    pub fn randf_range(&mut self, from: f64, to: f64) -> f64 {
        let (a, b) = (from as f32, to as f32);
        (self.randf_f32() * (b - a) + a) as f64
    }

    /// `RandomNumberGenerator::randi_range` — the BIASED modulo the engine ships,
    /// including its reversed-range branch. One draw.
    pub fn randi_range(&mut self, from: i64, to: i64) -> i64 {
        let r = self.rand_u32() as i64;
        if to < from {
            to + r % (from - to + 1)
        } else {
            from + r % (to - from + 1)
        }
    }

    /// `rng.state` as GDScript reads it back (a signed 64-bit int).
    pub fn state_i64(&self) -> i64 {
        self.state as i64
    }
}
