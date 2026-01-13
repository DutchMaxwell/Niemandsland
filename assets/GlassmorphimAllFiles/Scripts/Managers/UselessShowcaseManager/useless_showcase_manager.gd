extends Node

## Track how many times Simple SVG Editor has been visited
var svg_editor_visit_count: int = 0

## Track if we've returned from a showcase
var has_visited_showcase: bool = false

## Ensures the Glass Morphism main scene starts with the button view
func _ready() -> void:
	await get_tree().process_frame
	
	# Connect to child entered tree signal
	get_tree().root.child_entered_tree.connect(_on_child_entered_tree)
	
	# Find the Glass Morphism main scene if it's loaded
	var glass_morphism_scene: Node = _find_glass_morphism_scene(get_tree().root)
	if glass_morphism_scene:
		# Find the ViewNavigation node
		var view_navigation: Node = glass_morphism_scene.get_node_or_null("MainMarginContainer/HBoxContainer/MainPanel/MarginContainer/VBoxContainer/ShowcaseNavigationHBoxContainer")
		if view_navigation and view_navigation.has_method("_show_control"):
			# Force show the button view (index 0)
			view_navigation.call("_show_control", 0)
			# Also simulate button press to ensure proper state
		if view_navigation.get("buttons") != null:
				var buttons: Array = view_navigation.get("buttons")
				if buttons.size() > 0 and buttons[0] is Button:
					var button: Button = buttons[0] as Button
					button.set_pressed(true)


func _find_glass_morphism_scene(node: Node) -> Node:
	if node.name == "GlassmorphismMain":
		return node
	
	for child in node.get_children():
		var result: Node = _find_glass_morphism_scene(child)
		if result:
			return result
	
	return null


func _on_child_entered_tree(node: Node) -> void:
	# Check if this is the Simple SVG Editor
	if node.name == "SimpleSVGEditor":
		svg_editor_visit_count += 1
		has_visited_showcase = true
		# Only show warning dialogs in web version
		if OS.has_feature("web") and svg_editor_visit_count <= 2:
			_show_svg_editor_dialog(node)
		# No dialog for visits beyond the second visit or when not in web
	
	# Check for any showcase scene to mark as visited
	elif node.name in ["GlassmorphismMain", "SimpleSVGEditor", "SimpleDataVisualization", "SimpleFlowChart"]:
		has_visited_showcase = true
	
	# Check if we're returning to the main scene after visiting a showcase
	if has_visited_showcase:
		_check_and_skip_fairy_tutorial(node)


func _show_svg_editor_dialog(svg_editor: Node) -> void:
	# Create AcceptDialog
	var dialog: AcceptDialog = AcceptDialog.new()

	if svg_editor_visit_count == 1:
		dialog.title = "Warning!"
		dialog.dialog_text = "For Reference / Showcase Purposes Only! Making a functional \"Web Version\" is not on the Todo List!\n\nI used this to efficiently edit \"Phosphor Icons\" to be white, transparent, etc for this pack!\n\nIf you are going to use this UI Theme, you'll probably need to edit some other kinds of SVG icons!\n\nThis app can be \"downloaded\" for free with proper functionality! Again, the Web Version won't work!\n\nYou can check it out on my itch page!"
	elif svg_editor_visit_count == 2:
		dialog.title = "Warning! Again..."
		dialog.dialog_text = "TLDR:\n\nWeb Version No Work / Downloaded Version does!\n\nI Recommend Trying it Out / Available on my itch page!"

	dialog.size = Vector2(500, 300)
	
	# Configure dialog appearance
	dialog.unresizable = false
	dialog.popup_window = true
	
	# Add to the SVG editor as a child
	svg_editor.add_child(dialog)
	
	# Center the dialog on screen
	await svg_editor.get_tree().process_frame
	var viewport_size: Vector2 = svg_editor.get_viewport().get_visible_rect().size
	var dialog_size: Vector2 = Vector2(dialog.size.x, dialog.size.y)
	dialog.position = Vector2i((viewport_size - dialog_size) / 2)
	
	# Show the dialog
	dialog.popup_centered()
	
	# Clean up dialog when closed
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())


func _check_and_skip_fairy_tutorial(_node: Node) -> void:
	# Look for TutorialFairyManager in the root node's children
	var root_node: Node = get_tree().root
	
	# Search through all children of root for TutorialFairyManager
	for child in root_node.get_children():
		var fairy_manager: Node = _find_tutorial_fairy_manager(child)
		if fairy_manager:
			fairy_manager.queue_free()
			break


func _find_tutorial_fairy_manager(node: Node) -> Node:
	# Check if this node is the TutorialFairyManager
	if node.name == "TutorialFairyManager":
		return node
	
	# Recursively search children
	for child in node.get_children():
		var result: Node = _find_tutorial_fairy_manager(child)
		if result:
			return result
	
	return null
