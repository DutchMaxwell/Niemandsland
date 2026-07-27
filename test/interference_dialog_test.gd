extends GdUnitTestSuite
## Zauber-Welle F1: die reine Vorschau-Zeile des Interferenz-Tableaus (Wurfziel + Erfolgs-Odds
## vor/nach dem Token-Einsatz) — das Herzstück der Maintainer-Anforderung "direkte Einsicht".


func test_preview_line_shows_shifted_target_and_odds() -> void:
	# Basis 4+ ohne Boost: 2 Interferenz-Token -> 6+, 50% -> 17%.
	assert_str(InterferenceDialog.format_preview(4, 0, 2)).is_equal("Cast roll: 4+ → 6+   (success 50% → 17%)")
	# Geboosteter Wurf (Boost 1 -> 3+): 1 Token zurück auf 4+.
	assert_str(InterferenceDialog.format_preview(4, 1, 1)).is_equal("Cast roll: 3+ → 4+   (success 67% → 50%)")
	# Klemme: mehr Token verschlechtern nie über 6+ hinaus.
	assert_str(InterferenceDialog.format_preview(4, 0, 9)).contains("→ 6+")


func test_boost_preview_improves_target() -> void:
	# Eigener Cast: 2 Boost-Token heben 4+ auf 2+ (50% → 83%).
	assert_str(InterferenceDialog.format_preview_boost(4, 0, 2)).is_equal("Cast roll: 4+ → 2+   (success 50% → 83%)")
	# Gegen bekannte Interferenz 1: Boost 1 stellt 5+ zurück auf 4+.
	assert_str(InterferenceDialog.format_preview_boost(4, 1, 1)).is_equal("Cast roll: 5+ → 4+   (success 33% → 50%)")
