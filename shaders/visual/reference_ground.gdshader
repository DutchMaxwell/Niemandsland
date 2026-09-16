shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/visual/reference_ground.gdshaderinc"
uniform bool clip_base = false;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 ground_xz;
void vertex() { ground_xz = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz; }
void fragment() {
 if (clip_base && length(UV) > 1.0) { discard; }
 ALBEDO = ground_sample(ground_xz);
 ROUGHNESS = 0.94;
 METALLIC = 0.0;
 NORMAL_MAP = texture(detail_normal, ground_xz * 18.0).xyz;
 NORMAL_MAP_DEPTH = 0.16;
}
