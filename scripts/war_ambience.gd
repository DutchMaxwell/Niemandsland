class_name WarAmbience
extends Node
## Battlefield soundscape on the Ambience bus: occasional distant war one-shots
## (artillery / machine-gun) from random directions, a fading rain loop, thunder on
## lightning strikes, and positional fire crackle at burning ruins. Starts with the
## procedural AmbienceSynth sounds and hot-swaps to the CC0 recordings
## (AmbienceLibrary, delivered from R2) once they are cached. Owned by
## AtmosphereController.

# === Constants ===

const WAR_SFX_MIN_INTERVAL_S := 20.0
const WAR_SFX_MAX_INTERVAL_S := 60.0
## First shot shortly after enabling, so the toggle gives audible feedback.
const WAR_SFX_FIRST_DELAY_MIN_S := 2.0
const WAR_SFX_FIRST_DELAY_MAX_S := 6.0
const WAR_SFX_VOLUME_DB_MIN := -12.0
const WAR_SFX_VOLUME_DB_MAX := -5.0
const WAR_SFX_DISTANCE_M := 7.0     # off-table ring the one-shots play from
const WAR_SFX_HEIGHT_M := 0.5
const WAR_SFX_ARTILLERY_SHARE := 0.6
const WAR_SFX_PITCH_MIN := 0.92
const WAR_SFX_PITCH_MAX := 1.08
const WAR_STREAM_VARIANTS := 4      # pre-synthesized variants per sound type
const MUFFLE_CUTOFF_HZ := 2000.0

const RAIN_VOLUME_DB := -8.0
const RAIN_FADE_S := 2.0
const SILENT_DB := -80.0

const THUNDER_BASE_DB := -6.0
const THUNDER_DB_PER_DELAY_S := -5.0

const MAX_FIRE_CRACKLE_EMITTERS := 4
const CRACKLE_VOLUME_DB := -10.0
const CRACKLE_UNIT_SIZE := 0.35     # audible only near a burning ruin

# === Private variables ===

var _enabled := false
var _volume_offset_db := 0.0  # context attenuation (menu plays quieter than in-game)
var _timer: Timer = null
var _rng := RandomNumberGenerator.new()
var _war_player: AudioStreamPlayer3D = null
var _thunder_player: AudioStreamPlayer = null
var _rain_player: AudioStreamPlayer = null
var _rain_tween: Tween = null
var _crackle_players: Array[AudioStreamPlayer3D] = []
var _artillery_streams: Array[AudioStream] = []
var _mg_streams: Array[AudioStream] = []
var _thunder_streams: Array[AudioStream] = []
var _library: AmbienceLibrary = null

# === Lifecycle ===

func _ready() -> void:
	_rng.randomize()  # ambience-only randomness; nothing here is gameplay-synced

	# Pre-synthesize the fallback streams once (never inside _process or the timer
	# callback); the CC0 recordings replace them asynchronously (_swap_in_recordings).
	for i in WAR_STREAM_VARIANTS:
		_artillery_streams.append(AmbienceSynth.make_artillery_rumble(100 + i))
		_mg_streams.append(AmbienceSynth.make_distant_mg(200 + i))
	_thunder_streams.append(AmbienceSynth.make_thunder(1.0, 7))

	_war_player = AudioStreamPlayer3D.new()
	_war_player.bus = AudioManager.BUS_AMBIENCE
	_war_player.attenuation_filter_cutoff_hz = MUFFLE_CUTOFF_HZ
	add_child(_war_player)

	_thunder_player = AudioStreamPlayer.new()
	_thunder_player.bus = AudioManager.BUS_AMBIENCE
	add_child(_thunder_player)

	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = AudioManager.BUS_AMBIENCE
	_rain_player.stream = AmbienceSynth.make_rain_loop()
	_rain_player.volume_db = SILENT_DB
	add_child(_rain_player)

	for i in MAX_FIRE_CRACKLE_EMITTERS:
		var crackle := AudioStreamPlayer3D.new()
		crackle.bus = AudioManager.BUS_AMBIENCE
		crackle.stream = AmbienceSynth.make_fire_crackle_loop()
		crackle.volume_db = CRACKLE_VOLUME_DB
		crackle.unit_size = CRACKLE_UNIT_SIZE
		add_child(crackle)
		_crackle_players.append(crackle)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_war_sfx_due)
	add_child(_timer)

	_library = AmbienceLibrary.new()
	_library.name = "AmbienceLibrary"
	add_child(_library)
	_fetch_recordings()

# === Public ===

func set_war_sounds_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	if on:
		_schedule_next_war_sfx(true)
	else:
		_timer.stop()


func is_war_sounds_enabled() -> bool:
	return _enabled


## Context volume offset in dB applied to every voice (one-shots, thunder, crackle).
## The menu uses -10 dB; in-game default is 0 (behavior unchanged).
func set_volume_offset_db(db: float) -> void:
	_volume_offset_db = db
	for crackle in _crackle_players:
		crackle.volume_db = CRACKLE_VOLUME_DB + db


## Fade the steady rain loop in/out.
func set_rain_audio(on: bool) -> void:
	if _rain_tween and _rain_tween.is_valid():
		_rain_tween.kill()
	_rain_tween = create_tween()
	if on:
		if not _rain_player.playing:
			_rain_player.play()
		_rain_tween.tween_property(_rain_player, "volume_db", RAIN_VOLUME_DB, RAIN_FADE_S)
	else:
		_rain_tween.tween_property(_rain_player, "volume_db", SILENT_DB, RAIN_FADE_S)
		_rain_tween.tween_callback(_rain_player.stop)


## Thunder for a lightning strike: louder the shorter the flash-to-thunder delay.
func play_thunder(delay_distance_s: float) -> void:
	_thunder_player.stream = _thunder_streams[_rng.randi() % _thunder_streams.size()]
	_thunder_player.volume_db = thunder_volume_db(delay_distance_s) + _volume_offset_db
	_thunder_player.pitch_scale = _rng.randf_range(WAR_SFX_PITCH_MIN, WAR_SFX_PITCH_MAX)
	_thunder_player.play()


## Pure mapping (unit-tested): thunder volume falls with the flash-to-thunder delay.
static func thunder_volume_db(delay_distance_s: float) -> float:
	return THUNDER_BASE_DB + THUNDER_DB_PER_DELAY_S * delay_distance_s


## Park the crackle emitters at the first N fire positions (deterministic order from
## terrain_overlay). Called on fires_rebuilt only — never per frame.
func update_fire_crackle(fire_positions: Array) -> void:
	for i in _crackle_players.size():
		var crackle := _crackle_players[i]
		if i < fire_positions.size():
			crackle.position = fire_positions[i]
			if not crackle.playing:
				crackle.play()
		else:
			crackle.stop()

# === Private ===

## Download the CC0 recordings in the background and hot-swap them in when ready.
func _fetch_recordings() -> void:
	var ok: bool = await _library.ensure_all_sounds()
	if ok:
		_swap_in_recordings()


func _swap_in_recordings() -> void:
	var artillery_a := _library.get_stream("war_artillery_a")
	var artillery_b := _library.get_stream("war_artillery_b")
	if artillery_a != null and artillery_b != null:
		_artillery_streams = [artillery_a, artillery_b]
	var mg_a := _library.get_stream("war_mg_a")
	var mg_b := _library.get_stream("war_mg_b")
	if mg_a != null and mg_b != null:
		_mg_streams = [mg_a, mg_b]
	var thunder_a := _library.get_stream("thunder_a")
	var thunder_b := _library.get_stream("thunder_b")
	if thunder_a != null and thunder_b != null:
		_thunder_streams = [thunder_a, thunder_b]

	var rain := _library.get_stream("rain_loop")
	if rain != null:
		var was_playing := _rain_player.playing
		_rain_player.stop()
		_rain_player.stream = rain
		if was_playing:
			_rain_player.play()

	var crackle := _library.get_stream("fire_crackle")
	if crackle != null:
		for player in _crackle_players:
			var playing := player.playing
			player.stop()
			player.stream = crackle
			if playing:
				# Desynchronize the loops so nearby fires don't crackle in unison.
				player.play(_rng.randf() * float(crackle.get_length()))


func _schedule_next_war_sfx(first: bool = false) -> void:
	if first:
		_timer.wait_time = _rng.randf_range(WAR_SFX_FIRST_DELAY_MIN_S, WAR_SFX_FIRST_DELAY_MAX_S)
	else:
		_timer.wait_time = _rng.randf_range(WAR_SFX_MIN_INTERVAL_S, WAR_SFX_MAX_INTERVAL_S)
	_timer.start()


func _on_war_sfx_due() -> void:
	if not _enabled:
		return
	var azimuth := _rng.randf() * TAU
	_war_player.position = Vector3(cos(azimuth) * WAR_SFX_DISTANCE_M, WAR_SFX_HEIGHT_M,
			sin(azimuth) * WAR_SFX_DISTANCE_M)
	if _rng.randf() < WAR_SFX_ARTILLERY_SHARE:
		_war_player.stream = _artillery_streams[_rng.randi() % _artillery_streams.size()]
	else:
		_war_player.stream = _mg_streams[_rng.randi() % _mg_streams.size()]
	_war_player.volume_db = _rng.randf_range(WAR_SFX_VOLUME_DB_MIN, WAR_SFX_VOLUME_DB_MAX) \
			+ _volume_offset_db
	_war_player.pitch_scale = _rng.randf_range(WAR_SFX_PITCH_MIN, WAR_SFX_PITCH_MAX)
	_war_player.play()
	_schedule_next_war_sfx()
