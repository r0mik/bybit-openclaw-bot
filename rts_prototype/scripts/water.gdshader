shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled;
// Lake surface: two scrolling normal maps, fresnel tint, sharp sun highlights.

uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 deep_color : source_color = vec4(0.02, 0.1, 0.14, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.12, 0.36, 0.38, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.06;
	vec3 n1 = texture(ripples, uv + vec2(TIME * 0.012, TIME * 0.007)).rgb;
	vec3 n2 = texture(ripples, uv * 1.9 + vec2(-TIME * 0.016, TIME * 0.011)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.7;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float wave = n1.r * n2.g;
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, 0.25 + 0.5 * fresnel + 0.25 * wave);
	ROUGHNESS = 0.06;
	METALLIC = 0.1;
	SPECULAR = 0.9;
	ALPHA = 0.8;
}
