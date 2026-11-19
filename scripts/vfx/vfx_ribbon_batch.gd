class_name VfxRibbonBatch
extends MultiMeshInstance3D
## 1-draw-call MultiMesh batcher for up to 128 camera-facing tapered HDR tracer ribbons (with dark sand-contrast edge)
## and static reduced-motion sight-line threads. Ticked by packed float arrays — zero per-tracer node or tween churn.

const MAX_RIBBONS := 128
const SHADER_RES: Shader = preload("res://shaders/vfx_ribbon_batch.gdshader")
const STATIC_LIFE_S := 0.5

var auto_free_when_empty: bool = true

var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _delay := PackedFloat32Array()
var _width := PackedFloat32Array()
var _static := PackedByteArray()
var _cursor := 0
var _active := 0
var _mm: MultiMesh


func _init() -> void:
	_age.resize(MAX_RIBBONS)
	_life.resize(MAX_RIBBONS)
	_delay.resize(MAX_RIBBONS)
	_width.resize(MAX_RIBBONS)
	_static.resize(MAX_RIBBONS)
	_age.fill(0.0)
	_life.fill(0.0)
	_delay.fill(0.0)
	_width.fill(0.0)
	_static.fill(0)

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = MAX_RIBBONS
	for i in MAX_RIBBONS:
		_mm.set_instance_transform(i, Transform3D())
		_mm.set_instance_color(i, Color.WHITE)
		_mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
	multimesh = _mm

	var mat := ShaderMaterial.new()
	mat.shader = SHADER_RES
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0


func active_count() -> int:
	return _active


func is_slot_static(slot: int) -> bool:
	return slot >= 0 and slot < MAX_RIBBONS and _static[slot] != 0


## Enqueue one tracer or static sight-line thread from `a` to `b`. Returns its ring-buffer slot index.
func push_ribbon(a: Vector3, b: Vector3, tint: Color, width_m: float, duration_s: float,
		delay_s: float = 0.0, static_line: bool = false, hdr_boost: float = 1.9) -> int:
	var slot := _acquire_slot()
	var seg := b - a
	var mid := (a + b) * 0.5
	var seg_basis := Basis(Vector3.RIGHT, seg, Vector3.FORWARD)
	_mm.set_instance_transform(slot, Transform3D(seg_basis, mid))
	_mm.set_instance_color(slot, Color(tint.r, tint.g, tint.b, hdr_boost))
	_age[slot] = -maxf(delay_s, 0.0)
	_life[slot] = maxf(duration_s, 0.02)
	_delay[slot] = maxf(delay_s, 0.0)
	_width[slot] = maxf(width_m, 0.0005)
	_static[slot] = 1 if static_line else 0
	_write_slot_visual(slot)
	set_process(true)
	return slot


func _acquire_slot() -> int:
	for k in MAX_RIBBONS:
		var idx := (_cursor + k) % MAX_RIBBONS
		if _life[idx] <= 0.0:
			_cursor = (idx + 1) % MAX_RIBBONS
			_active += 1
			return idx
	var evict := _cursor
	_cursor = (_cursor + 1) % MAX_RIBBONS
	return evict


func _write_slot_visual(slot: int) -> void:
	var age := _age[slot]
	var life := _life[slot]
	if life <= 0.0 or age < 0.0 or age >= life:
		_mm.set_instance_custom_data(slot, Color(0.0, 0.0, 0.0, 0.0))
		return
	var u := clampf(age / life, 0.0, 1.0)
	if _static[slot] != 0:
		var fade := 1.0 - smoothstep(0.65, 1.0, u)
		_mm.set_instance_custom_data(slot, Color(1.0, 0.0, _width[slot], -maxf(fade, 0.002)))
	else:
		var raw_head := u * 1.38 + 0.08
		var head := clampf(raw_head, 0.0, 1.0)
		var tail := clampf(raw_head - 0.50, 0.0, 1.0)
		var fade := 1.0 - smoothstep(0.88, 1.0, u)
		_mm.set_instance_custom_data(slot, Color(head, tail, _width[slot], maxf(fade, 0.002)))


func _process(delta: float) -> void:
	if _active <= 0:
		set_process(false)
		if auto_free_when_empty:
			queue_free()
		return
	var alive := 0
	for i in MAX_RIBBONS:
		var life := _life[i]
		if life <= 0.0:
			continue
		var next_age := _age[i] + delta
		if next_age >= life:
			_life[i] = 0.0
			_age[i] = 0.0
			_width[i] = 0.0
			_static[i] = 0
			_mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
			continue
		_age[i] = next_age
		_write_slot_visual(i)
		alive += 1
	_active = alive
	if _active <= 0:
		set_process(false)
		if auto_free_when_empty:
			queue_free()
