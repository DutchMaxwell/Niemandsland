// The ruin town's ground fog: ONE transparent plane at the fog's top. Every pixel integrates an exponential height-fog density analytically
// along the view ray, from the plane down to the opaque surface behind it (read from the depth buffer): a ray from the play camera crosses
// only the thin layer (a light veil over the street; roofs, walls and figures stand above it), a grazing ray at eye level crosses a long
// path (the street dissolves with distance). The top wavers with a board-space noise; up to 12 lamp pools glow in it. Godot's volumetric
// fog cannot resolve a 0.5 in layer at miniature scale, hence the plane. Built and fed by scripts/boardgen_ground_fog.gd.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_y = 0.0;      // world y of the ground (m)
uniform float top_m = 0.014;       // mean fog top over the ground (m)
uniform float waver_m = 0.005;     // how far the top wavers (m)
uniform float scale_m = 0.0076;    // density falls by e every scale_m upwards (a soft top)
uniform float density = 30.0;      // extinction per metre at the ground
uniform vec4 fog_col : source_color = vec4(0.24, 0.26, 0.32, 1.0);
uniform vec3 lamps[12];            // world positions of the lamp glass
uniform int lamp_n = 0;
uniform vec4 lamp_col : source_color = vec4(1.0, 0.72, 0.45, 1.0);
uniform float lamp_r = 0.07;       // the pool's radius in the air (m): lamp height 2.55 in x tan(48 deg)
uniform float lamp_gain = 0.45;   // the fog's albedo inside a pool = lamp colour x this
uniform sampler2D clear_tex : filter_linear, repeat_disable;   // 1 = no fog: round every model's base (BoardgenGroundFog)
uniform vec2 board_center = vec2(0.0);   // world xz of the board's centre (m)
uniform vec2 board_size = vec2(1.0);     // the board's size (m): clear_tex covers it

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	vec3 s = (INV_VIEW_MATRIX * vec4(v.xyz, 1.0)).xyz;            // the opaque surface behind this pixel
	vec3 e = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;           // this pixel on the plane
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 a = e;
	vec3 b = s;
	if (cam.y < e.y) {   // a camera inside the layer: the ray starts at the camera
		a = cam;
	}
	float n = texture(noise_tex, a.xz * 7.0 + 0.27).r * 0.65 + texture(noise_tex, a.xz * 23.0 + 0.61).r * 0.35;
	float top = ground_y + top_m + (n - 0.5) * 2.0 * waver_m;
	float ya = a.y;
	float yb = b.y;
	float len_ab = length(b - a);
	if (ya > top) {
		if (yb >= top) {
			discard;
		}
		len_ab *= (top - yb) / max(ya - yb, 1e-5);
		ya = top;
	}
	float ha = max(ya - ground_y, 0.0);
	float hb = max(yb - ground_y, 0.0);
	float dy = hb - ha;
	float integral;
	if (abs(dy) < 1e-5) {
		integral = density * len_ab * exp(-ha / scale_m);
	} else {
		integral = density * len_ab * scale_m * (exp(-ha / scale_m) - exp(-hb / scale_m)) / dy;
	}
	integral *= mix(0.35, 1.45, n);   // patchy: thicker and thinner banks, never a flat sheet
	float alpha = 1.0 - exp(-max(integral, 0.0));
	float glow = 0.0;
	for (int i = 0; i < lamp_n; i++) {
		// the pool of light in the air under a lamp: compact (no long tails, ten lamps must not add up to a carpet), widest at the ground
		float dl = length(b.xz - lamps[i].xz);   // looked up where the ray ENDS: the fog in front of a lit pool is lit by that pool (a grazing ray's middle is far from it)
		float k = 1.0 - clamp(dl / lamp_r, 0.0, 1.0);
		glow += k * k;
	}
	ALBEDO = mix(fog_col.rgb, lamp_col.rgb * lamp_gain, min(glow, 1.0));   // inside a pool the fog takes the lamp's colour, outside it keeps the sky's
	// the veil stays off the models: no fog where the ray ends on a model or on the ground round its base (the gate reads that ring)
	alpha *= 1.0 - texture(clear_tex, (b.xz - board_center) / board_size + 0.5).r;
	ALPHA = clamp(alpha, 0.0, 0.97);
}
