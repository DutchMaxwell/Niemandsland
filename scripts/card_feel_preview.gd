extends Control
## DEV-ONLY tuning harness for the unit-dock card feel + design (Handover D). F6 this scene: the top row
## shows PRESENTED-card faces (Tactical-HUD design, CardFace) in each state — default, wounded,
## out-of-coherency, destroyed; the bottom shows the compact STRIP-card variant, dealt into a hand-fan.
## Hover to feel the tilt/lift/spring. Tunables: scripts/card_visual.gd; design: scripts/card_face.gd.
## NOT shipped in game.

const PCARD: Vector2 = Vector2(300, 300)
const SCARD: Vector2 = Vector2(150, 82)


func _ready() -> void:
	var hint := Label.new()
	hint.text = "Card design/feel preview (dev) — hover the cards. Design: card_face.gd · Feel: card_visual.gd"
	hint.position = Vector2(24, 18)
	add_child(hint)

	var states: Array = [
		{"name": "Assault Brothers", "points": 215, "quality": 3, "defense": 3, "alive": 10, "total": 10,
			"activated": true, "coherent": true, "rules": "Fearless · Relentless",
			"weapons": [{"name": "CCW", "meta": "A2"}, {"name": "Heavy Rifle", "meta": "30\" A1 AP1"}]},
		{"name": "Skeleton Warriors", "points": 130, "quality": 4, "defense": 4, "alive": 6, "total": 10,
			"fatigued": true, "coherent": true, "rules": "Undead · Banner · Fearless",
			"weapons": [{"name": "Hand Weapon", "meta": "A1"},
				{"name": "2x Spear", "meta": "A1", "rules": "Counter"}]},
		{"name": "Royal Guard", "points": 180, "quality": 3, "defense": 2, "alive": 4, "total": 5,
			"shaken": true, "coherent": false, "rules": "Undead · Fear",
			"weapons": [{"name": "Great Weapon", "meta": "A2 AP2", "rules": "Rending"}]},
		{"name": "Gun Drones", "points": 90, "quality": 5, "defense": 5, "alive": 0, "total": 3,
			"dead": true, "coherent": true},
		{"name": "Wormhole Daemons of Change", "points": 305, "quality": 3, "defense": 4, "alive": 8,
			"total": 8, "caster": true, "coherent": true,
			"rules": "Caster(2) · Flying · Fear · Tough(6) · Strider",
			"weapons": [{"name": "Warp Blade", "meta": "A3 AP2", "rules": "Rending"},
				{"name": "Bolt Pistol", "meta": "12\" A2 AP1"}, {"name": "Chaos Icon", "meta": "A1"},
				{"name": "Daemon Claws", "meta": "A4 AP1", "rules": "Counter, Deadly(2)"}]},
	]

	# Top row: presented-card faces, one per state (last = longest real name).
	var px0: float = 120.0
	for i in range(states.size()):
		var card := CardVisual.new()
		card.size = PCARD
		add_child(card)
		card.set_content_node(CardFace.build_presented(states[i]))
		# Destroyed unit: desaturate the whole card to the tray-parking grey language.
		if bool(states[i].get("dead", false)):
			card.modulate = Color(0.60, 0.60, 0.64)
		var pos := Vector2(px0 + i * (PCARD.x + 40.0), 110.0)
		card.snap_to(pos + Vector2(0, 200), 0.0, 0.7)
		card.spring_to(pos, 0.0, 1.0)

	# Bottom row: compact strip cards dealt into a slight hand-fan.
	var n := 8
	var sx0: float = 220.0
	var row_y: float = 470.0
	for i in range(n):
		var card := CardVisual.new()
		card.size = SCARD
		add_child(card)
		card.set_content_node(CardFace.build_presented(states[i % states.size()], Callable(), false))
		card.snap_to(Vector2(sx0 + i * (SCARD.x + 18.0), row_y + 160.0), 0.0, 0.6)
		var fan: float = (float(i) - float(n - 1) / 2.0) * CardVisual.FAN_DEG_PER_CARD
		card.set_fan(fan)
		card.spring_to(Vector2(sx0 + i * (SCARD.x + 18.0), row_y), fan, 1.0)
