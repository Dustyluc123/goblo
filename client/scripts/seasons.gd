class_name Seasons
extends RefCounted
## Estações do ano reais (fase 2.5): a mesma conta de server/internal/game/season.go. A data
## vem do relógio do servidor (o "dia seguinte" do modo dev também vale) e o modo dev pode
## forçar uma data.
##
## A fase vai de 0 a 4 no hemisfério norte (0 = primavera, 1 = verão, 2 = outono,
## 3 = inverno); no sul, soma 2. Perto de cada virada, os pesos de duas estações se
## misturam por ±BLEND_DAYS dias, então nada muda de um dia para o outro: o chão muda de cor
## aos poucos e cada árvore troca de modelo num dia diferente (sorteio pelo id).

const TROPIC := 23.44
const BLEND_DAYS := 10.0
const YEAR := 365.2422
const STARTS := [78.5, 171.5, 264.5, 354.5]
const NAMES := ["spring", "summer", "autumn", "winter"]
const LABELS := {"spring": "Primavera", "summer": "Verão", "autumn": "Outono", "winter": "Inverno", "none": "Sem estação"}
## Largura da mistura em unidades de fase (~91 dias por estação).
const BLEND := BLEND_DAYS / (YEAR / 4.0)

## Data forçada pelo modo dev (segundos unix); 0 = a data real do servidor.
static var override_unix := 0.0

## Árvores que têm versões de outono e de neve no Ultimate Nature Pack.
static var _tree_re := RegEx.create_from_string("^(CommonTree|BirchTree|PineTree|Willow)_(\\d)$")
static var _rock_re := RegEx.create_from_string("^Rock(_Moss)?_(\\d)$")
static var _bush_re := RegEx.create_from_string("^Bush_(\\d)$")


## Dia do ano (0 = 1º de janeiro, com fração) do instante unix, em UTC.
static func day_of_year(unix: float) -> float:
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": d["year"], "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return (unix - jan1) / 86400.0


## Fase no hemisfério norte (0 a 4).
static func north_phase(unix: float) -> float:
	var doy := day_of_year(unix)
	for i in 4:
		var a: float = STARTS[i]
		var b: float = STARTS[(i + 1) % 4] + (YEAR if i == 3 else 0.0)
		var d := doy + (YEAR if i == 3 and doy < a else 0.0)
		if d >= a and d < b:
			return i + (d - a) / (b - a)
	return 3.0


## Fase na latitude (norte + 2 no sul).
static func phase_at(north: float, lat: float) -> float:
	return fposmod(north + (2.0 if lat < 0.0 else 0.0), 4.0)


## Estação na latitude: spring, summer, autumn, winter ou none (entre os trópicos).
static func season_at(unix: float, lat: float) -> String:
	if absf(lat) < TROPIC:
		return "none"
	return NAMES[int(phase_at(north_phase(unix), lat)) % 4]


## Peso (0 a 1) da estação `s` (0 a 3) na fase `p`, com a mistura nas viradas.
static func weight(p: float, s: int) -> float:
	var d := fposmod(p - s + 2.0, 4.0) - 2.0
	return smoothstep(-BLEND, BLEND, d) * (1.0 - smoothstep(1.0 - BLEND, 1.0 + BLEND, d))


## O bioma muda com as estações? (floresta, campo, tundra e montanha)
static func seasonal_biome(b: int) -> bool:
	return b in [WorldData.Biome.FOREST, WorldData.Biome.GRASSLAND, WorldData.Biome.TUNDRA, WorldData.Biome.MOUNTAIN]


## A célula tem estações? (bioma temperado ou frio, fora dos trópicos)
static func cell_has_seasons(world: WorldData, cell: int) -> bool:
	return seasonal_biome(world.biomes[cell]) and absf(world.lats[cell]) >= TROPIC


## Respostas de variant_model já calculadas (a expressão regular rodava por objeto, a cada
## pedaço montado).
static var _variant_cache := {}


## Versão do modelo na estação: "autumn" ou "snow" ("" = não existe, fica o normal).
static func variant_model(model: String, variant: String) -> String:
	var key := model + "|" + variant
	if not _variant_cache.has(key):
		_variant_cache[key] = _variant_model(model, variant)
	return _variant_cache[key]


static func _variant_model(model: String, variant: String) -> String:
	var m := _tree_re.search(model)
	if m:
		return "%s_%s_%s" % [m.get_string(1), "Autumn" if variant == "autumn" else "Snow", m.get_string(2)]
	if variant != "snow":
		return ""
	m = _rock_re.search(model)
	if m:
		return "Rock_Snow_" + m.get_string(2)
	m = _bush_re.search(model)
	if m:
		return "Bush_Snow_" + m.get_string(1)
	match model:
		"WoodLog", "WoodLog_Moss":
			return "WoodLog_Snow"
		"TreeStump", "TreeStump_Moss":
			return "TreeStump_Snow"
	return ""


## Qual versão (autumn, snow ou "") um objeto usa na fase `north` (norte). Cada objeto troca
## num dia diferente da transição (limiar pelo id), então a floresta muda aos poucos.
static func object_variant(world: WorldData, o: Dictionary, north: float) -> String:
	var cell := int(o["cell"])
	if not cell_has_seasons(world, cell):
		return ""
	var p := phase_at(north, world.lats[cell])
	var limit := 0.1 + 0.8 * BiomeStyle.hash01(int(o["id"]))
	if weight(p, 3) > limit:
		return "snow" if not variant_model(str(o["model"]), "snow").is_empty() else ""
	if weight(p, 2) > limit and str(o["kind"]) == "tree":
		return "autumn" if not variant_model(str(o["model"]), "autumn").is_empty() else ""
	return ""


## Modelos de estação que podem aparecer na fase `north` ou nos próximos dias (para
## pré-carregar): versões de outono e/ou de neve dos modelos dados, conforme a estação em
## algum dos hemisférios. Olhar uns dias à frente evita carregar modelo no meio do jogo
## quando a transição começa com o jogo aberto.
const LOOKAHEAD := 0.05  # ~4,5 dias

static func models_needed(models: Array, north: float) -> Array:
	var want := []
	for hemi in [north, fposmod(north + 2.0, 4.0), fposmod(north + LOOKAHEAD, 4.0), fposmod(north + 2.0 + LOOKAHEAD, 4.0)]:
		if weight(hemi, 2) > 0.0 and not want.has("autumn"):
			want.append("autumn")
		if weight(hemi, 3) > 0.0 and not want.has("snow"):
			want.append("snow")
	var out := []
	for m: String in models:
		for v: String in want:
			var vm := variant_model(m, v)
			if not vm.is_empty() and not out.has(vm):
				out.append(vm)
	return out
