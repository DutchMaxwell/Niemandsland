extends Control

# Interactive Soundboard Tool for Playing Multiple Sound Effects
class_name InteractiveSoundboard

# UI References
@export var sound_buttons_container: GridContainer
@export var master_volume_slider: HSlider
@export var master_volume_label: Label
@export var stop_all_button: Button
@export var clear_all_button: Button
@export var file_dialog: FileDialog

# Sound slot data structure
class SoundSlot:
	var button: Button
	var audio_player: AudioStreamPlayer
	var file_path: String = ""
	var original_text: String = ""
	var volume: float = 1.0
	var is_looping: bool = false

# Sound management
const MAX_SOUND_SLOTS: int = 12
var sound_slots: Array[SoundSlot] = []
var currently_loading_slot: int = -1
var master_volume: float = 0.5

func _ready() -> void:
	# Get UI references
	sound_buttons_container = $MarginContainer/VBoxContainer/MainPanel/MarginContainer/VBoxContainer/ScrollContainer/SoundButtonsContainer
	master_volume_slider = $MarginContainer/VBoxContainer/MainPanel/MarginContainer/VBoxContainer/ControlsPanel/MarginContainer/VBoxContainer/VolumeControl/HBoxContainer/VolumeSlider
	master_volume_label = $MarginContainer/VBoxContainer/MainPanel/MarginContainer/VBoxContainer/ControlsPanel/MarginContainer/VBoxContainer/VolumeControl/HBoxContainer/VolumeLabel
	stop_all_button = $MarginContainer/VBoxContainer/MainPanel/MarginContainer/VBoxContainer/ControlsPanel/MarginContainer/VBoxContainer/ButtonsContainer/StopAllButton
	clear_all_button = $MarginContainer/VBoxContainer/MainPanel/MarginContainer/VBoxContainer/ControlsPanel/MarginContainer/VBoxContainer/ButtonsContainer/ClearAllButton
	file_dialog = $FileDialog
	
	# Initialize file dialog
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.ogg", "OGG Audio Files")
	file_dialog.add_filter("*.mp3", "MP3 Audio Files")
	file_dialog.add_filter("*.wav", "WAV Audio Files")
	file_dialog.file_selected.connect(_on_file_selected)
	
	# Initialize sound slots
	_create_sound_slots()
	
	# Connect control signals
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	stop_all_button.pressed.connect(_stop_all_sounds)
	clear_all_button.pressed.connect(_clear_all_sounds)
	
	# Set initial values
	master_volume_slider.value = master_volume
	_update_volume_label()

func _create_sound_slots() -> void:
	for i in range(MAX_SOUND_SLOTS):
		var slot: SoundSlot = SoundSlot.new()
		
		# Create button
		slot.button = Button.new()
		slot.button.custom_minimum_size = Vector2(150, 80)
		slot.button.text = "Empty Slot %d" % (i + 1)
		slot.original_text = slot.button.text
		slot.button.pressed.connect(_on_sound_button_pressed.bind(i))
		
		# Add right-click functionality
		slot.button.gui_input.connect(_on_button_input.bind(i))
		
		# Create audio player
		slot.audio_player = AudioStreamPlayer.new()
		slot.audio_player.bus = "Master"
		add_child(slot.audio_player)
		
		# Add button to container
		sound_buttons_container.add_child(slot.button)
		
		# Store slot
		sound_slots.append(slot)

func _on_sound_button_pressed(slot_index: int) -> void:
	var slot: SoundSlot = sound_slots[slot_index]
	
	if not slot.audio_player.stream:
		# No sound loaded, open file dialog
		currently_loading_slot = slot_index
		file_dialog.popup_centered(Vector2(800, 600))
	else:
		# Toggle playback
		if slot.audio_player.playing:
			slot.audio_player.stop()
			slot.button.modulate = Color.WHITE
		else:
			slot.audio_player.play()
			slot.button.modulate = Color(0.7, 1.0, 0.7)  # Green tint when playing

func _on_button_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_show_slot_context_menu(slot_index)

func _show_slot_context_menu(slot_index: int) -> void:
	var slot: SoundSlot = sound_slots[slot_index]
	var popup_menu: PopupMenu = PopupMenu.new()
	
	popup_menu.add_item("Load Sound...", 0)
	if slot.audio_player.stream:
		popup_menu.add_separator()
		popup_menu.add_check_item("Loop", 1)
		popup_menu.set_item_checked(1, slot.is_looping)
		popup_menu.add_separator()
		popup_menu.add_item("Clear Slot", 2)
	
	popup_menu.id_pressed.connect(_on_context_menu_pressed.bind(slot_index))
	# Property 'popup_on_parent' is read-only and can't be changed, this line is removed.
	add_child(popup_menu)
	popup_menu.popup(Rect2(get_global_mouse_position(), Vector2.ZERO))
	
	# Clean up popup after it's hidden
	popup_menu.popup_hide.connect(func() -> void: popup_menu.queue_free())

func _on_context_menu_pressed(id: int, slot_index: int) -> void:
	match id:
		0:  # Load Sound
			currently_loading_slot = slot_index
			file_dialog.popup_centered(Vector2(800, 600))
		1:  # Toggle Loop
			var sound_slot: SoundSlot = sound_slots[slot_index]
			sound_slot.is_looping = not sound_slot.is_looping
			if sound_slot.audio_player.stream:
				sound_slot.audio_player.stream.loop = sound_slot.is_looping
		2:  # Clear Slot
			_clear_slot(slot_index)

func _on_file_selected(path: String) -> void:
	if currently_loading_slot < 0 or currently_loading_slot >= sound_slots.size():
		return
	
	var slot: SoundSlot = sound_slots[currently_loading_slot]
	
	# Load the audio file
	var audio_stream: AudioStream = load(path)
	if audio_stream:
		slot.audio_player.stream = audio_stream
		slot.file_path = path
		
		# Update button text with filename
		var filename: String = path.get_file().get_basename()
		slot.button.text = filename
		slot.button.tooltip_text = path
		
		# Apply looping setting
		if audio_stream.has_method("set_loop"):
			audio_stream.loop = slot.is_looping
		
		# Update volume
		_update_slot_volume(currently_loading_slot)
	
	currently_loading_slot = -1

func _clear_slot(slot_index: int) -> void:
	var slot: SoundSlot = sound_slots[slot_index]
	
	slot.audio_player.stop()
	slot.audio_player.stream = null
	slot.file_path = ""
	slot.button.text = slot.original_text
	slot.button.tooltip_text = ""
	slot.button.modulate = Color.WHITE
	slot.is_looping = false

func _on_master_volume_changed(value: float) -> void:
	master_volume = value
	_update_volume_label()
	
	# Update all sound volumes
	for i in range(sound_slots.size()):
		_update_slot_volume(i)

func _update_slot_volume(slot_index: int) -> void:
	var slot: SoundSlot = sound_slots[slot_index]
	var combined_volume: float = slot.volume * master_volume
	
	# Convert to decibels (0 to 1 -> -80 to 0 dB)
	if combined_volume <= 0.0:
		slot.audio_player.volume_db = -80.0
	else:
		slot.audio_player.volume_db = linear_to_db(combined_volume)

func _update_volume_label() -> void:
	master_volume_label.text = "%d%%" % (master_volume * 100)

func _stop_all_sounds() -> void:
	for slot in sound_slots:
		if slot.audio_player.playing:
			slot.audio_player.stop()
			slot.button.modulate = Color.WHITE

func _clear_all_sounds() -> void:
	for i in range(sound_slots.size()):
		_clear_slot(i)

func _input(event: InputEvent) -> void:
	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			_stop_all_sounds()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var index: int = event.keycode - KEY_1
			if index < sound_slots.size():
				_on_sound_button_pressed(index)
