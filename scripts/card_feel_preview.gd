extends Control
## DEV-ONLY tuning harness for the unit-dock card feel + design (Handover D). F6 this scene: the top row
## shows PRESENTED-card faces (Tactical-HUD design, CardFace) in each state — default, wounded,
## out-of-coherency, destroyed; the bottom shows the compact STRIP-card variant, dealt into a hand-fan.
## Hover to feel the tilt/lift/spring. Tunables: scripts/card_visual.gd; design: scripts/card_face.gd.
## NOT shipped in game.

const PCARD: Vector2 = Vector2(300, 200)
const SCARD: Vector2 = Vector2(150, 108)


func _ready() -> void:
	var hint := Label.new()
	hint.text = "Card design/feel preview (dev) — hover the cards. Design: card_face.gd · Feel: card_visual.gd"
	hint.position = Vector2(24, 18)
	add_child(hint)

	var states: Array = [
		{"name": "Assault Brothers", "points": 215, "quality": 3, "defense": 3, "alive": 10, "total": 10,
			"activated": true, "coherent": true},
		{"name": "Skeleton Warriors", "points": 130, "quality": 4, "defense": 4, "alive": 6, "total": 10,
			"fatigued": true, "coherent": true},
		{"name": "Royal Guard", "points": 180, "quality": 3, "defense": 2, "alive": 4, "total": 5,
			"shaken": true, "coherent": false},
		{"name": "Gun Drones", "points": 90, "quality": 5, "defense": 5, "alive": 0, "total": 3,
			"dead": true, "coherent": true},
	]

	# Top row: presented-card faces, one per state.
	var px0: float = 200.0
	for i in range(states.size()):
		var card := CardVisual.new()
		card.size = PCARD
		add_child(card)
		card.set_content_node(CardFace.build_presented(states[i]))
		var pos := Vector2(px0 + i * (PCARD.x + 60.0), 120.0)
		card.snap_to(pos + Vector2(0, 180), 0.0, 0.7)
		card.spring_to(pos, 0.0, 1.0)

	# Bottom row: compact strip cards dealt into a slight hand-fan.
	var n := 8
	var sx0: float = 220.0
	var row_y: float = 470.0
	for i in range(n):
		var card := CardVisual.new()
		card.size = SCARD
		add_child(card)
		card.set_content_node(CardFace.build_strip(states[i % states.size()]))
		card.snap_to(Vector2(sx0 + i * (SCARD.x + 18.0), row_y + 160.0), 0.0, 0.6)
		var fan: float = (float(i) - float(n - 1) / 2.0) * CardVisual.FAN_DEG_PER_CARD
		card.set_fan(fan)
		card.spring_to(Vector2(sx0 + i * (SCARD.x + 18.0), row_y), fan, 1.0)
