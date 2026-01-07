extends RichTextLabel

func _on_meta_clicked(meta: Variant) -> void:
	if meta is String:
		OS.shell_open(meta)
