extends GdUnitTestSuite
## The relief of the town's surfaces (plan R2a ground, R2b walls and roofs): every pattern reports a height, the end of the fragment shader bends the normal from its gradient and sets roughness and
## occlusion. The headless run has a dummy renderer, so these pin the mechanism; the capture judges the look (street, macro: each sett has a lit and a shadow side under a lantern).

const SHADER := "res://shaders/ruintown_board.gdshader"


func test_the_height_becomes_a_bent_normal_with_occlusion_at_the_end_of_the_fragment_shader() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("float depth_in = 0.0;")).is_true()
	assert_bool(src.contains("NORMAL = normalize(abs(det) * NORMAL - grad);")).override_failure_message("the surface-gradient bump is missing").is_true()
	assert_bool(src.contains("AO = ao;")).is_true()
	assert_bool(src.contains("grad *= min(1.0, 1.2 / max(tilt, 0.0001));")).override_failure_message("the bend is not limited").is_true()   # no pinprick specular on mortar edges
	assert_bool(src.contains("dFdx(h)") and src.contains("dFdy(h)")).is_true()   # the gradient of the height, not a tangent-space map


func test_the_patterns_report_their_height_and_fade_it_with_the_pixel_footprint() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	for fn in ["vec3 stone(", "vec3 cobble("]:
		var head := src.substr(src.find(fn), 160)
		assert_bool(head.contains("out float rel")).override_failure_message("%s does not report a height" % fn).is_true()
	assert_bool(src.contains("rel = mix(0.5, mix(0.34,")).is_true()   # a sett that is too fine for the pixel is flat again (no shimmer)
	assert_bool(src.contains("rel = mix(0.5, edge *")).is_true()
	# the ground is bumped: cobbles, earth, boards, flagstones each set a depth
	for needle in ["depth_in = 0.06;", "depth_in = 0.05;", "depth_in = 0.02;", "depth_in = 0.03;"]:
		assert_bool(src.contains(needle)).override_failure_message("no relief depth `%s`" % needle).is_true()


func test_roughness_follows_the_material_worn_crowns_matt_joints() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("rough = mix(0.85, 0.65, smoothstep(0.3, 0.7, crown));")).is_true()   # (target C, train 2) a dirty joint matt 0.85, a worn crown 0.65 (the grit map's wet makes damp joints shine)
	assert_bool(src.contains("rough = 0.95;")).is_true()   # packed earth


## R2b: walls and roofs. Stone courses recess their mortar, plaster has a trowel's waviness with the frame timbers proud of it and windows as recesses, tile rows are steps;
## roughness per material (plaster 0.95, stone 0.85, timber 0.8, tile 0.7).
func test_walls_and_roofs_have_relief_and_the_materials_their_roughness() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.substr(src.find("vec3 timber("), 160).contains("out float rel")).is_true()
	assert_bool(src.contains("rel = mix(rel, 0.05, max(inside, hole * (1.0 - members)));")).override_failure_message("a window is not a recess").is_true()
	assert_bool(src.contains("rel = mix(0.5, fract(p.y / TILE_H) *")).override_failure_message("tile rows are not steps").is_true()
	assert_bool(src.contains("rough = 0.7;")).is_true()   # tile
	assert_bool(src.contains("rough = 0.85;")).is_true()   # stone
	assert_bool(src.contains("rough = mix(0.95, 0.8, step(0.8, rel));")).is_true()   # plaster 0.95, timber 0.8
	# every wall pattern that reports a height also sets a depth, so it is bumped
	var bumped := 0
	for needle in ["depth_in = 0.025;", "depth_in = 0.03;"]:
		bumped += src.count(needle)
	assert_int(bumped).is_greater_equal(5)


## R3 (edges and wear): the box size reaches the fragment; chips within 0.06 in of an edge, a damp band at the wall foot, soot under the eaves, a ragged top course on ruined tiers.
func test_the_box_size_reaches_the_fragment_and_the_edges_foot_eaves_and_top_course_wear() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("box_in = INSTANCE_CUSTOM.gba;")).is_true()
	assert_bool(src.contains("lpos = VERTEX * INSTANCE_CUSTOM.gba;")).is_true()
	assert_bool(src.contains("1.0 - smoothstep(0.0, 0.06, d_edge)")).override_failure_message("the chipped edge is not within 0.06 in").is_true()
	assert_bool(src.contains("1.0 - smoothstep(0.0, 0.3, p.y)")).override_failure_message("the wall foot band is not 0.3 in").is_true()
	assert_bool(src.contains("soot under the eaves")).is_true()
	assert_bool(src.contains("float d_top = e.y")).is_true()   # the ragged top course is measured from the box top (its size is in the instance data), the collider is untouched
	assert_bool(src.contains("k != 15 && k != 17")).is_true()   # the roof prism and the lantern are no boxes


## The earth's pebbles and tufts (lead, 21.11., after R3 macro): small, dark, irregular and sparse - never yellow coins.
func test_the_earth_has_sparse_dark_irregular_pebbles_and_no_yellow_coins() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("vec3(0.30, 0.38, 0.17)")).override_failure_message("the yellow-green coin tuft is back").is_false()
	assert_bool(src.contains("step(0.955, sp)")).is_true()   # a pebble in one cell of 22
	assert_bool(src.contains("1.0 + 1.4 * h21(ci + 5.0)")).is_true()   # stretched, so no round coin
	assert_bool(src.contains("vec3(0.13, 0.12, 0.11)")).is_true()   # a dark stone
	assert_bool(src.contains("+ 0.35 * pebble")).is_true()   # and it stands proud (relief)


## Standing water (the pools): a near-black peaty body, a trace of sheen, a duller surface that still shows the probe; never a flat teal slab (lead 21.11., twice) and never a black mirror
## (the first stills read that as a hole in the table).
func test_standing_water_is_a_deep_teal_that_lets_the_probe_win_over_the_sheen() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("alb = vec3(0.018, 0.028, 0.03) * mix(0.7, 1.3, swirl);")).is_true()
	assert_bool(src.contains("alb = vec3(0.03, 0.07, 0.085)")).override_failure_message("the teal body is back").is_false()
	assert_bool(src.contains("emis += vec3(0.002, 0.004, 0.005)")).override_failure_message("a trace of sheen only: the old sheen made a flat slab").is_true()
	assert_bool(src.contains("emis += vec3(0.02, 0.045, 0.07)")).override_failure_message("the old strong sheen is back").is_false()
	assert_bool(src.contains("spec = 0.45;")).override_failure_message("the water must stay specular to show the probe, but no mirror").is_true()
	assert_bool(src.contains("SPECULAR = spec;")).is_true()
	assert_bool(src.contains("rough = 0.16;")).is_true()


## The R3 chips are for solid boxes: the thin pool film and the ground skin have no chipped edge (the dashed pale line round the pond from above was exactly that rim).
func test_thin_films_get_no_chipped_edge() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("box_in.x > 0.0 && box_in.y > 0.5;")).override_failure_message("a thin box would get chips on its rim").is_true()


## R4a / R4b: the half-timber has a grammar and each lot its own plaster and timber.
func test_half_timber_has_a_grammar_braces_only_in_corner_bays_and_per_lot_tints() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("float corner = step(bay, 0.5) + step(2.5, bay);")).override_failure_message("braces must be limited to the corner bays").is_true()
	assert_bool(src.contains("float post = smoothstep(0.06, 0.04, min(lx, 1.0 - lx) * 0.75);")).is_true()   # a post every 0.75 in
	assert_bool(src.contains("vec3 plaster_of(float lot)") and src.contains("vec3 wood_of(float lot)")).is_true()
	assert_bool(src.contains("float members = max(post * (1.0 - inside),")).override_failure_message("a post runs through the opening").is_true()
	assert_bool(src.contains("step(0.9, hb) * step(0.0001, holes)")).override_failure_message("a hole is for ruins only").is_true()
	assert_bool(src.contains("float lot_h = ground_at(p.xz - wnrm.xz * 0.2).b;")).is_true()


## R4b (rest): four roofs by the lot's hash and a value ladder over the tops.
func test_roofs_have_five_tints_by_lot_and_the_tops_a_value_ladder() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("vec3 roof_of(float lot, vec3 clay)")).is_true()
	assert_bool(src.contains("float k = floor(fract(lot * 5.0) * 4.999);")).override_failure_message("five roofs (roofs lane 22.11.): two slates, a dark shingle, a mossy shingle, one dull clay").is_true()
	assert_bool(src.contains("tint = roof_of(ground_at(p.xz - wnrm.xz * 0.2).b, tint);")).override_failure_message("the roof must read the lot under it").is_true()
	assert_bool(src.contains("alb *= mix(0.88, 1.12, clamp(p.y / 9.0, 0.0, 1.0));")).override_failure_message("no value ladder on the tops").is_true()


## R5: a board's decay story - the fire side and the shade side come from the board's seed, are unit vectors a quarter turn apart, and the shader folds them by the half turn.
func test_the_decay_story_is_a_function_of_the_seed_and_the_shader_folds_it_by_the_half_turn() -> void:
	var a := BoardgenTownDressing.story(42)
	assert_object(BoardgenTownDressing.story(42)).is_equal(a)   # same seed, same story
	var seen := {}
	for seed in 20:
		var c := BoardgenTownDressing.story(seed)
		assert_float(Vector2(c.r, c.g).length()).is_equal_approx(1.0, 0.0001)
		assert_float(Vector2(c.b, c.a).length()).is_equal_approx(1.0, 0.0001)
		assert_float(Vector2(c.r, c.g).dot(Vector2(c.b, c.a))).is_equal_approx(0.0, 0.0001)   # the shade side is a quarter turn off the fire
		seen[snappedf(c.r, 0.1)] = true
	assert_int(seen.size()).override_failure_message("every board tells the same story").is_greater(4)
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("vec2 q = (p.z >= 0.0 ? -p.xz : p.xz) + vec2(0.0, 12.0);")).override_failure_message("the story must fold by the half turn: one half may not burn more than the other").is_true()
	assert_bool(src.contains("* (k == 13 ? 0.35 : 1.0);")).override_failure_message("an intact house burns less than a ruin").is_true()
	assert_bool(src.contains("float lost = smoothstep(0.62, 0.7,")).override_failure_message("no missing tiles").is_true()


## R6: a ruined tier's top is a broken floor in the edge strip only, and only at the lot's outer edge: the middle stays solid; stone tops are cracked with weeds in the joints.
func test_ruined_tops_break_only_in_the_outer_edge_strip() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("float strip = outer * (1.0 - smoothstep(0.1, 0.75, ed));")).override_failure_message("the broken floor must stay inside the 0.75 in strip").is_true()
	assert_bool(src.contains("float outer = step(0.004, abs(ground_at(xz).b - ground_at(xz + to_edge * (ed + 0.3)).b));")).override_failure_message("an edge inside a lot must not break").is_true()
	assert_bool(src.contains("float lost = step(1.0 - 0.7 * strip,")).override_failure_message("the loss must fade to nothing at the strip's inner line").is_true()
	assert_bool(src.contains("float fh = h21(fc + seed + 77.0);")).override_failure_message("no cracked flags").is_true()   # (21.11.: one straight fracture per broken flag, no curly noise isolines)
	assert_bool(src.contains("abs(vnoise(xz * 1.6 + seed * 2.0) - 0.5)")).override_failure_message("the curly scribble cracks are back").is_false()


## Lead 21.11. (readability gate): the ground the models stand on - streets, packed earth, garden plots, the decks of yards and tier floors - sits a step below the models' own values.
func test_the_ground_the_models_stand_on_sits_below_the_models() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("cobble(xz, seed, grit_street_tint(tint * vec3(0.96, 1.0, 1.08) * GROUND_COBBLE), run")).override_failure_message("the street's road tint (target C train 2: neutral-cool; the grit map keeps only its luminance)").is_true()
	assert_bool(src.contains("alb = tint * GROUND_EARTH * mix(0.78, 1.15, fbm(xz * 1.6 + seed));")).is_true()
	# maintainer 21.11. "too dark": a floor under the ground (no near-black earth or road), and still a step below the models
	for name: String in ["GROUND_COBBLE", "GROUND_EARTH"]:
		var at := src.find("const float %s = " % name)
		assert_int(at).is_greater(-1)
		var v := float(src.substr(at + ("const float %s = " % name).length(), 6).get_slice(";", 0))
		# (target C train 2: GROUND_COBBLE 0.70 - the slate setts are darker per unit and the lamp pools shrank; the street renders at luma 0.225, below the old warm road's 0.28,
		# and the readability gate stays green. The bound guards the constant, the gate guards the picture.)
		assert_float(v).override_failure_message("%s %f: the ground must sit between near-black and the models" % [name, v]).is_between(0.4, 0.72)
	assert_bool(src.contains("alb = tint * 0.55 * mix(0.6, 1.25, fbm(xz * 2.4 + seed))")).override_failure_message("garden plots must stay dark").is_true()
	assert_bool(src.contains("			alb *= 0.5;   // the decks the models stand on")).override_failure_message("the decks must stay dark").is_true()
	# (lane townC4) the decks weather to silver-grey (the brown boards were the play camera's largest warm area) and stay below the models: at most a 15 % lift
	assert_bool(src.contains("alb = mix(vec3(dot(alb, vec3(0.3, 0.55, 0.15))), alb, DECK_KEEP_HUE) * DECK_LIFT;")).override_failure_message("the decks keep only part of their warm hue").is_true()
	for name: String in ["DECK_KEEP_HUE", "DECK_LIFT"]:
		var at := src.find("const float %s = " % name)
		assert_int(at).is_greater(-1)
		var v := float(src.substr(at + ("const float %s = " % name).length(), 6).get_slice(";", 0))
		assert_float(v).override_failure_message("%s %f" % [name, v]).is_between(0.0, 0.6 if name == "DECK_KEEP_HUE" else 1.15)
