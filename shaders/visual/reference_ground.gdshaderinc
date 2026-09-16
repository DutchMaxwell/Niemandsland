uniform sampler2D meadow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D woodland_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int forest_count = 0;
uniform vec4 forest_regions[16];
uniform float forest_angles[16];

// Integer hashing keeps neighboring cells identical across GPU optimizations.
float surface_hash(vec2 p) {
 uvec2 q = uvec2(ivec2(p));
 uint h = (q.x * 16777619u) ^ (q.y * 1103515245u);
 h = ((h >> 16u) ^ h) * 16777619u;
 h = (h >> 13u) ^ h;
 return float(h & 65535u) / 65535.0;
}
float surface_noise(vec2 p) {
 vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
 return mix(mix(surface_hash(i), surface_hash(i + vec2(1,0)), f.x),
 mix(surface_hash(i + vec2(0,1)), surface_hash(i + vec2(1,1)), f.x), f.y);
}
vec2 mirrored_uv(vec2 uv) { return 1.0 - abs(mod(uv, 2.0) - 1.0); }
vec3 tiled_surface(sampler2D tex, vec2 uv) {
 vec2 rotated = mat2(vec2(0.8,0.6),vec2(-0.6,0.8)) * uv * 0.71 + vec2(0.37,0.61);
 return mix(texture(tex,mirrored_uv(uv)).rgb,texture(tex,mirrored_uv(rotated)).rgb,0.45);
}
vec3 ground_sample(vec2 p) {
 vec2 uv = p * 18.0;
 float broad = surface_noise(p * 6.5) * 0.65 + surface_noise(p * 18.0) * 0.35;
 float meadow = smoothstep(0.31, 0.64, broad);
 vec3 earth = tiled_surface(earth_tex, uv);
 vec3 grass = tiled_surface(meadow_tex, uv);
 vec3 col = mix(earth * vec3(0.48,0.43,0.37), grass, meadow);
 float woodland = 0.0;
 for (int i = 0; i < forest_count; i++) {
  vec2 d = p - forest_regions[i].xy;
  float c = cos(forest_angles[i]), s = sin(forest_angles[i]);
  d = mat2(vec2(c,-s),vec2(s,c)) * d;
  float distance_to_edge = length(d / forest_regions[i].zw);
  woodland = max(woodland, 1.0 - smoothstep(0.78,1.18 + 0.10 * broad,distance_to_edge));
 }
 col = mix(col, tiled_surface(woodland_tex, uv * 1.1) * 0.87, woodland * 0.88);
 return col * 0.76;
}
