extends GdUnitTestSuite
## S8-U5: the unit card's Wounds button (RadialMenuController.card_open_wounds) must apply the same
## Tough(1) gate as the radial route (radial_menu_controller.gd, "regiment_tray" context). A Tough(X>1)
## regiment keeps per-model wound tracking; opening the regiment POOL dialog on it reads the stale pooled
## counter (regiment.wounds_taken == 0) and apply_regiment_wounds then rewrites every model's wounds from
## it — a damaged Tough(3) regiment is healed when damage is applied through the card.

const CELL := 0.025
const OPRArmyManagerScript = preload("res://scripts/opr_army_manager.gd")


## Records which model the card opened the wounds dialog on; builds no UI.
class SpyWoundsDialog:
	extends WoundsDialog
	var opened: ModelInstance = null

	func open(model: ModelInstance) -> void:
		opened = model


func _game_unit(n: int, tough: int, unit_id: String = "card_reg") -> GameUnit:
	var gu := GameUnit.new()
	gu.unit_id = unit_id
	gu.unit_properties = {"base_width_mm": 25, "base_depth_mm": 25, "regiment_mode": true}
	for i in range(n):
		var mi := ModelInstance.new()
		var node := Node3D.new()
		add_child(node)
		auto_free(node)
		mi.node = node
		mi.is_alive = true
		mi.wounds_max = tough
		mi.wounds_current = tough
		mi.properties["tough"] = tough
		mi.unit = gu
		gu.models.append(mi)
	return gu


func _army_manager() -> OPRArmyManager:
	var om: Node3D = auto_free(Node3D.new())
	om.name = "ObjectManager"
	add_child(om)
	var am: OPRArmyManager = auto_free(OPRArmyManagerScript.new())
	am.name = "OPRArmyManager"
	om.add_child(am)
	am.object_manager = om
	return am


func _formed_regiment(am: OPRArmyManager, gu: GameUnit, frontage: int) -> RegimentTray:
	var members := RegimentTray.collect_members(gu)
	var tray: RegimentTray = auto_free(RegimentTray.new())
	add_child(tray)
	tray.form(members.nodes, members.footprints, frontage)
	var regiment := Regiment.new(gu, tray, frontage)
	tray.set_meta("regiment", regiment)
	gu.unit_properties["frontage"] = frontage
	am.regiments[gu.unit_id] = regiment
	return tray


func _controller(am: OPRArmyManager) -> Array:
	var rc: RadialMenuController = auto_free(RadialMenuController.new())
	var dlg: SpyWoundsDialog = auto_free(SpyWoundsDialog.new())
	rc.army_manager = am
	rc.wounds_dialog = dlg
	return [rc, dlg]


func _remaining(gu: GameUnit) -> int:
	var total := 0
	for m in gu.models:
		if m.is_alive:
			total += m.wounds_current
	return total


func test_card_on_damaged_tough3_regiment_opens_the_per_model_dialog_not_the_pool() -> void:
	var am := _army_manager()
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	gu.models[0].wounds_current = 1  # two wounds already taken on model 0; pool counter still 0
	var pair := _controller(am)
	var rc: RadialMenuController = pair[0]
	var dlg: SpyWoundsDialog = pair[1]

	rc.card_open_wounds(gu)

	assert_object(dlg.opened).is_not_null()
	# The per-model dialog edits a real model; the pool dialog edits a proxy that is not in gu.models.
	assert_bool(gu.models.has(dlg.opened)).is_true()
	assert_object(rc._regiment_wound_dialog_tray).is_null()


func test_card_wound_on_damaged_tough3_regiment_never_heals_the_unit() -> void:
	var am := _army_manager()
	var gu := _game_unit(2, 3)
	_formed_regiment(am, gu, 2)
	gu.models[0].wounds_current = 1  # remaining wounds [1, 3] = 4
	var before := _remaining(gu)
	var pair := _controller(am)
	var rc: RadialMenuController = pair[0]
	var dlg: SpyWoundsDialog = pair[1]

	rc.card_open_wounds(gu)
	# What the dialog's "-" button does: one wound off the opened model, then emit wounds_changed.
	var edited: ModelInstance = dlg.opened
	edited.wounds_current -= 1
	if edited.wounds_current <= 0:
		edited.is_alive = false
	rc._on_wounds_changed(edited, edited.wounds_current)

	var after := _remaining(gu)
	assert_int(after).is_less_equal(before)
	assert_int(after).is_equal(before - 1)


func test_card_on_tough1_regiment_still_opens_the_pool_dialog() -> void:
	var am := _army_manager()
	var gu := _game_unit(10, 1)
	var tray := _formed_regiment(am, gu, 5)
	var pair := _controller(am)
	var rc: RadialMenuController = pair[0]
	var dlg: SpyWoundsDialog = pair[1]

	rc.card_open_wounds(gu)

	assert_object(dlg.opened).is_not_null()
	# Pool proxy: wounds_max = the pool (10), a model that is not one of the unit's real models.
	assert_int(dlg.opened.wounds_max).is_equal(10)
	assert_bool(gu.models.has(dlg.opened)).is_false()
	assert_object(rc._regiment_wound_dialog_tray).is_same(tray)
