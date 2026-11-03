shader_type canvas_item;
// Tela levemente zonza (fome no mínimo, fase 4.0; mais leve na 4.1, ADR 0052): cantos um
// pouco escuros que respiram devagar. Não lê a tela (nada de hint_screen_texture): uma
// cópia da imagem inteira a cada quadro custava caro na janela Retina. Só fica visível com
// amount > 0 (BodyGame esconde o retângulo no resto do tempo). amount vai de 0 a 1.

uniform float amount = 0.0;

void fragment() {
	float t = TIME * 0.6;
	vec2 d = SCREEN_UV - vec2(0.5);
	// Borda que ondula um tico (sem distorcer a imagem: só a máscara mexe).
	d += 0.012 * vec2(sin(SCREEN_UV.y * 9.0 + t), cos(SCREEN_UV.x * 7.0 + t * 0.8));
	float r = length(d) * (1.0 + 0.03 * sin(t * 1.7));
	float v = smoothstep(0.35, 0.95, r);
	COLOR = vec4(0.12, 0.08, 0.1, v * amount * 0.5);
}
