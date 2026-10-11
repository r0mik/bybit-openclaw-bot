shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Vegetation: colour from vertex colours (sRGB-ish), wind sway weighted by vertex alpha.

uniform float sway = 0.18;
uniform float speed = 1.6;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = COLOR.a;
	float t = TIME * speed + wp.x * 0.31 + wp.z * 0.17;
	VERTEX.x += sin(t) * sway * w;
	VERTEX.z += cos(t * 0.8 + 1.3) * sway * 0.6 * w;
	VERTEX.y += sin(t * 1.7) * sway * 0.25 * w;
}

void fragment() {
	ALBEDO = COLOR.rgb * COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
}
