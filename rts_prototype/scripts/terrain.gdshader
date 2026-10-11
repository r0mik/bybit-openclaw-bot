shader_type spatial;
render_mode cull_disabled;
// Ground: dirt base with grass / rock / sand layers from a CPU-baked splat map (scripts/terrain.gd).
// Rock uses triplanar mapping so cliffs are not stretched. Lake beds turn to dark wet mud.

uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask : filter_linear, repeat_enable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform vec2 splat_origin = vec2(-70.0);
uniform vec2 splat_size = vec2(540.0, 440.0);
uniform vec2 map_size = vec2(400.0, 300.0);
uniform float tile = 0.09;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz * tile;
	float n3 = texture(mask, wpos.xz * 0.03 + vec2(0.11, 0.53)).r;
	float n4 = texture(mask, wpos.xz * 0.11).r;
	vec4 sp = texture(splat, (wpos.xz - splat_origin) / splat_size);
	float grass = clamp(sp.r + (n4 - 0.5) * 0.6 * sp.r, 0.0, 1.0);
	float rock = sp.g;
	float sand = sp.b;

	vec3 c = texture(dirt_tex, uv).rgb;
	vec3 nm = texture(dirt_nrm, uv).rgb;
	c = mix(c, texture(grass_tex, uv * 1.4).rgb, grass);
	nm = mix(nm, texture(grass_nrm, uv * 1.4).rgb, grass);
	c = mix(c, texture(dirt_tex, uv * 0.7).rgb * vec3(1.45, 1.35, 1.1), sand);

	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	float rs = tile * 0.7;
	vec3 rc = texture(rock_tex, wpos.zy * rs).rgb * bw.x + texture(rock_tex, wpos.xz * rs).rgb * bw.y
			+ texture(rock_tex, wpos.xy * rs).rgb * bw.z;
	c = mix(c, rc * vec3(0.66, 0.6, 0.55) * (0.8 + 0.4 * n4), rock);
	nm = mix(nm, texture(rock_nrm, wpos.xz * rs).rgb, rock * bw.y);

	c *= 0.82 + 0.3 * n3;                                    // large-scale tonal variation
	c *= mix(1.0, 0.45, smoothstep(-0.2, -1.4, wpos.y));      // wet, dark lake bed
	vec2 outside = max(-wpos.xz, wpos.xz - map_size);
	c *= 1.0 - 0.25 * smoothstep(5.0, 40.0, max(outside.x, outside.y));

	ALBEDO = c;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = mix(mix(0.95, 0.8, rock), 0.55, smoothstep(-0.1, -0.6, wpos.y));
	SPECULAR = 0.3;
}
