// The ground of a GENERATED BOARD under a model's base: a one-time top-down albedo bake of the board's own
// surfaces (scripts/boardgen_ground_bake.gd), pushed by Table.set_board_ground(). Shared by both base-top shaders. has_board false
// (no board on the table) leaves every base exactly as before.
uniform sampler2D board_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool has_board = false;
uniform vec4 board_rect = vec4(0.0);   // xy = world x / z of the bake's corner, zw = 1 / its size in metres

// The board's relief, approximated from the bake's own light and dark (sett tops bright, joints dark), as a view-space normal: screen-space
// derivatives of the luma on the base's flat top (as the table tier of reference_ground_body.gdshaderinc does). `pos` / `n` in view space.
const float BOARD_BUMP_M = 0.004;   // metres of relief per unit of luma
vec3 board_bump(vec3 col, vec3 pos, vec3 n) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	float h = dot(col, vec3(0.3, 0.5, 0.2));
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	return normalize(abs(det) * n - sign(det) * (dFdx(h) * r1 + dFdy(h) * r2) * BOARD_BUMP_M);
}

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
