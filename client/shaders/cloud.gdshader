// Nuvens low-poly: branco com sombreamento flat (derivadas) e transparência controlada
// pela câmera (somem perto do personagem).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, depth_draw_opaque;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = tint.rgb;
	ALPHA = opacity;
	ROUGHNESS = 1.0;
}
