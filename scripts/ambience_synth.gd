class_name AmbienceSynth
extends RefCounted
## Procedural battlefield-ambience synthesis: rain, thunder, distant artillery and
## machine-gun fire, fire crackle — all generated as 16-bit mono AudioStreamWAV buffers
## at runtime (zero audio-asset licensing; generalizes ui_feedback.gd::_tone()).
##
## Every generator takes an explicit rng_seed so output is reproducible (tested in
## test/ambience_synth_test.gd). Loops are tail-into-head crossfaded against clicks and
## flagged LOOP_FORWARD; one-shots are not looped. Peaks are limited before encoding.

# === Constants ===

const MIX_RATE := 22050
const LOOP_CROSSFADE_S := 0.25  # tail-into-head crossfade kills loop clicks
const PEAK_LIMIT := 0.9

# === Public API ===

## Somber menu drone pad (fallback while the CC0 recording is not cached): a low
## root + fifth with detune beating and two slow incommensurate amplitude LFOs.
static func make_menu_drone_pad(duration_s: float = 12.0, rng_seed: int = 11) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var n := int(duration_s * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var root_hz := 55.0
	var detune_hz := root_hz * 1.003
	var fifth_hz := root_hz * 1.5
	var phase_jitter := rng.randf() * TAU
	for i in n:
		var t := float(i) / MIX_RATE
		var lfo := 0.6 + 0.25 * sin(TAU * t / 17.3) + 0.15 * sin(TAU * t / 7.1 + phase_jitter)
		var voice := sin(TAU * root_hz * t) * 0.5 \
				+ sin(TAU * detune_hz * t) * 0.35 \
				+ sin(TAU * fifth_hz * t) * 0.2
		samples[i] = voice * lfo * 0.5
	_crossfade_loop_ends(samples)
	return _to_wav(samples, true)


## Loopable steady rain: lowpassed white noise with a slow gust LFO.
static func make_rain_loop(duration_s: float = 6.0, rng_seed: int = 1) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var n := int(duration_s * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	var lp_alpha := _lowpass_alpha(1400.0)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		lp += lp_alpha * (rng.randf_range(-1.0, 1.0) - lp)
		var gust := 1.0 + 0.15 * sin(TAU * 0.3 * t)
		samples[i] = lp * gust * 0.8
	_crossfade_loop_ends(samples)
	return _to_wav(samples, true)


## Loopable fire crackle: quiet brown-noise bed + sparse random decay clicks.
static func make_fire_crackle_loop(duration_s: float = 4.0, rng_seed: int = 2) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var n := int(duration_s * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var brown := 0.0
	for i in n:
		brown = clampf(brown + rng.randf_range(-1.0, 1.0) * 0.02, -0.3, 0.3)
		samples[i] = brown * 0.25
	# Poisson-ish clicks: ~12 per second, each a 5-20 ms exponential noise tick.
	var click_count := int(duration_s * 12.0)
	for _c in click_count:
		var start := rng.randi() % n
		var click_len := int(rng.randf_range(0.005, 0.02) * MIX_RATE)
		var amp := rng.randf_range(0.2, 0.7)
		for j in click_len:
			var idx := start + j
			if idx >= n:
				break
			var env := exp(-float(j) / float(click_len) * 6.0)
			samples[idx] += rng.randf_range(-1.0, 1.0) * amp * env
	_crossfade_loop_ends(samples)
	return _to_wav(samples, true)


## One-shot thunder: broadband crack + long lowpassed rumble tail + sub sweep.
## intensity 0..1+ scales the crack/tail balance (1.0 = close strike).
static func make_thunder(intensity: float = 1.0, rng_seed: int = 0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var duration_s := 4.5
	var n := int(duration_s * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var crack_len := int(0.1 * MIX_RATE)
	var lp := 0.0
	var lp_alpha := _lowpass_alpha(220.0)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var s := 0.0
		# Initial crack (only meaningful for close strikes).
		if i < crack_len:
			s += rng.randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.9 * intensity
		# Rumble tail: lowpassed noise with slow exponential decay.
		lp += lp_alpha * (rng.randf_range(-1.0, 1.0) - lp)
		s += lp * exp(-t * 0.9) * 2.2
		# Sub sweep 60 -> 35 Hz under it all.
		var sweep_f := lerpf(60.0, 35.0, clampf(t / duration_s, 0.0, 1.0))
		s += sin(TAU * sweep_f * t) * exp(-t * 1.2) * 0.35
		samples[i] = s
	return _to_wav(samples, false)


## One-shot distant artillery: sub thump with downward pitch drift + muffled noise burst.
static func make_artillery_rumble(rng_seed: int = 0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var duration_s := 2.5
	var n := int(duration_s * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	var lp_alpha := _lowpass_alpha(300.0)
	var base_f := rng.randf_range(40.0, 52.0)
	for i in n:
		var t := float(i) / float(MIX_RATE)
		var f := base_f * (1.0 - 0.3 * clampf(t / duration_s, 0.0, 1.0))
		var s := sin(TAU * f * t) * exp(-t * 2.0) * 0.8
		lp += lp_alpha * (rng.randf_range(-1.0, 1.0) - lp)
		s += lp * exp(-t * 2.8) * 1.6
		samples[i] = s
	return _to_wav(samples, false)


## One-shot distant machine-gun burst: a train of muffled clicks at ~9-12 Hz.
static func make_distant_mg(rng_seed: int = 0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var shot_count := rng.randi_range(5, 12)
	var rate_hz := rng.randf_range(9.0, 12.0)
	var duration_s := float(shot_count) / rate_hz + 0.4
	var n := int(duration_s * MIX_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var click_len := int(0.004 * MIX_RATE)
	for shot in shot_count:
		var start := int(float(shot) / rate_hz * MIX_RATE)
		var amp := rng.randf_range(0.5, 0.9)
		for j in click_len:
			var idx := start + j
			if idx >= n:
				break
			raw[idx] += rng.randf_range(-1.0, 1.0) * amp * exp(-float(j) / float(click_len) * 4.0)
	# Distance muffling: lowpass the whole burst train.
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	var lp_alpha := _lowpass_alpha(900.0)
	for i in n:
		lp += lp_alpha * (raw[i] - lp)
		samples[i] = lp * 2.0
	return _to_wav(samples, false)

# === Private helpers ===

## One-pole lowpass smoothing factor for a given cutoff at MIX_RATE.
static func _lowpass_alpha(cutoff_hz: float) -> float:
	var rc := 1.0 / (TAU * cutoff_hz)
	var dt := 1.0 / float(MIX_RATE)
	return dt / (rc + dt)


## Crossfades the buffer tail into its head so LOOP_FORWARD playback has no click.
static func _crossfade_loop_ends(samples: PackedFloat32Array) -> void:
	var fade_n := mini(int(LOOP_CROSSFADE_S * MIX_RATE), samples.size() / 2)
	var n := samples.size()
	for i in fade_n:
		var blend := float(i) / float(fade_n)
		samples[i] = samples[i] * blend + samples[n - fade_n + i] * (1.0 - blend)
	# The blended head replaces the tail region's job; trim nothing — playback loops
	# back before the raw tail by setting loop_end below the crossfaded region.
	samples.resize(n - fade_n)


## Normalizes peaks to PEAK_LIMIT and encodes a 16-bit mono AudioStreamWAV.
static func _to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var peak := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
	var gain := (PEAK_LIMIT / peak) if peak > PEAK_LIMIT else 1.0

	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav
