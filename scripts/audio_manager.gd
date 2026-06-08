extends Node
## Global audio manager handling SFX playback, music crossfade, and volume control
## Registered as Autoload — access via AudioManager singleton

# === Constants ===

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const BUS_UI := "UI"  # short UI feedback ticks (UiFeedback); independently mutable

const SFX_POOL_SIZE: int = 8
const CROSSFADE_DURATION: float = 2.0

enum SFXType {
	DICE_ROLL,
	DICE_IMPACT,
	MODEL_PLACE,
	MODEL_SELECT,
	UI_CLICK,
	UI_HOVER,
	TURN_START,
	TURN_END,
}

# === Signals ===

signal music_changed(track_name: String)
signal volume_changed(bus_name: String, volume_db: float)

# === Private Variables ===

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_pool_index: int = 0

var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_music_player: AudioStreamPlayer
var _crossfade_tween: Tween

var _ambience_player: AudioStreamPlayer

## SFX resource paths — populated when audio files are added to assets/audio/
var _sfx_paths: Dictionary = {
	SFXType.DICE_ROLL: "res://assets/audio/dice/dice_roll.ogg",
	SFXType.DICE_IMPACT: "res://assets/audio/dice/dice_impact.ogg",
	SFXType.MODEL_PLACE: "res://assets/audio/ui/model_place.ogg",
	SFXType.MODEL_SELECT: "res://assets/audio/ui/model_select.ogg",
	SFXType.UI_CLICK: "res://assets/audio/ui/ui_click.ogg",
	SFXType.UI_HOVER: "res://assets/audio/ui/ui_hover.ogg",
	SFXType.TURN_START: "res://assets/audio/ui/turn_start.ogg",
	SFXType.TURN_END: "res://assets/audio/ui/turn_end.ogg",
}

## Cached loaded SFX streams
var _sfx_cache: Dictionary = {}


# === Lifecycle ===

func _ready() -> void:
	_setup_sfx_pool()
	_setup_music_players()
	_setup_ambience_player()
	_load_volume_settings()


# === SFX ===

## Play a sound effect by type
func play_sfx(sfx_type: SFXType, volume_offset_db: float = 0.0) -> void:
	var stream := _get_sfx_stream(sfx_type)
	if not stream:
		return

	var player := _sfx_pool[_sfx_pool_index]
	player.stream = stream
	player.volume_db = volume_offset_db
	player.play()
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE


## Play a one-shot SFX from a direct resource path
func play_sfx_at_path(path: String, volume_offset_db: float = 0.0) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if not stream:
		return

	var player := _sfx_pool[_sfx_pool_index]
	player.stream = stream
	player.volume_db = volume_offset_db
	player.play()
	_sfx_pool_index = (_sfx_pool_index + 1) % SFX_POOL_SIZE


# === Music ===

## Play a music track with crossfade
func play_music(stream: AudioStream, fade_duration: float = CROSSFADE_DURATION) -> void:
	if not stream:
		return

	var next_player := _get_inactive_music_player()
	next_player.stream = stream
	next_player.volume_db = -80.0
	next_player.play()

	# Crossfade
	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	_crossfade_tween = create_tween().set_parallel(true)

	# Fade in new
	_crossfade_tween.tween_property(next_player, "volume_db", 0.0, fade_duration)

	# Fade out old
	if _active_music_player and _active_music_player.playing:
		_crossfade_tween.tween_property(_active_music_player, "volume_db", -80.0, fade_duration)
		_crossfade_tween.chain().tween_callback(_active_music_player.stop)

	_active_music_player = next_player
	music_changed.emit(stream.resource_path.get_file())


## Play music from a file path
func play_music_from_path(path: String, fade_duration: float = CROSSFADE_DURATION) -> void:
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: Music file not found: %s" % path)
		return
	var stream := load(path) as AudioStream
	play_music(stream, fade_duration)


## Stop music with fade out
func stop_music(fade_duration: float = CROSSFADE_DURATION) -> void:
	if not _active_music_player or not _active_music_player.playing:
		return

	if _crossfade_tween and _crossfade_tween.is_valid():
		_crossfade_tween.kill()

	_crossfade_tween = create_tween()
	_crossfade_tween.tween_property(_active_music_player, "volume_db", -80.0, fade_duration)
	_crossfade_tween.tween_callback(_active_music_player.stop)


# === Ambience ===

## Play an ambience loop
func play_ambience(stream: AudioStream) -> void:
	if not stream:
		return
	_ambience_player.stream = stream
	_ambience_player.play()


## Stop ambience
func stop_ambience() -> void:
	_ambience_player.stop()


# === Volume Control ===

## Set volume for a bus by name (in dB)
func set_bus_volume(bus_name: String, volume_db: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		push_warning("AudioManager: Bus not found: %s" % bus_name)
		return
	AudioServer.set_bus_volume_db(bus_idx, volume_db)
	volume_changed.emit(bus_name, volume_db)
	_save_volume_settings()


## Get volume for a bus (in dB)
func get_bus_volume(bus_name: String) -> float:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(bus_idx)


## Set bus mute state
func set_bus_mute(bus_name: String, muted: bool) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	AudioServer.set_bus_mute(bus_idx, muted)


## Check if bus is muted
func is_bus_muted(bus_name: String) -> bool:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return false
	return AudioServer.is_bus_mute(bus_idx)


# === Private Methods ===

func _setup_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_pool.append(player)


func _setup_music_players() -> void:
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = BUS_MUSIC
	add_child(_music_player_a)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = BUS_MUSIC
	add_child(_music_player_b)

	_active_music_player = _music_player_a


func _setup_ambience_player() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = BUS_AMBIENCE
	add_child(_ambience_player)


func _get_inactive_music_player() -> AudioStreamPlayer:
	if _active_music_player == _music_player_a:
		return _music_player_b
	return _music_player_a


func _get_sfx_stream(sfx_type: SFXType) -> AudioStream:
	# Return cached stream if available
	if _sfx_cache.has(sfx_type):
		return _sfx_cache[sfx_type]

	# Try to load
	var path: String = _sfx_paths.get(sfx_type, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null

	var stream := load(path) as AudioStream
	if stream:
		_sfx_cache[sfx_type] = stream
	return stream


func _save_volume_settings() -> void:
	var config := ConfigFile.new()
	for bus_name in [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_AMBIENCE]:
		config.set_value("audio", bus_name, get_bus_volume(bus_name))
	config.save("user://audio_settings.cfg")


func _load_volume_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://audio_settings.cfg")
	if err != OK:
		return

	for bus_name in [BUS_MASTER, BUS_MUSIC, BUS_SFX, BUS_AMBIENCE]:
		if config.has_section_key("audio", bus_name):
			var vol: float = config.get_value("audio", bus_name, 0.0)
			set_bus_volume(bus_name, vol)
