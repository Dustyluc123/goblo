class_name FlagAtlas
extends RefCounted
## Atlas de bandeiras dos países (fase 3.6): um PNG com uma bandeira 4:3 por país e o índice
## em JSON, montados por tools/montar_bandeiras.gd a partir do flag-icons (MIT). Feito para
## ser reaproveitado (marcos da fronteira agora; a capa dos países visitados na fase 4.0).
##
## Países sem bandeira no pacote (áreas disputadas sem código ISO) têm a bandeirinha neutra
## com o código, e um código desconhecido cai nela também (índice NEUTRAL).

const TEXTURE := preload("res://assets/lipis/flag-icons/bandeiras.png")
const INDEX := "res://assets/lipis/flag-icons/bandeiras.json"
## Índice usado quando o país não está no atlas: o primeiro neutro.
const NEUTRAL := -1

static var _meta: Dictionary


static func meta() -> Dictionary:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	return _meta


static func texture() -> Texture2D:
	return TEXTURE


## Índice do país no atlas (o da primeira bandeira neutra, se não houver).
static func index_of(code: String) -> int:
	var codes: Dictionary = meta()["codes"]
	if codes.has(code):
		return int(codes[code])
	var neutral: Array = meta()["neutral"]
	return int(codes[neutral[0]]) if not neutral.is_empty() else 0


## Grade do atlas (colunas, linhas).
static func grid() -> Vector2i:
	return Vector2i(int(meta()["cols"]), int(meta()["rows"]))


## Retângulo da bandeira (sem a margem) em UV do atlas, para usar fora dos shaders.
static func uv_rect(code: String) -> Rect2:
	var m := meta()
	var g := grid()
	var i := index_of(code)
	var tile := Vector2(float(m["tile"][0]), float(m["tile"][1]))
	var pad := float(m["pad"])
	var size := Vector2(g.x * tile.x, g.y * tile.y)
	var origin := Vector2((i % g.x) * tile.x + pad, (i / g.x) * tile.y + pad)
	return Rect2(origin / size, (tile - Vector2(pad, pad) * 2.0) / size)


## Margem da bandeira dentro do quadrinho (fração), para os shaders.
static func inner_margin() -> Vector2:
	var m := meta()
	return Vector2(float(m["pad"]) / float(m["tile"][0]), float(m["pad"]) / float(m["tile"][1]))
