// The ground of a GENERATED BOARD under a model's base (ticket BASE-GROUND): a one-time top-down albedo bake of the board's own
// surfaces (scripts/boardgen_ground_bake.gd), pushed by Table.set_board_ground(). Shared by both base-top shaders. has_board false
// (no board on the table) leaves every base exactly as before.
uniform sampler2D board_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_board = false;
uniform vec4 board_rect = vec4(0.0);   // xy = world x / z of the bake's corner, zw = 1 / its size in metres
uniform float board_fill = 0.0;   // the town's emission floor on its open ground (grit_fill in ruintown_grit.gdshaderinc): pow(albedo, 2.2) x this

// True (and the board's albedo in `col`) where the base stands on the baked board.
bool board_ground(vec2 xz, out vec3 col) {
	col = vec3(0.0);
	vec2 buv = (xz - board_rect.xy) * board_rect.zw;
	if (!has_board || any(lessThan(buv, vec2(0.0))) || any(greaterThan(buv, vec2(1.0)))) {
		return false;
	}
	col = texture(board_albedo, buv).rgb;
	return true;
}
