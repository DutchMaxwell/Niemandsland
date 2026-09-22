extends Node3D
## A transform observer without geometry. Visual meshes live outside the rule owner.

signal moved
signal leaving


func _ready() -> void:
	# Ctrl+C/Ctrl+V duplicates native child nodes. The new owner gets a fresh observer.
	if get_meta("urban_owner_id",0) != get_parent().get_instance_id():
		queue_free()
		return
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		moved.emit()


func _exit_tree() -> void:
	leaving.emit()
