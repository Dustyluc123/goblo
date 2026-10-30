class_name Session
extends Node
## Estado do jogador neste cliente: token, dados do /me, conteúdo do jogo (itens, receitas,
## casas) e a ferramenta na mão. O servidor é a fonte da verdade; aqui só guardamos a
## última resposta dele e avisamos a interface quando algo muda.

signal inventory_changed
signal me_changed
signal equipped_changed
## O saldo de moedas mudou (delta = quanto mudou).
signal coins_changed(delta: int)
## Os passaportes mudaram (comprou, ganhou no modo dev, zerou).
signal passports_changed

const PROFILE_DIR := "user://"

## Perfil do token (permite vários jogadores na mesma máquina: --profile=NOME).
var profile := "player"
var me: Dictionary = {}
var inventory: Array = []  # [{item, count}]
var slots_used := 0
var slots_max := 20
var items: Dictionary = {}  # id → item
var item_order: Array = []  # ids na ordem de items.json
var recipes: Array = []
var houses: Array = []
## Modelos que os objetos do servidor usam (para pré-carregar).
var object_models: Array = []
var tile_size := 0.5
var lot_tiles := 14
## O servidor está em modo dev (GOBLO_DEV=1)?
var dev := false
## Item de ferramenta na mão ("" = mão vazia).
var equipped := ""
## Saldo de moedas (o servidor é a fonte da verdade).
var coins := 0
## Nome da moeda (economy.json): {"singular", "plural"}.
var currency := {"singular": "moeda", "plural": "moedas"}
## Quanto a caixa de vendas paga por unidade de cada item.
var sell_prices := {}
## Espécies de animais (animals.json): id → {name, model, height, shy, walk, run, roam, leg, jump}.
var animal_species := {}
## Regras de fronteira e multiplayer (rules.json do servidor).
var rules := {}
## Páginas da Goblopédia (do /content, sem o progresso): [{id, name, kind, model, season}].
var pedia_catalog: Array = []
## Livro de passaporte (GET /passport): {"passports": [...], "stamps": [{country, name, first_at}]}.
var passport_book := {}


func token_path() -> String:
	return PROFILE_DIR + profile + ".cfg"


func load_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(token_path()) != OK:
		return ""
	return str(cfg.get_value("player", "token", ""))


func save_token(token: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "token", token)
	cfg.save(token_path())


func clear_token() -> void:
	DirAccess.remove_absolute(token_path())


func set_content(data: Dictionary) -> void:
	items.clear()
	item_order.clear()
	for it: Dictionary in data.get("items", []):
		items[it["id"]] = it
		item_order.append(it["id"])
	recipes = data.get("recipes", [])
	houses = data.get("houses", [])
	object_models = data.get("object_models", [])
	tile_size = float(data.get("tile_size", 0.5))
	lot_tiles = int(data.get("lot_tiles", 14))
	slots_max = int(data.get("inventory_slots", 20))
	if data.get("currency") is Dictionary:
		currency = data["currency"]
	sell_prices = data.get("sell_prices", {})
	animal_species = data.get("animals", {})
	rules = data.get("rules", {})
	pedia_catalog = data.get("pedia", [])


func set_me(data: Dictionary) -> void:
	me = data
	set_inventory(data.get("inventory", []), int(data.get("slots_used", 0)))
	set_coins(int(data.get("coins", coins)))
	me_changed.emit()


## Páginas da Goblopédia sem progresso (para abrir o álbum antes da resposta do servidor).
func pedia_entries() -> Array:
	return pedia_catalog.map(func(e: Dictionary) -> Dictionary:
		var c := e.duplicate()
		c["discovered"] = false
		return c)


func set_coins(n: int) -> void:
	if n == coins:
		return
	var delta := n - coins
	coins = n
	coins_changed.emit(delta)


## Passaportes que o jogador tem (o do país de residência primeiro).
func passports() -> Array:
	var list: Variant = me.get("passports")
	if list is Array and not (list as Array).is_empty():
		return list
	return [str(me.get("country", ""))]


func has_passport(code: String) -> bool:
	return passports().has(code)


## Guarda o livro de passaporte (resposta de /passport, /travel, /passport/buy…).
func set_passport_book(book: Dictionary) -> void:
	passport_book = book
	if book.has("passports"):
		var before := passports()
		me["passports"] = book["passports"]
		if passports() != before:
			passports_changed.emit()
	if book.has("coins"):
		set_coins(int(book["coins"]))


## Já tem o carimbo do país?
func stamped(code: String) -> bool:
	for st: Dictionary in passport_book.get("stamps", []):
		if str(st["country"]) == code:
			return true
	return false


## "1 moeda", "12 moedas".
func coins_text(n: int) -> String:
	return "%d %s" % [n, currency["singular"] if absi(n) == 1 else currency["plural"]]


func set_inventory(inv: Array, used: int) -> void:
	inventory = inv
	slots_used = used
	if not equipped.is_empty() and count(equipped) == 0:
		equip("")
	inventory_changed.emit()


func set_lot(lot: Dictionary) -> void:
	me["lot"] = lot
	me_changed.emit()


func lot() -> Dictionary:
	var l: Variant = me.get("lot")
	return l if l is Dictionary else {}


func count(item: String) -> int:
	for s: Dictionary in inventory:
		if s["item"] == item:
			return int(s["count"])
	return 0


func item_name(id: String) -> String:
	return str(items.get(id, {}).get("name", id))


func is_tool(id: String) -> bool:
	return str(items.get(id, {}).get("category", "")) == "tool"


func is_placeable(id: String) -> bool:
	return str(items.get(id, {}).get("category", "")) == "placeable"


## Ferramentas do inventário na ordem em que chegaram (a barra rápida).
func tools() -> Array:
	var out: Array = []
	for s: Dictionary in inventory:
		if is_tool(s["item"]):
			out.append(s["item"])
	return out


func equip(id: String) -> void:
	if equipped == id:
		return
	equipped = id
	equipped_changed.emit()


## Quantos itens de um custo o jogador tem ("#flower" soma todas as flores).
func have_for(key: String) -> int:
	if not key.begins_with("#"):
		return count(key)
	var tag := key.substr(1)
	var total := 0
	for s: Dictionary in inventory:
		if tag in items.get(s["item"], {}).get("tags", []):
			total += int(s["count"])
	return total


func cost_label(key: String) -> String:
	if key == "#flower":
		return "Flores (qualquer cor)"
	return item_name(key)


func can_afford(cost: Dictionary) -> bool:
	for k: String in cost:
		if have_for(k) < int(cost[k]):
			return false
	return true


func house_level(level: int) -> Dictionary:
	for h: Dictionary in houses:
		if int(h["level"]) == level:
			return h
	return {}
