extends SceneTree
## Monta o atlas de bandeiras (fase 3.6): uma bandeira por país do jogo, num PNG só, com o
## índice em JSON. Fonte: flag-icons (MIT, https://github.com/lipis/flag-icons), versão 4x3
## em SVG. O Godot desenha cada SVG (Image.load_svg_from_buffer) e reduz para o quadrinho.
##
## Os países vêm de server/data/naturalearth/paises.geojson (CODE = A3 do jogo, A2 = ISO).
## Regra neutra (a mesma das fronteiras, padrão do Natural Earth): país sem código ISO de
## duas letras (áreas disputadas como Chipre do Norte, Somalilândia e o Glaciar de Siachen)
## ou sem bandeira no pacote ganha a bandeirinha neutra com o código dele. "CN-TW" (como o
## Natural Earth marca Taiwan) usa o código ISO 3166-1 do território, TW.
##
## Uso (de client/), com o pacote baixado e descompactado numa pasta qualquer:
##   godot --headless --path . -s tools/montar_bandeiras.gd -- --svg=/caminho/package/flags/4x3
## Gera assets/lipis/flag-icons/bandeiras.png e bandeiras.json (ver FlagAtlas).

const OUT_DIR := "res://assets/lipis/flag-icons/"
const COUNTRIES := "res://../server/data/naturalearth/paises.geojson"
## Quadrinho de cada bandeira (4:3) e a margem repetida em volta (para os mipmaps não
## misturarem bandeiras vizinhas).
const TILE := Vector2i(64, 48)
const PAD := 3
const COLS := 16
## Bandeira neutra: creme com uma faixa verde (a cor do Goblo) e o código.
const NEUTRAL_BG := Color("fff6e4")
const NEUTRAL_BAND := Color("7cc49a")
const NEUTRAL_INK := Color("5b4636")

## Letras 3 × 5 (linhas de cima para baixo, bits da esquerda para a direita).
const FONT := {
	"A": [2, 5, 7, 5, 5], "B": [6, 5, 6, 5, 6], "C": [3, 4, 4, 4, 3], "D": [6, 5, 5, 5, 6],
	"E": [7, 4, 6, 4, 7], "F": [7, 4, 6, 4, 4], "G": [3, 4, 5, 5, 3], "H": [5, 5, 7, 5, 5],
	"I": [7, 2, 2, 2, 7], "J": [1, 1, 1, 5, 2], "K": [5, 5, 6, 5, 5], "L": [4, 4, 4, 4, 7],
	"M": [5, 7, 7, 5, 5], "N": [6, 5, 5, 5, 5], "O": [2, 5, 5, 5, 2], "P": [6, 5, 6, 4, 4],
	"Q": [2, 5, 5, 6, 3], "R": [6, 5, 6, 5, 5], "S": [3, 4, 2, 1, 6], "T": [7, 2, 2, 2, 2],
	"U": [5, 5, 5, 5, 7], "V": [5, 5, 5, 5, 2], "W": [5, 5, 7, 7, 5], "X": [5, 5, 2, 5, 5],
	"Y": [5, 5, 2, 2, 2], "Z": [7, 1, 2, 4, 7], "?": [6, 1, 2, 0, 2],
}


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var svg_dir := str(args.get("svg", ""))
	if svg_dir.is_empty() or not DirAccess.dir_exists_absolute(svg_dir):
		print("bandeiras: passe --svg=PASTA com os SVG 4x3 do flag-icons")
		quit(1)
		return
	var geo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(COUNTRIES)))
	var countries: Array = []
	for f: Dictionary in geo["features"]:
		var p: Dictionary = f["properties"]
		countries.append([str(p["CODE"]), str(p.get("A2", ""))])
	countries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var rows := ceili(float(countries.size()) / COLS)
	var atlas := Image.create(TILE.x * COLS, TILE.y * rows, false, Image.FORMAT_RGBA8)
	var index := {}
	var neutral: Array = []
	for i in countries.size():
		var code: String = countries[i][0]
		var a2: String = countries[i][1]
		if a2.contains("-"):
			a2 = a2.get_slice("-", 1)
		var flag := _svg_flag(svg_dir, a2)
		if flag == null:
			flag = _neutral_flag(code)
			neutral.append(code)
		_blit_padded(atlas, flag, Vector2i(i % COLS, i / COLS))
		index[code] = i
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	atlas.save_png(OUT_DIR + "bandeiras.png")
	var meta := {
		"source": "flag-icons 7.6.0 (MIT), https://github.com/lipis/flag-icons",
		"tile": [TILE.x, TILE.y], "pad": PAD, "cols": COLS, "rows": rows,
		"codes": index, "neutral": neutral,
	}
	var out := FileAccess.open(OUT_DIR + "bandeiras.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(meta, "\t", true))
	out.close()
	print("bandeiras: %d países, %d com a bandeira neutra (%s), atlas %d × %d" % [
		countries.size(), neutral.size(), ", ".join(neutral), atlas.get_width(), atlas.get_height()])
	quit(0)


## Bandeira do SVG no tamanho do quadrinho sem a margem (null se não houver).
func _svg_flag(dir: String, a2: String) -> Image:
	if a2.length() != 2:
		return null
	var path := dir.path_join(a2.to_lower() + ".svg")
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	var inner := TILE - Vector2i(PAD * 2, PAD * 2)
	# Desenha com folga (4×) e reduz: bordas mais limpas que desenhar direto pequeno.
	if img.load_svg_from_buffer(FileAccess.get_file_as_bytes(path), 4.0 * inner.x / 640.0) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(inner.x, inner.y, Image.INTERPOLATE_LANCZOS)
	return img


## Bandeirinha neutra: creme, faixa verde na tralha e o código em letras de pixel.
func _neutral_flag(code: String) -> Image:
	var inner := TILE - Vector2i(PAD * 2, PAD * 2)
	var img := Image.create(inner.x, inner.y, false, Image.FORMAT_RGBA8)
	img.fill(NEUTRAL_BG)
	img.fill_rect(Rect2i(0, 0, 10, inner.y), NEUTRAL_BAND)
	var scale := 3
	var text := code.substr(0, 3)
	var width := text.length() * 4 * scale - scale
	var x0 := 10 + (inner.x - 10 - width) / 2
	var y0 := (inner.y - 5 * scale) / 2
	for k in text.length():
		var glyph: Array = FONT.get(text[k], FONT["?"])
		for row in 5:
			for col in 3:
				if int(glyph[row]) & (4 >> col):
					img.fill_rect(Rect2i(x0 + (k * 4 + col) * scale, y0 + row * scale, scale, scale), NEUTRAL_INK)
	return img


## Copia a bandeira no quadrinho (col, row) e repete as bordas na margem.
func _blit_padded(atlas: Image, flag: Image, cell: Vector2i) -> void:
	var origin := Vector2i(cell.x * TILE.x, cell.y * TILE.y)
	var w := flag.get_width()
	var h := flag.get_height()
	for y in TILE.y:
		for x in TILE.x:
			var sx := clampi(x - PAD, 0, w - 1)
			var sy := clampi(y - PAD, 0, h - 1)
			atlas.set_pixel(origin.x + x, origin.y + y, flag.get_pixel(sx, sy))
