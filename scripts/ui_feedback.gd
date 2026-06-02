extends Node
## Autoload: global UI feedback. Wires every BaseButton (already in the tree + added
## later) for tactile hover/press motion via UiMotion — one node_added hook, zero
## per-button code. UI sound is added on the same hook. Honours
## GraphicsSettings.reduce_motion through UiMotion.

const WIRED_META := "_ui_feedback_wired"


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_wire_existing(get_tree().root)


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
