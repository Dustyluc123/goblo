shader_type canvas_item;
// Tela levemente zonza (fome no mínimo, fase 4.0): ondulação bem suave da imagem e cantos
// um pouco escuros. amount vai de 0 a 1 (entra e sai devagar). Sem enjoar: pouca amplitude
// e devagar.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float amount = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME * 0.6;
	uv += amount * 0.0035 * vec2(sin(uv.y * 9.0 + t), cos(uv.x * 7.0 + t * 0.8));
	vec3 c = texture(screen, uv).rgb;
	float v = smoothstep(0.95, 0.35, distance(SCREEN_UV, vec2(0.5)));
	COLOR = vec4(mix(c, c * v, amount * 0.45), 1.0);
}
