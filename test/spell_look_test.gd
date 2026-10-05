extends GdUnitTestSuite
## SpellLook: a spell's element comes from its name with an arcane fallback (the five spells the maintainer approved on
## 05.10. each land on their own element), and every element has a tint and a particle look.

const LookScript = preload("res://scripts/vfx/spell_look.gd")


func test_the_element_comes_from_the_spell_name() -> void:
	var E = LookScript.Element
	var table := {"Sky Blaze": E.FIRE, "Fire Ball": E.FIRE, "Lightning Fog": E.LIGHTNING, "Ice Maw": E.FROST,
		"Psychic Terror": E.SHADOW, "Cerebral Trauma": E.ARCANE, "": E.ARCANE}
	for spell: String in table:
		assert_int(LookScript.element_of(spell)).override_failure_message(spell).is_equal(table[spell])


func test_every_element_has_a_tint_and_particles() -> void:
	assert_int(LookScript.TINTS.size()).is_equal(LookScript.Element.size())
	for el: int in LookScript.Element.values():
		assert_bool(LookScript.PARTICLES.has(el)).is_true()
