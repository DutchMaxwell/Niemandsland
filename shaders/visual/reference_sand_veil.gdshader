shader_type spatial;
// Local terrain-following ribbons: lit moving grains, soft crosswind edges and
// staggered gusts. No board-wide overlay or independently sliding ground colour.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, diffuse_burley;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float time = 0.0;
uniform float opacity = 0.52;
varying vec2 world_xz;

float sand_hash(vec2 p) {
	p = fract(p * vec2(123.34,345.45));
	p += dot(p,p + 34.345);
	return fract(p.x * p.y);
}
float sand_noise(vec2 p) {
	vec2 i = floor(p),f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(sand_hash(i),sand_hash(i+vec2(1,0)),f.x),
		mix(sand_hash(i+vec2(0,1)),sand_hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	world_xz = (MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
}
void fragment() {
	float seed = COLOR.r;
	float cycle = fract(time*(0.13+COLOR.g*0.045)+seed);
	float head = cycle*1.6-0.30;
	float envelope = 1.0-smoothstep(0.03,0.28,abs(UV.x-head));
	float ends = smoothstep(0.0,0.15,UV.x)*(1.0-smoothstep(0.75,1.0,UV.x));
	float across = pow(max(0.0,1.0-abs(UV.y*2.0-1.0)),1.4);
	vec2 flow = vec2(UV.x*17.0-time*(3.0+COLOR.b),UV.y*9.0+seed*31.0);
	float filaments = smoothstep(0.24,0.80,sand_noise(flow));
	float grains = sand_noise(flow*vec2(3.0,1.3)+13.0);
	float density = envelope*ends*across*(0.30+filaments*0.70)*(0.70+grains*0.30);
	vec2 uv = 1.0-abs(mod(world_xz*5.0,2.0)-1.0);
	ALBEDO = texture(sand_tex,uv).rgb*vec3(1.12,0.96,0.72);
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
	ALPHA = density*opacity;
}
