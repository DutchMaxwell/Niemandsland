shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// The accepted reference ground (menu diorama, reference scene). The body lives in
// reference_ground_body.gdshaderinc, shared with the game-table tier (reference_ground_table.gdshader).
#include "res://shaders/visual/reference_ground_body.gdshaderinc"
