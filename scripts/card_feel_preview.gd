extends Control
## DEV-ONLY tuning harness for the unit-dock card feel (Handover D). F6 this scene, hover the cards and
## watch the Balatro-style tilt, hover-lift, spring-into-place, deal-in overshoot and hand-fan. Every
## knob lives in scripts/card_visual.gd (CardVisual's tunable constants). NOT shipped in game — remove
## or keep clearly marked dev before merge.

const N: int = 8
const CARD_SIZE: Vector2 = Vector2(152, 210)


func _ready() -> void:
	var hint := Label.new()
	hint.text = "CardVisual tuning preview (dev) — hover the cards. Tunables: scripts/card_visual.gd"
	hint.position = Vector2(24, 20)
	add_child(hint)

	var row_y: float = 360.0
	var spacing: float = 172.0
	var x0: float = 220.0
	for i in range(N):
		var card := CardVisual.new()
		card.size = CARD_SIZE
		add_child(card)
		card.set_content_node(_demo_content(i))
		# Start small + below the row, then deal into place with the spring's overshoot/settle.
		card.snap_to(Vector2(x0 + i * spacing, row_y + 220.0), 0.0, 0.6)
		var fan: float = (float(i) - float(N - 1) / 2.0) * CardVisual.FAN_DEG_PER_CARD
		card.set_fan(fan)
		card.spring_to(Vector2(x0 + i * spacing, row_y), fan, 1.0)


func _demo_content(i: int) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = CARD_SIZE
	v.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Unit %d" % (i + 1)
	v.add_child(title)
	var stats := Label.new()
	stats.text = "Q 4+   D 3+"
	v.add_child(stats)
	var models := Label.new()
	models.text = "%d models" % (5 + i)
	v.add_child(models)
	return v
