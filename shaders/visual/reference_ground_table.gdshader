shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Game-table tier of the reference ground (TableBiomePresenter): the same surface with a derivative
// bump instead of three extra full-surface samples for the normal. See reference_ground_body.gdshaderinc.
#define TABLE_TIER
#include "res://shaders/visual/reference_ground_body.gdshaderinc"
