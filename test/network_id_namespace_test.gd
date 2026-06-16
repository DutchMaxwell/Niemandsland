extends GdUnitTestSuite
## network_id namespacing for OPR-owned objects (opr_army_manager.gd): an owned id is
## slot*STRIDE + a PURE low counter, so two players' armies never collide on the wire
## regardless of import order, while the shared _object_counter stays a small monotonic
## value (the +10000..+50000 non-OPR offset bands depend on it).

const OPRArmyManagerScript := preload("res://scripts/opr_army_manager.gd")
const STRIDE := OPRArmyManager.OPR_NET_ID_SLOT_STRIDE


## A bare stand-in for ObjectManager (typed Node3D in OPRArmyManager) exposing only the
## shared int counter the helper needs.
func _stub_object_manager() -> Node3D:
	var om: Node3D = auto_free(Node3D.new())
	var src := GDScript.new()
	src.source_code = "extends Node3D\nvar _object_counter: int = 0\n"
	src.reload()
	om.set_script(src)
	return om


func _make_manager(om: Node3D) -> Object:
	var mgr: Object = auto_free(OPRArmyManagerScript.new())
	mgr.object_manager = om
	return mgr


func test_id_is_slot_prefix_plus_counter() -> void:
	var om := _stub_object_manager()
	var mgr := _make_manager(om)
	assert_int(mgr._next_owned_net_id(2)).is_equal(2 * STRIDE + 1)
	assert_int(mgr._next_owned_net_id(2)).is_equal(2 * STRIDE + 2)


func test_counter_stays_pure_low() -> void:
	var om := _stub_object_manager()
	var mgr := _make_manager(om)
	for i in range(5):
		mgr._next_owned_net_id(7)
	# The shared counter is the bare call count, NOT slot-prefixed.
	assert_int(om._object_counter).is_equal(5)


func test_two_slots_never_collide() -> void:
	var om := _stub_object_manager()
	var mgr := _make_manager(om)
	var slot1: Array = []
	var slot2: Array = []
	for i in range(40):
		slot1.append(mgr._next_owned_net_id(1))
		slot2.append(mgr._next_owned_net_id(2))
	for id1 in slot1:
		assert_bool(slot2.has(id1)).is_false()


func test_slot_zero_floored_to_one() -> void:
	var om := _stub_object_manager()
	var mgr := _make_manager(om)
	var id: int = mgr._next_owned_net_id(0)
	assert_int(id).is_greater_equal(STRIDE + 1)  # floored to slot 1
	assert_int(id).is_less(2 * STRIDE)
