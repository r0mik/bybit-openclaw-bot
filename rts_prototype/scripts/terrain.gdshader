shader_type spatial;
// Ground: dirt / grass / rock layers blended by world-space noise, with normal maps.
// Outside the playable area the ground turns into darker rock (map boundary).

uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask : filter_linear, repeat_enable;
uniform vec2 map_size = vec2(400.0, 300.0);
uniform float tile = 0.09;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	float n1 = texture(mask, wpos.xz * 0.0035).r;
	float n2 = texture(mask, wpos.xz * 0.009 + vec2(0.37, 0.71)).r;
	float n3 = texture(mask, wpos.xz * 0.03 + vec2(0.11, 0.53)).r;
	float grass = smoothstep(0.58, 0.78, n1 + (n3 - 0.5) * 0.25) * 0.85;
	vec2 outside = max(-wpos.xz, wpos.xz - map_size);
	float edge = max(outside.x, outside.y);
	float rock = max(smoothstep(0.76, 0.9, n2 + (n3 - 0.5) * 0.15) * 0.8, smoothstep(-5.0, 3.0, edge));

	vec3 c = mix(texture(dirt_tex, uv).rgb, texture(grass_tex, uv * 1.4).rgb, grass);
	vec3 nm = mix(texture(dirt_nrm, uv).rgb, texture(grass_nrm, uv * 1.4).rgb, grass);
	c = mix(c, texture(rock_tex, uv * 0.6).rgb, rock);
	nm = mix(nm, texture(rock_nrm, uv * 0.6).rgb, rock);
	c *= 0.8 + 0.3 * n3;                               // large-scale tonal variation
	c *= 1.0 - 0.5 * smoothstep(0.0, 14.0, edge);        // darken beyond the boundary

	ALBEDO = c;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = mix(0.95, 0.8, rock);
	SPECULAR = 0.3;
}
