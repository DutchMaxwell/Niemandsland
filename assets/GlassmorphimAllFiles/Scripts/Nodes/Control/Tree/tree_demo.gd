extends Tree

func _ready() -> void:
	var root: TreeItem = create_item()
	root.set_text(0, "Tree")
	
	# First child: regular item
	var item: TreeItem = create_item(root)
	item.set_text(0, "Item")
	
	# Second child: editable item
	var editable_item: TreeItem = create_item(root)
	editable_item.set_text(0, "Editable Item")
	editable_item.set_editable(0, true)
	
	# Third child: sub-tree with checkbox item
	var sub_tree: TreeItem = create_item(root)
	sub_tree.set_text(0, "Sub Tree")
	
	var checkbox_item: TreeItem = create_item(sub_tree)
	checkbox_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	checkbox_item.set_text(0, "Checkbox Item")
	checkbox_item.set_editable(0, true)
	checkbox_item.set_checked(0, true)
