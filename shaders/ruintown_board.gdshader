shader_type spatial;
// Greybox of a generated ruin-town board (BoardgenGreybox, theme RuinTown): ONE material for every box of the board, a flat colour
// per surface kind from the theme palette, a thin line on every 3 in cell, a hatch on the yards (the level-0 rest of a half-collapsed house).
// The kind comes per instance (INSTANCE_CUSTOM.x, same contract as tiefwerk_board.gdshader). Procedural: no texture file.

uniform vec4 palette[19];   // display colours by kind index (BoardgenTheme.TOWN_KINDS)
uniform vec3 board_origin;   // world position of the board centre
uniform float cell_in = 3.0;

varying vec3 wpos;
varying vec3 wnrm;
varying flat float kind;

const float IN = 0.0254;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	kind = INSTANCE_CUSTOM.x;
}

void fragment() {
	int k = clamp(int(kind + 0.5), 0, 18);
	vec3 alb = palette[k].rgb;
	if (wnrm.y > 0.5) {   // a top face
		vec2 uv = (wpos.xz - board_origin.xz) / (IN * cell_in);   // in cells
		vec2 e = abs(fract(uv) - 0.5);
		alb *= mix(1.0, 0.72, smoothstep(0.47, 0.49, max(e.x, e.y)));
		if (k == 8) {
			alb *= mix(1.0, 0.8, step(0.5, fract((uv.x + uv.y) * 3.0)));
		}
	}
	ALBEDO = pow(alb, vec3(2.2));
	ROUGHNESS = 0.95;
}
