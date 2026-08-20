extends GdUnitTestSuite
## #317 — the Takedown killability extension. The book tiers stand untouched
## (heroes, then costed upgrades); NEW behind them: softest armour first
## (higher Defense number = worse save), then the smaller remaining wound
## pool. A sniper team with no elite target in reach now hunts something it
## can actually kill instead of plinking a Tough(15)/2+ tank picked by bare
## nearest.


func _cand(dist: float, hero: bool, def: int, rtough: int, activated: bool = false) -> Dictionary:
	return {"dist": dist, "activated": activated, "in_cover": false, "defense": def,
		"is_hero": hero, "has_upgrade": false, "upgrade_cost": 0,
		"single_tough": false, "has_tough": rtough > 1, "remaining_tough": rtough,
		"blast_pref": 0}


func test_hero_tier_still_dominates_everything() -> void:
	# A hero in heavy armour outranks the flimsiest infantry — the book tier
	# stays the first word.
	var hero_tanky := _cand(20.0, true, 2, 6)
	var soft_near := _cand(5.0, false, 5, 5)
	assert_int(AiTargeting.best_index([soft_near, hero_tanky],
		AiTargeting.Overlay.TAKEDOWN)).is_equal(1)


func test_reported_game_tank_loses_to_the_squad() -> void:
	# The community game: Tough(15) tank at Def 2+ NEARER than a 10-model
	# Def 5+ squad. Old key: bare nearest -> tank. New key: softest armour
	# first -> the squad, despite the distance.
	var tank := _cand(8.0, false, 2, 15)
	var squad := _cand(15.0, false, 5, 10)
	assert_int(AiTargeting.best_index([tank, squad],
		AiTargeting.Overlay.TAKEDOWN)).is_equal(1)


func test_equal_armour_prefers_the_smaller_pool_then_base_key() -> void:
	# Same save: the five-wound unit dies sooner than the thirty-wound horde.
	var horde := _cand(6.0, false, 5, 30)
	var five := _cand(14.0, false, 5, 5)
	assert_int(AiTargeting.best_index([horde, five],
		AiTargeting.Overlay.TAKEDOWN)).is_equal(1)
	# Fully equal killability: the base key (not-activated, then nearest)
	# still decides — the official ordering survives underneath.
	var near_fresh := _cand(6.0, false, 5, 5)
	var far_acted := _cand(4.0, false, 5, 5, true)
	assert_int(AiTargeting.best_index([far_acted, near_fresh],
		AiTargeting.Overlay.TAKEDOWN)).is_equal(1)
