class_name ArmyReplaceConfirm
## The one question before an army lands in a seat that already holds one (maintainer, 27.11.2026): "Player N
## already has an army (<faction>, <pts>). Replace it?" - Replace / Keep. Asked by the army import and by
## "Bring NACHTMAHR" (the table's Opponent… page); an empty seat asks nothing and costs no frame.

const LAYER := 110   # over the army import sheet (OPRImportDialog.LAYER), under the loading overlay


## The question's line for the army `held` in seat `player_id`.
static func text(player_id: int, held: OPRApiClient.OPRArmy) -> String:
	var faction := held.faction_name if not held.faction_name.is_empty() else held.name
	var points := held.points if held.points > 0 else held.get_total_points()
	return "Player %d already has an army (%s, %d pts). Replace it?" % [player_id, faction, points]


## True when `armies` (seat -> OPRArmy, the table's) holds an army in `player_id`.
static func occupied(armies: Dictionary, player_id: int) -> bool:
	return armies.get(player_id) is OPRApiClient.OPRArmy


## Asks while the seat is held; true = go on (Replace), false = leave the seat as it is (Keep, Esc).
static func ask(armies: Dictionary, player_id: int) -> bool:
	var card := PromptCard.new("Replace the army?", text(player_id, armies[player_id]), "Replace", "Keep")
	card.layer = LAYER
	(Engine.get_main_loop() as SceneTree).root.add_child(card)
	return bool(await card.answer())
