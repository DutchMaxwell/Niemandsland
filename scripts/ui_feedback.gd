extends Node
## Autoload: global UI feedback. Wires every BaseButton (already in the tree + added
## later) for tactile hover/press motion via UiMotion — one node_added hook, zero
## per-button code. UI sound is added on the same hook. Honours
## GraphicsSettings.reduce_motion through UiMotion.

const WIRED_META := "_ui_feedback_wired"

# ===== UI sound (procedural, no assets) =====
var _player: AudioStreamPlayer
var _snd_click: AudioStreamWAV
var _snd_confirm: AudioStreamWAV
var _snd_back: AudioStreamWAV


func _ready() -> void:
	_setup_audio()
	get_tree().node_added.connect(_on_node_added)
	_wire_existing(get_tree().root)


func _setup_audio() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	add_child(_player)
	# Quiet, sub-300ms tones. Click = neutral tick, confirm = rising two-tone (primary),
	# back = lower single tone (destructive/cancel).
	_snd_click = _tone([1200.0], 0.035, 0.16)
	_snd_confirm = _tone([880.0, 1320.0], 0.06, 0.18)
	_snd_back = _tone([440.0], 0.05, 0.15)


func _play(stream: AudioStream) -> void:
	if _player == null or stream == null:
		return
	_player.stream = stream
	_player.pitch_scale = randf_range(0.98, 1.02)  # avoid machine-gun on rapid clicks
	_player.play()


func _sound_for(b: BaseButton) -> AudioStreamWAV:
	match b.theme_type_variation:
		&"PrimaryButton":
			return _snd_confirm
		&"DangerButton":
			return _snd_back
		_:
			return _snd_click


## Short procedural tone: sum of sine partials with a fast exponential decay -> 16-bit WAV.
func _tone(freqs: Array, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * float(rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := exp(-t * 22.0)
		var s := 0.0
		for f in freqs:
			s += sin(TAU * float(f) * t)
		s = s / float(freqs.size()) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire(node as BaseButton)


func _wire_existing(root: Node) -> void:
	for child in root.get_children():
		if child is BaseButton:
			_wire(child as BaseButton)
		_wire_existing(child)


func _wire(b: BaseButton) -> void:
	if b.has_meta(WIRED_META):
		return
	b.set_meta(WIRED_META, true)
	UiMotion.attach_button(b)
	b.pressed.connect(func() -> void: _play(_sound_for(b)))
