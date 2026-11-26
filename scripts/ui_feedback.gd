extends Node
## Autoload: global UI feedback. Wires every BaseButton (already in the tree + added
## later) for tactile hover/press motion via UiMotion — one node_added hook, zero
## per-button code. UI sound is added on the same hook. Honours
## GraphicsSettings.reduce_motion through UiMotion.

const WIRED_META := "_ui_feedback_wired"

# ===== UI sound (procedural, no assets) =====
const SFX_POOL := 4
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _snd_click: AudioStreamWAV
var _snd_confirm: AudioStreamWAV
var _snd_back: AudioStreamWAV
var _snd_hover: AudioStreamWAV
var _snd_focus: AudioStreamWAV
var _snd_card: AudioStreamWAV
var _snd_panel_in: AudioStreamWAV
var _snd_panel_out: AudioStreamWAV


func _ready() -> void:
	_setup_audio()
	get_tree().node_added.connect(_on_node_added)
	_wire_existing(get_tree().root)


func _setup_audio() -> void:
	# A small pool so rapid clicks overlap instead of cutting each other off.
	var bus := "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	for _i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	# Quiet, sub-300ms tones. Click = neutral tick, confirm = rising two-tone (primary),
	# back = lower single tone (destructive/cancel). Hover/focus are far quieter
	# micro-ticks: hover fires on every mouse sweep across a button row, focus covers
	# keyboard/controller navigation (the playbook's "quiet focus tick").
	_snd_click = _tone([1200.0], 0.035, 0.16)
	_snd_confirm = _tone([880.0, 1320.0], 0.06, 0.18)
	_snd_back = _tone([440.0], 0.05, 0.15)
	_snd_hover = _tone([1600.0], 0.02, 0.05)
	_snd_focus = _tone([1000.0], 0.025, 0.07)
	# Card deal-in: a soft low two-tone swish for the unit-dock present (D5).
	_snd_card = _tone([420.0, 630.0], 0.09, 0.13)
	# A panel or sheet opening / closing: a soft noise sweep, rising on the way in, falling on the way
	# out.
	_snd_panel_in = _sweep(400.0, 1600.0, 0.18, 0.06)
	_snd_panel_out = _sweep(1600.0, 400.0, 0.14, 0.06)


## Plays the unit-card deal-in cue (the dock calls this on present). Procedural, on the UI bus, and
## naturally quiet so a rapid selection sweep never machine-guns. Action chips already sound via the
## global BaseButton hook, so no extra wiring is needed there.
func play_card_deal() -> void:
	_play(_snd_card)


## A panel or sheet opens (`opening`) or closes: the soft noise sweep of the sound table.
func play_panel(opening: bool) -> void:
	_play(_snd_panel_in if opening else _snd_panel_out)


func _play(stream: AudioStream) -> void:
	if stream == null or _players.is_empty():
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = randf_range(0.98, 1.02)  # avoid machine-gun on rapid clicks
	p.play()


func _sound_for(b: BaseButton) -> AudioStreamWAV:
	match b.theme_type_variation:
		&"PrimaryButton", HouseStyle.PRIMARY, HouseStyle.BAR_PRIMARY:
			return _snd_confirm
		&"DangerButton", HouseStyle.DANGER_BUTTON:
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


## A filtered-noise sweep: white noise (a fixed seed, so the sound is always the same) through a
## resonant band-pass whose centre glides from `from_hz` to `to_hz`, shaped by a smooth envelope,
## peak `vol`.
func _sweep(from_hz: float, to_hz: float, dur: float, vol: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * float(rate))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var samples := PackedFloat32Array()
	samples.resize(n)
	var low := 0.0
	var band := 0.0
	var peak := 0.0001
	for i in n:
		var u := float(i) / float(n)
		var f := 2.0 * sin(PI * from_hz * pow(to_hz / from_hz, u) / float(rate))
		var high := rng.randf_range(-1.0, 1.0) - low - 0.35 * band
		band += f * high
		low += f * band
		samples[i] = band * sin(PI * u)
		peak = maxf(peak, absf(samples[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * vol, -1.0, 1.0) * 32767.0))
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
	b.mouse_entered.connect(func() -> void: _play(_snd_hover))
	# Keyboard/controller navigation feedback; FOCUS_NONE buttons never fire this.
	b.focus_entered.connect(func() -> void: _play(_snd_focus))
