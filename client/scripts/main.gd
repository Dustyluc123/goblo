class_name GameMain
extends Node3D
## Ponto de entrada: baixa o mundo do servidor (com cache local), identifica o jogador
## (token guardado ou tela de primeiro acesso), monta o globo e solta o personagem no lote
## dele. Também é o "controlador" que as janelas chamam (fabricar, casa, modo dev).
##
## Argumentos opcionais (depois de "--" na linha de comando):
##   --server=URL        servidor (também: GOBLO_SERVER_URL ou goblo/server_url)
##   --profile=NOME      perfil do token (user://NOME.cfg); padrão "player"
##   --nickname=APELIDO  cria o jogador sem a tela de primeiro acesso (com --country=BRA)
##   --quality=Q         low, medium ou high (padrão: o salvo, ou medium)
##   --spawn=LAT,LON     nasce aqui em vez de no lote
##   --zoom=0..1         zoom inicial da câmera
##   --utc=HORA          fixa o horário UTC (ex.: 15.5) para testes e screenshots
##   --no-cache          ignora o mundo guardado em cache
##   --equip=ITEM        segura uma ferramenta (precisa ter no inventário)
##   --plaza=U,V         (com --ui=airport) põe o personagem no ponto (u, v) da praça
##   --smoke-test        anda alguns segundos, imprime onde o personagem está e fecha
##   --jump              (com --smoke-test) pula e mede a altura do pulo
##   --play-test         testa o ciclo: coleta, fabricação, decoração e casa (servidor dev)
##   --screenshot=ARQ    salva um PNG da tela e fecha (combine com --zoom e --walk)
##   --walk=SEGUNDOS     anda antes do teste/screenshot
##   --dir=DIREÇÃO       forward (padrão), back, left ou right
##   --run               segura Shift enquanto anda (corre)
##   --moving            tira o screenshot ainda andando (para ver a animação)
##   --route=LAT,LON     piloto automático até a coordenada; imprime o tempo e fecha
##   --perf-test=SEG     anda pela região medindo fps; imprime média e 1% piores e fecha
##   --tour              passeio automático (anda, afasta, gira, volta) e fecha
##   --fullscreen-test   entra em tela cheia antes do teste (combine com --perf-test)
##   --ui-scale=1.25     tamanho da interface só nesta execução
##   --window-size=WxH   abre em janela desse tamanho (em vez de maximizada)
##   --fps-limit=N       limite de fps só nesta execução (30, 60 ou 0 = sem limite)
##   --no-focus          janela de teste que não pega o foco (tools/sem_foco.sh usa)
##   --profile-scene     parado no lugar, mede GPU/CPU/draw calls ligando e desligando cada
##                       parte (sombras, árvores, grama, casas, chão, nuvens); com
##                       --neighbors=N cria N vizinhos falsos antes (servidor dev)
##   --off=A,B           (com --profile-scene) desliga desde o começo: nevoa, glow,
##                       tonemap, folhagem, sombras; mede só o total
##   --border-test       teleporta para pontos dos dois lados de fronteiras conhecidas,
##                       confere o país exato e a linha no chão, e anda até cruzar uma
##   --animal-test       acha animais, confere a posição contra o trajeto comum, faz
##                       carinho, dá frutinha, assusta um tímido correndo e mede o custo
##   --photo-test        câmera fotográfica: enquadra um animal e uma flor, mira com nome, fora do centro, escondido, longe
##                       na Goblopédia (gobolares só na primeira foto) e abre o álbum
##   --season-test       força cada estação (modo dev) e confere árvores, grama, chão, o
##                       nome no HUD, os dois hemisférios, os trópicos e a foto de outono
##   --travel-test       barreira da fronteira sem passaporte, carimbo ao entrar com ele,
##                       balcão do aeroporto, viagem de avião e livro do passaporte
##   --hitch-test        passeio pelos momentos suspeitos de travar (correr, afastar a câmera,
##                       Alemanha no outono, pampa com animais, modo foto, voo, casa, troca de
##                       estação) e imprime as travadas (> 25 ms) do registro (servidor dev)
##   --mp-test=a|b       dois jogos ao mesmo tempo (tools/dois_clientes.sh): cada um espera ver
##                       o outro (--peer=APELIDO), o b anda e fala, o a confere que viu o b
##                       andar e responde; os dois conferem o chat (servidor dev)
##   --cursor-test       voo, casa (H), teleporte do modo dev, menus, aviso da fronteira e
##                       plaquinha: depois de cada um, o cursor volta a ser capturado e o
##                       mouse gira a câmera sem clique (finge a janela na frente)
##   --dev-test          aperta os botões novos do painel dev (gobolares, passaportes, barreira,
##                       linhas de fronteira, animais, Goblopédia, voo de graça)
##   --npc-test          fase 3.5: apresentação do guia (tarefa e pular), lojista, loja,
##                       atendente e troca com um bot (servidor dev)
##   --camera-test       encosta em casas e na floresta, gira a câmera e confere que a
##                       distância não muda sozinha, que ela não vai para baixo do chão e
##                       que o que fica no caminho está transparente (servidor dev)

const DEFAULT_SERVER := "http://127.0.0.1:8080"
const RETRY_SECONDS := 3.0
const CACHE_DIR := "user://cache"
const CACHE_FILE := "user://cache/world.bin"
const CACHE_VERSION_FILE := "user://cache/world.version"

@export var spawn_lat := -23.55
@export var spawn_lon := -46.63

var world: WorldData
## Medições da última carga (ms e bytes), mostradas no console e no painel F2.
var load_stats := {}
var _args := {}
var _http: HTTPRequest
var _server_url := ""
var _cached_version := ""
var _request_started := 0
var _collision_timer := 0.0
var _ready_to_play := false
var _server_asked := false

var _api: Api
var _session: Session
var _data: ChunkData
var _neighborhood: Neighborhood
var _icons: ItemIcons
var _ui: GameUi
var _build: BuildMode
var _interaction: Interaction
var _occlusion: CameraOcclusion
var _border_lines: BorderLines
var _animals: Animals
var _photo: PhotoMode
var _pedia_art: PediaArt
var _season_fx: SeasonFx
var _airports: Airports
var _hitches: HitchLog
## Tempo real (fase 3): conexão, outros jogadores e o envio da posição.
var _net: Net
var _remotes: RemotePlayers
var _send_t := 0.0
var _last_sent := []
var _spawn_sent := false
## Voando (viagem de avião): o mundo não carrega pedaços pelo caminho.
var _flying := false
## Barreira do passaporte ligada (o modo dev pode desligar).
var barrier_on := true
var _barrier_msg_at := -10.0
var _airport_list: Array = []
## Fase da estação aplicada agora (no hemisfério norte; ver Seasons).
var _season_north := -1.0
var _season_timer := 0.0
var _season_busy := false
var _tracker: CountryTracker
## Marcador da casa no globo, visível na visão afastada.
var _home_marker: Sprite3D

## Fase 4.0: corpo, visual dos personagens, guarda-roupa e editor.
var body: BodyGame
var wardrobe: WardrobeUi
var look_editor: LookEditor
## Conta criada agora (primeiro acesso): o editor abre antes de entrar no mundo.
var _new_account := false
## Fase 4.5: cavernas (mapa separado) e lendas do folclore.
var cave: CaveGame
var legends: LegendsGame
var _cave_env := {}
var _looks := CharacterLook.new()
@onready var _terrain: Terrain = $Terrain
@onready var _vegetation: Vegetation = $Vegetation
@onready var _sun: DirectionalLight3D = $Sun
@onready var _day_night: DayNight = $DayNight
@onready var _clouds: Clouds = $Clouds
@onready var _highlight: MeshInstance3D = $Highlight
@onready var _player: Player = $Player
@onready var _camera: CameraRig = $Camera
@onready var _hud: Hud = $HUD


func _ready() -> void:
	InputSetup.ensure()
	_args = _parse_args()
	_server_url = _resolve_server_url()
	_camera.target = _player
	_player.camera = _camera
	_player.cell_changed.connect(_on_cell_changed)
	_player.rescued.connect(func(_cell: int) -> void:
		HitchLog.note("personagem abaixo do chão, posto de volta em cima")
		_terrain.update_collision(_player.global_position, -1)
		_camera.snap_behind_target())
	if _args.has("zoom"):
		_camera.set_zoom_now(float(_args["zoom"]))
	if _args.has("spawn"):
		var parts := str(_args["spawn"]).split(",")
		if parts.size() == 2:
			spawn_lat = float(parts[0])
			spawn_lon = float(parts[1])
	_cached_version = _read_cached_version()
	if _args.has("utc"):
		_day_night.set_utc_hour(float(_args["utc"]))
	if _args.has("quality"):
		Quality.set_quality(str(_args["quality"]), false)
	if _args.has("ui-scale"):
		Quality.set_ui_scale(float(_args["ui-scale"]), false)
	if _args.has("fullscreen-test"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	if _args.has("no-focus"):
		# Testes: janela comum (não maximizada), que não pega o foco nem vem para a frente.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1600, 900))
	if _args.has("window-size"):
		var wh := str(_args["window-size"]).split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	Quality.emitter.changed.connect(_apply_quality)
	Quality.emitter.ui_changed.connect(_apply_ui_scale)
	get_viewport().size_changed.connect(_apply_render_scale)
	_apply_quality()
	_apply_ui_scale()
	FpsLimit.apply()
	if _args.has("fps-limit"):
		FpsLimit.set_value(int(_args["fps-limit"]), false)

	_api = Api.new()
	_api.base_url = _server_url
	add_child(_api)
	_session = Session.new()
	_session.profile = str(_args.get("profile", "player"))
	add_child(_session)
	_data = ChunkData.new()
	add_child(_data)
	_neighborhood = Neighborhood.new()
	_neighborhood.name = "Neighborhood"
	add_child(_neighborhood)
	_icons = ItemIcons.new()
	add_child(_icons)
	_ui = GameUi.new()
	add_child(_ui)
	_camera.ui = _ui
	_build = BuildMode.new()
	add_child(_build)
	_interaction = Interaction.new()
	add_child(_interaction)
	_occlusion = CameraOcclusion.new()
	add_child(_occlusion)
	_border_lines = BorderLines.new()
	_border_lines.name = "BorderLines"
	add_child(_border_lines)
	_tracker = CountryTracker.new()
	add_child(_tracker)
	_animals = Animals.new()
	_animals.name = "Animals"
	add_child(_animals)
	_pedia_art = PediaArt.new()
	add_child(_pedia_art)
	_photo = PhotoMode.new()
	_photo.name = "PhotoMode"
	add_child(_photo)
	_season_fx = SeasonFx.new()
	_season_fx.name = "SeasonFx"
	add_child(_season_fx)
	_airports = Airports.new()
	_airports.name = "Airports"
	add_child(_airports)
	_session.equipped_changed.connect(_on_equipped)
	_hitches = HitchLog.new()
	_hitches.name = "HitchLog"
	_hitches.game = self
	add_child(_hitches)
	_net = Net.new()
	_net.name = "Net"
	add_child(_net)
	cave = CaveGame.new()
	cave.name = "Caves"
	add_child(cave)
	legends = LegendsGame.new()
	legends.name = "Legends"
	add_child(legends)
	_remotes = RemotePlayers.new()
	_remotes.name = "RemotePlayers"
	add_child(_remotes)

	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.request_completed.connect(_on_world_downloaded)
	add_child(_http)
	_request_world()


# --- Carga do mundo -----------------------------------------------------------------------

func _request_world() -> void:
	_hud.show_status(tr("Baixando o mundo de %s…") % _server_url)
	var headers := PackedStringArray()
	if not _cached_version.is_empty():
		headers.append('If-None-Match: "%s"' % _cached_version)
	_request_started = Time.get_ticks_msec()
	var err := _http.request(_server_url + "/world.bin", headers)
	if err != OK:
		_fail("Não consegui fazer a requisição (erro %d)." % err)


func _on_world_downloaded(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	load_stats["download_ms"] = Time.get_ticks_msec() - _request_started
	var data := PackedByteArray()
	if result == HTTPRequest.RESULT_SUCCESS and code == 304:
		data = FileAccess.get_file_as_bytes(CACHE_FILE)
		load_stats["source"] = "cache (versão %s)" % _cached_version
	elif result == HTTPRequest.RESULT_SUCCESS and code == 200:
		data = body
		load_stats["source"] = "download"
		load_stats["bytes"] = body.size()
		_write_cache(body, _header_version(headers))
	else:
		_fail("Sem resposta do servidor em %s (resultado %d, HTTP %d).\nEle está rodando? cd server && go run ./cmd/server" % [_server_url, result, code])
		return

	var t0 := Time.get_ticks_msec()
	world = WorldData.from_binary(data)
	if world == null:
		_clear_cache()
		_fail("O servidor mandou um mundo em formato inesperado.")
		return
	world.version = _cached_version
	load_stats["parse_ms"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_terrain.build(world)
	load_stats["mesh_ms"] = Time.get_ticks_msec() - t0
	_camera.set_planet_radius(world.radius)
	_camera.world = world
	_clouds.build(world.radius, Quality.current()["clouds"])
	_hud.build_minimap(world)

	_hud.show_status("Entrando no Goblo…")
	if not await _identify():
		return
	if not await _load_content():
		return
	_hud.show_status("Carregando árvores e casas…")
	var tm := Time.get_ticks_msec()
	await ModelLibrary.preload_all(_models_to_preload(), get_tree())
	await Animals.preload_scenes(_session.animal_species, get_tree())
	await RemotePlayers.preload_characters(_session.rules.get("characters", []), get_tree())
	CharacterLook.prepare(_session.body.get("look", {}).get("parts", []))
	load_stats["models_ms"] = Time.get_ticks_msec() - tm
	_setup_game()
	_hud.show_status("Preparando os gráficos…")
	tm = Time.get_ticks_msec()
	var warmed := await ShaderWarmup.run(self, _camera, _warm_extras())
	_neighborhood.prefill_arrays()
	load_stats["warmup_ms"] = Time.get_ticks_msec() - tm
	load_stats["warmup_items"] = warmed
	# Conta nova (fase 4.1): o editor de personagem é obrigatório antes de entrar no mundo.
	if _new_account:
		_hud.hide_status()
		if _args.get("ui", "") == "first-look":
			look_editor.open(true)
			await get_tree().create_timer(1.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(_args.get("screenshot", "user://editor.png")))
			get_tree().quit()
			return
		await look_editor.run_first()
		_hud.show_status("Preparando o seu lote…")

	var t1 := Time.get_ticks_msec()
	var spawn_cell: int
	var spawn_pos: Vector3
	if _args.has("spawn") or _session.lot().is_empty():
		spawn_cell = world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(spawn_lat, spawn_lon)))
		spawn_pos = world.centers[spawn_cell] * world.surface_radius(spawn_cell)
	else:
		spawn_pos = land_point(home_point())
		spawn_cell = world.find_cell(spawn_pos)
	_terrain.update_collision(spawn_pos, -1)
	_player.spawn(world, spawn_cell)
	_player.teleport(spawn_pos)
	_camera.snap_behind_target()
	await _data.load_now(spawn_pos, 60.0)
	_vegetation.load_now(_player.global_position)
	_neighborhood.flush()
	load_stats["content_ms"] = Time.get_ticks_msec() - t1
	_hud.hide_status()
	_ready_to_play = true
	# Espera a conexão em tempo real (até 6 s) para o servidor saber onde você está.
	var wait := 0.0
	while not _net.is_welcomed and wait < 6.0:
		await get_tree().process_frame
		wait += get_process_delta_time()
	_send_spawn()
	var win := DisplayServer.window_get_size()
	_hitches.start(tr("qualidade %s · janela %d × %d · limite %s · V-Sync %s · %s") % [Quality.label(), win.x, win.y,
		FpsLimit.label(), "ligado" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "desligado",
		"automação" if _is_automation() else "jogo"])
	# Cursor capturado durante o jogo (mover o mouse gira a câmera); nunca nas automações
	# nem nas janelas de teste, para não prender o mouse de quem está usando o Mac.
	_ui.mouse_capture = not _is_automation() and not _args.has("no-focus")
	var lot := _session.lot()
	print("Goblo: mundo %d células — %s, download %d ms, leitura %d ms, malhas %d ms, modelos %d ms, objetos %d ms (%d objetos, qualidade %s); jogador %s (%s), lote %s" % [
		world.cell_count(), load_stats["source"], load_stats["download_ms"], load_stats["parse_ms"], load_stats["mesh_ms"],
		load_stats["models_ms"], load_stats["content_ms"], _vegetation.instance_count, Quality.current_name(), _session.me.get("nickname", "?"),
		_session.me.get("country", "?"), str(int(lot.get("id", -1)))])
	if _args.has("equip"):
		_session.equip(str(_args["equip"]))
	_check_intro()
	_run_automation()


## Identifica o jogador: token guardado (GET /me) ou primeiro acesso (POST /players).
func _identify() -> bool:
	var token := _session.load_token()
	while true:
		if token.is_empty():
			break
		_api.token = token
		var r := await _api.request("GET", "/me")
		if r["ok"]:
			_session.set_me(r["data"])
			return true
		if r["status"] == 401:
			_session.clear_token()
			token = ""
			break
		if _is_automation():
			_fail("Servidor não respondeu ao /me: %s" % r["message"])
			return false
		_hud.show_status(tr("Sem resposta do servidor (%s).\nTentando de novo…") % r["message"])
		await get_tree().create_timer(RETRY_SECONDS).timeout

	var geo := await _api.request("GET", "/geo?locale=" + OS.get_locale().uri_encode())
	var detected := ""
	var source := "none"
	if geo["ok"]:
		detected = str(geo["data"]["country"])
		source = str(geo["data"]["source"])
	var created: Dictionary
	if (_is_automation() or _args.has("nickname")) and _args.get("ui", "") != "first":
		var nick := str(_args.get("nickname", "Robo %d" % randi_range(1000, 9999)))
		var country := str(_args.get("country", detected if not detected.is_empty() else "BRA"))
		var body := {"nickname": nick, "country": country}
		if _args.has("character"):
			body["character"] = str(_args["character"])
		var r := await _api.request("POST", "/players", body)
		if not r["ok"]:
			_fail("Não consegui criar o jogador: %s" % r["message"])
			return false
		created = r["data"]
		_new_account = _args.get("ui", "") == "first-look"  # captura do editor do 1º acesso
	elif _args.get("ui", "") == "first":
		# Screenshot da tela de primeiro acesso (testes): mostra, fotografa e fecha.
		_hud.hide_status()
		_hud.set_help_visible(false)
		_ui.show_first_access(world.countries, detected, source)
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(_args.get("screenshot", "user://primeiro.png")))
		get_tree().quit()
		return false
	else:
		_hud.hide_status()
		_hud.set_help_visible(false)
		var screen := _ui.show_first_access(world.countries, detected, source)
		while true:
			var sub: Array = await screen.submitted
			var r := await _api.request("POST", "/players", {"nickname": sub[0], "country": sub[1]})
			if r["ok"]:
				created = r["data"]
				_new_account = true
				break
			screen.show_error(str(r["message"]))
		_ui.close_first_access()
		_hud.show_status("Preparando o seu lote…")
	_session.save_token(str(created["token"]))
	_api.token = str(created["token"])
	_session.set_me(created["me"])
	return true


func _load_content() -> bool:
	var r := await _api.request("GET", "/content")
	if not r["ok"]:
		_fail("Não consegui baixar o conteúdo do jogo: %s" % r["message"])
		return false
	_session.set_content(r["data"])
	_session.dev = bool(r["data"].get("dev", false))
	var ap := await _api.request("GET", "/airports")
	_airport_list = ap["data"]["airports"] if ap["ok"] else []
	var pb := await _api.request("GET", "/passport")
	if pb["ok"]:
		_session.set_passport_book(pb["data"])
	return true


## Todos os modelos que podem aparecer: objetos do servidor, grama, itens e casas.
func _models_to_preload() -> Array:
	var out: Array = []
	out.append_array(_session.object_models)
	for c in ["red", "yellow", "white", "purple"]:
		out.append("flower:" + c)
	var decor: Variant = JSON.parse_string(FileAccess.get_file_as_string(Vegetation.DECOR_FILE))
	if decor is Dictionary:
		for list: Array in (decor["biomes"] as Dictionary).values():
			for e: Dictionary in list:
				out.append_array(e["models"])
	for id: String in _session.items:
		out.append(str(_session.items[id].get("model", "")))
	for h: Dictionary in _session.houses:
		out.append(str(h["scene"]))
	out.append_array(Airports.MODELS)
	# Versões de estação das árvores (outono, neve) que valem hoje em algum hemisfério.
	out.append_array(Seasons.models_needed(_session.object_models, Seasons.north_phase(season_now())))
	return out.filter(func(m: String) -> bool: return not m.is_empty())


func _setup_game() -> void:
	_data.setup(world, _api)
	_data.lot_size_units = _session.tile_size * _session.lot_tiles
	_data.radius = float(Quality.current()["big_radius"]) + 20.0
	_vegetation.setup(world, _data)
	_neighborhood.setup(world, _data, _session)
	_neighborhood.set_view_distance(float(Quality.current()["lot_radius"]))
	_icons.setup(_session.items)
	_ui.setup(self, _session, _icons, world.countries)
	_ui.inventory.place_requested.connect(func(item: String) -> void: _build.enter(item))
	_ui.inventory.use_requested.connect(use_item)
	# Fase 4.0: corpo (necessidades, fogueiras), visual dos personagens, guarda-roupa e editor.
	add_child(_looks)
	body = BodyGame.new()
	body.name = "Body"
	add_child(body)
	body.setup(self, _session, _api, _ui, _player, _data, _airports)
	wardrobe = _ui.add_window(WardrobeUi.new()) as WardrobeUi
	wardrobe.setup(self, _session)
	look_editor = _ui.add_window(LookEditor.new()) as LookEditor
	look_editor.setup(self, _session)
	_ui.settings.on_quiet = func() -> void:
		await body.set_quiet(not body.quiet())
		_ui.settings.show_quiet(body.quiet())
	_ui.settings.on_editor = open_look_editor
	_build.game = self
	_build.session = _session
	_build.data = _data
	_build.api = _api
	_build.ui = _ui
	_build.camera = _camera
	_build.player = _player
	_ui.on_build_close = _build.exit
	_border_lines.setup(world, _data)
	_border_lines.has_passport = func(code: String) -> bool: return _session.has_passport(code)
	# Comprou (ou perdeu) um passaporte: as fronteiras perto abrem (ou fecham) animando.
	_session.passports_changed.connect(func() -> void: _border_lines.refresh_state(true))
	_animals.setup(world, _data, _player, _session.animal_species)
	_tracker.world = world
	_tracker.data = _data
	_tracker.player = _player
	_tracker.country_changed.connect(_on_country_changed)
	_occlusion.camera = _camera
	_occlusion.player = _player
	_occlusion.data = _data
	_occlusion.vegetation = _vegetation
	_occlusion.neighborhood = _neighborhood
	_occlusion.airports = _airports
	_interaction.game = self
	_interaction.player = _player
	_interaction.data = _data
	_interaction.session = _session
	_interaction.api = _api
	_interaction.ui = _ui
	_interaction.vegetation = _vegetation
	_interaction.icons = _icons
	_interaction.neighborhood = _neighborhood
	_interaction.animals = _animals
	_interaction.airports = _airports
	_airports.setup(world, _data, _airport_list, _session.npc_roles)
	var dirs: Array = []
	for a: Dictionary in _airport_list:
		dirs.append(world.centers[int(a["cell"])])
		if not bool(a.get("small", false)):
			_vegetation.bare_cells[int(a["cell"])] = true
	_hud.set_airports(dirs)
	_player.border_guard = _border_guard
	_pedia_art.setup(_session.pedia_catalog, Animals._scenes, _session.animal_species)
	_ui.pedia.setup(self, _session, _pedia_art)
	_photo.game = self
	_photo.camera = _camera
	_photo.player = _player
	_photo.session = _session
	_photo.ui = _ui
	_photo.hud = _hud
	_photo.data = _data
	_photo.animals = _animals
	_photo.vegetation = _vegetation
	_photo.tracker = _tracker
	_photo.world = world
	_photo.api = _api
	_data.day_changed.connect(func() -> void:
		var r := await _api.request("GET", "/me")
		if r["ok"]:
			_session.set_me(r["data"])
		_ui.toast("Bom dia! Um novo dia começou no Goblo."))
	_session.me_changed.connect(func() -> void:
		var lot := _session.lot()
		if not lot.is_empty():
			_data.set_lot(lot)
		_update_home_marker())
	_update_home_marker()
	_hud.set_dev(_session.dev)
	apply_season(Seasons.north_phase(season_now()))
	_session.coins_changed.connect(func(delta: int) -> void: _hud.set_coins(_session.coins_text(_session.coins), delta))
	_hud.set_coins(_session.coins_text(_session.coins))
	_setup_net()
	_setup_dialogs()
	cave.setup(self, _session, _api, _ui, _player, _camera, world, _data)
	_net.cave_message.connect(cave.on_message)
	legends.setup(self, _session, _api, _player, world, _data, _net)


# --- Tempo real (fase 3) --------------------------------------------------------------------

func _setup_net() -> void:
	var character := str(_session.me.get("character", ""))
	if not character.is_empty() and character != _player.character:
		_player.set_character(character)
	_remotes.setup(_net, _camera)
	_ui.players.setup(self, _remotes)
	_ui.settings.on_character = set_character
	_ui.settings.show_character(_player.character)
	_ui.chat.max_chars = int(_session.rules.get("chat", {}).get("max_chars", 120))
	_net.body_received.connect(func(b: Dictionary) -> void:
		body.set_body(b)
		_ui.settings.show_quiet(body.quiet()))
	_net.look_changed.connect(func(id: int, lv: Dictionary) -> void:
		if id == _net.player_id:
			_player.set_look(lv))
	_net.fire_lit.connect(body.add_fire)
	_load_look_and_body()
	_ui.chat.sent.connect(func(text: String) -> void: _net.send_json({"t": "chat", "text": text}))
	_ui.emotes.picked.connect(emote)
	_net.welcomed.connect(func(_info: Dictionary) -> void:
		_spawn_sent = false
		if _ready_to_play:
			_send_spawn())
	_net.state_changed.connect(func(state: String) -> void:
		_hud.set_net_state(state)
		if state == "sem conexão" and _ready_to_play:
			_ui.toast("Sem conexão com o servidor. Tentando de novo…"))
	_net.corrected.connect(func(pos: Vector3, _reason: int) -> void:
		if not _flying:
			_player.correct(pos))
	_net.teleport_result.connect(func(why: String, ok: bool) -> void:
		if not ok:
			HitchLog.note("teleporte recusado pelo servidor: %s" % why)
			if why == "spawn":
				# O servidor não aceitou o lugar de nascimento: volta para casa.
				_teleport(home_point(), "home"))
	_net.chat_received.connect(_on_chat)
	_net.emote_received.connect(func(id: int, _e: String) -> void: pass)
	_net.act_received.connect(func(id: int, a: String, animal: int) -> void:
		if (a == "pet" or a == "feed") and id != _net.player_id:
			_animals.remote_pet(animal))
	_net.object_event.connect(func(d: Dictionary, by: int) -> void:
		if by != _net.player_id:
			_interaction.remote_action(int(d.get("id", -1)), str(d.get("action", ""))))
	_net.lot_event.connect(func(lot: Dictionary, by: int) -> void:
		if by != _net.player_id:
			_data.set_lot(lot))
	_net.stamped.connect(_on_stamped)
	_net.blocked_changed.connect(func(id: int, on: bool) -> void:
		if on:
			_ui.players.blocked[id] = true
		else:
			_ui.players.blocked.erase(id)
		_ui.toast("Jogador bloqueado: vocês não veem mais o chat nem os emotes um do outro." if on else "Jogador desbloqueado."))
	_net.info.connect(func(text: String) -> void: _ui.toast(text))
	_net.trade_requested.connect(func(from: int, nick: String) -> void:
		if _accept_trades:
			_ui.trade.show_request(from, nick)
		else:
			net_send({"t": "trade_answer", "from": from, "ok": false}))
	_net.trade_changed.connect(func(v: Dictionary) -> void:
		if not _ui.trade.visible:
			_ui.close_windows()
		_ui.trade.show_view(v))
	_net.trade_finished.connect(_ui.trade.on_done)
	_net.trade_closed.connect(_ui.trade.on_closed)
	_net.kicked.connect(func(reason: String) -> void:
		_hud.show_status(tr("%s\nFeche este jogo ou entre de novo.") % reason))
	_remotes.muted = _load_mutes()
	_net.start(_server_url, _api.token)


## Primeira posição no servidor (nascimento ou reconexão).
func _send_spawn() -> void:
	if _spawn_sent or not _net.is_welcomed:
		return
	_spawn_sent = true
	_net.teleport("spawn", _player.global_position)
	_last_sent = []


## Manda a posição send_hz vezes por segundo (só se mudou, ou 1 vez por segundo parado).
func _send_movement(delta: float) -> void:
	if not _net.is_welcomed or not _spawn_sent or _flying or not _player.visible:
		return
	_send_t -= delta
	if _send_t > 0.0:
		return
	_send_t = 1.0 / float(_net.send_hz)
	var pos := _player.global_position
	var yaw := Net.yaw_of(pos, _player.facing)
	var code := _player.anim_code()
	var flags := 0
	if _player.is_on_floor():
		flags |= Net.FLAG_ON_FLOOR
	if Input.is_action_pressed("run"):
		flags |= Net.FLAG_RUNNING
	if _player.noclip:
		flags |= Net.FLAG_NOCLIP
	if _photo.active:
		flags |= Net.FLAG_PHOTO
	var now := Time.get_ticks_msec()
	if not _last_sent.is_empty():
		var same: bool = (_last_sent[0] as Vector3).distance_to(pos) < 0.01 and absf(float(_last_sent[1]) - yaw) < 0.01 and _last_sent[2] == code
		if same and now - int(_last_sent[3]) < 1000:
			return
	_net.send_move(pos, yaw, code, flags)
	_last_sent = [pos, yaw, code, now]


func _on_chat(id: int, nick: String, text: String) -> void:
	var own := id == _net.player_id
	if not own and _remotes.muted.has(id):
		return
	_ui.chat.add_line(nick, text, own)
	if not own:
		_remotes.say(id, text)


## Carimbo a pé dado pelo servidor (ADR 0040).
func _on_stamped(res: Dictionary) -> void:
	if res.has("passport"):
		_session.set_passport_book(res["passport"])
	var reward := int(res.get("reward", 0))
	_ui.toast(tr("Carimbo novo no passaporte!  +%s") % _session.coins_text(reward))


## Emote do jogador: toca aqui e manda para quem está perto.
func emote(e: String) -> void:
	_player.play_emote(e)
	if e == "cheer":
		_season_fx.confetti(_player.global_position + _player.global_position.normalized() * 1.4)
	_net.send_json({"t": "emote", "e": e})


## Ação que os outros veem (animação de coletar, carinho, foto).
func net_act(a: String, animal := 0) -> void:
	_net.send_json({"t": "act", "a": a, "animal": animal})


## Silenciar (só neste computador, guardado no perfil).
func set_muted(id: int, on: bool) -> void:
	if on:
		_remotes.muted[id] = true
	else:
		_remotes.muted.erase(id)
	var cfg := ConfigFile.new()
	for k: int in _remotes.muted:
		cfg.set_value("silenciados", str(k), true)
	cfg.save("user://silenciados_%s.cfg" % _session.profile)
	_ui.toast("Jogador silenciado." if on else "Você volta a ouvir esse jogador.")


func _load_mutes() -> Dictionary:
	var out := {}
	var cfg := ConfigFile.new()
	if cfg.load("user://silenciados_%s.cfg" % _session.profile) == OK and cfg.has_section("silenciados"):
		for k: String in cfg.get_section_keys("silenciados"):
			out[int(k)] = true
	return out


func set_blocked(id: int, on: bool) -> void:
	_net.send_json({"t": "block", "id": id, "on": on})


# --- Troca entre jogadores (fase 3.5, ADR 0044) ---------------------------------------------

## Aceitar pedidos de troca (F6); desligado, o servidor recusa por você.
var _accept_trades := true


func net_send(msg: Dictionary) -> void:
	_net.send_json(msg)


func toast(text: String, item := "") -> void:
	_ui.toast(text, item)


## Propõe uma troca (lista J ou E perto do jogador). O servidor confere distância e bloqueio.
func propose_trade(id: int) -> void:
	if _ui.trade.trading():
		_ui.toast("Você já está numa troca.")
		return
	_net.send_json({"t": "trade_req", "to": id})


## Jogador remoto mais perto (até `reach`): id, ou -1.
func nearest_remote(pos: Vector3, reach: float) -> int:
	var best := -1
	var best_d := reach
	for id: int in _remotes.ids():
		var d := _remotes.position_of(id).distance_to(pos)
		if d < best_d:
			best_d = d
			best = id
	return best


func remote_position(id: int) -> Vector3:
	return _remotes.position_of(id)


func remote_nick(id: int) -> String:
	return str(_remotes.info(id).get("nick", "?"))


func set_accept_trades(on: bool) -> void:
	_accept_trades = on
	_net.send_json({"t": "trade_block", "on": not on})


## Troca o personagem (configurações): guarda no servidor e os outros veem.
func set_character(c: String) -> void:
	var r := await _api.request("POST", "/player/character", {"character": c})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	_session.set_me(r["data"])
	_player.set_character(c)
	_on_equipped()
	_net.send_json({"t": "char", "c": c})


# --- Corpo, roupas e visual (fase 4.0) -----------------------------------------------------

func _load_look_and_body() -> void:
	var r := await _api.request("GET", "/look")
	if r["ok"]:
		_player.set_look(r["data"])
	await body.load_body()
	_ui.settings.show_quiet(body.quiet())


## Aplica a resposta das ações de roupa e visual.
func _apply_wear(r: Dictionary) -> bool:
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return false
	var d: Dictionary = r["data"]
	_session.set_inventory(d["inventory"], int(d.get("slots_used", 0)))
	_player.set_look(d.get("look", {}))
	body.set_body(d.get("body", {}))
	if not str(d.get("message", "")).is_empty():
		_ui.toast(str(d["message"]))
	if wardrobe.visible:
		wardrobe.refresh()
	return true


func wear(item: String) -> bool:
	return _apply_wear(await _api.request("POST", "/wear", {"item": item}))


func unwear(slot: String) -> bool:
	return _apply_wear(await _api.request("POST", "/wear/remove", {"slot": slot}))


func dye(slot: String, paint: String) -> bool:
	return _apply_wear(await _api.request("POST", "/wear/dye", {"slot": slot, "paint": paint}))


## Bandeiras da capa, na ordem (fase 4.5). Vazia = automático (os últimos carimbos).
func set_cape(countries: Array) -> bool:
	return _apply_wear(await _api.request("POST", "/wear/cape", {"countries": countries}))


func save_look(look: Dictionary) -> bool:
	return _apply_wear(await _api.request("POST", "/look", look))


func open_look_editor() -> void:
	_ui.close_windows()
	look_editor.open()


## Modo dev (fase 4.0): necessidades, temperatura, bônus.
func dev_body(req: Dictionary) -> void:
	var r := await _dev("/dev/body", req, "")
	if r["ok"]:
		body.set_body(r["data"])
		_ui.dev.status(tr("Corpo: sede %d, conforto %d, fome %d · %.0f °C (%s)") % [int(r["data"]["thirst"]), int(r["data"]["comfort"]),
			int(r["data"]["hunger"]), float(r["data"]["felt"]), str(r["data"]["level"])])


func dev_body_kit() -> void:
	for pair: Array in [["mushroom", 4], ["herbs", 4], ["grain", 6], ["berries", 6], ["coconut", 2], ["campfire", 2], ["canteen", 1], ["branch", 4]]:
		await _dev("/dev/give", {"item": pair[0], "count": pair[1]}, "")
	var r := await _api.request("GET", "/me")
	if r["ok"]:
		_session.set_me(r["data"])
	_ui.dev.status("Ingredientes, fogueiras e cantil no bolso.")


func dev_wear() -> void:
	var r := await _dev("/dev/wear", {}, "Todas as roupas e tintas no bolso.")
	if r["ok"]:
		_session.set_me(r["data"])


## Põe uma flor decorativa de cada espécie do bioma em volta do personagem (só no cliente).
func dev_show_flowers() -> void:
	var biome := world.biome_names[int(world.biomes[_player.cell_id])]
	var list: Array = []
	for it: String in _session.item_order:
		var d: Dictionary = _session.items[it]
		if (d.get("tags", []) as Array).has("flower"):
			list.append(str(d.get("model", "")))
	var holder := Node3D.new()
	holder.name = "DevFlores"
	add_child(holder)
	var up := _player.global_position.normalized()
	var east := Vector3.UP.cross(up).normalized()
	var north := up.cross(east)
	for i in list.size():
		var lib := ModelLibrary.get_model(str(list[i]))
		if lib.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = lib["mesh"]
		var a := TAU * i / list.size()
		var p := _player.global_position + (east * cos(a) + north * sin(a)) * 2.5
		mi.transform = Transform3D(Basis(east, up, -north), p)
		holder.add_child(mi)
	get_tree().create_timer(60.0).timeout.connect(holder.queue_free)
	_ui.dev.status(tr("%d flores em volta de você por 1 minuto (bioma: %s).") % [list.size(), biome])


## Clique num item do bolso que se usa (comer, beber, vestir, tinta, fogueira, cantil).
func use_item(item: String) -> void:
	var it: Dictionary = _session.items.get(item, {})
	if it.get("wear") is Dictionary:
		await wear(item)
	elif (it.get("tags", []) as Array).has("paint"):
		_ui.close_windows()
		wardrobe.toggle()
	elif item == "campfire":
		# No próprio lote, coloca como decoração; fora dele, acende no chão por uns minutos.
		if not _session.lot().is_empty() and _in_own_lot_area(_session.lot(), _player.global_position):
			_ui.close_windows()
			_build.enter(item)
		else:
			_ui.close_windows()
			await body.light_fire()
	elif body.is_food(item):
		await body.consume(item)
	elif item in ["canteen", "canteen_half"]:
		_ui.toast("Chegue perto de uma fonte ou de um poço e aperte E para encher o cantil.")


## Modo dev: cria n bots perto (0 = tira todos).
func dev_bots(n: int) -> void:
	var r := await _dev("/dev/bots", {"count": n}, "")
	if r["ok"]:
		var d: Dictionary = r["data"]
		_ui.dev.status(tr("%d bots criados perto de você.") % int(d["created"]) if d.has("created") else "%d bots tirados." % int(d.get("removed", 0)))


## Modo dev: quem está conectado e os números da rede.
func dev_online() -> void:
	var r := await _api.request("GET", "/dev/online")
	if not r["ok"]:
		_ui.dev.status(str(r["message"]))
		return
	var lines := PackedStringArray()
	for o: Dictionary in r["data"].get("online", []):
		lines.append(tr("%s%s · %s · %s · vê %d") % [o["nickname"], " (bot)" if o["bot"] else "", o["country"],
			WorldData.format_lat_lon(float(o["lat"]), float(o["lon"])), int(o["visible"])])
	var st: Dictionary = r["data"].get("stats", {})
	if not st.is_empty():
		var secs := maxf(1.0, float(st["uptime_ms"]) / 1000.0)
		lines.insert(0, tr("%d conectados, %d bots · servidor mandou %.1f KB/s e recebeu %.1f KB/s em média") % [
			int(st["clients"]), int(st["bots"]), float(st["bytes_out"]) / 1024.0 / secs, float(st["bytes_in"]) / 1024.0 / secs])
	_ui.dev.show_online("\n".join(lines))


## Modo dev: simula atraso (ms; -1 = não muda) e perda (0 a 0,1; -1 = não muda).
func set_net_sim(latency: int, loss: float) -> void:
	if latency >= 0:
		_net.sim_latency_ms = latency
	if loss >= 0.0:
		_net.sim_loss = loss


func player_position() -> Vector3:
	return _player.global_position


## Casinha no mini mapa e marcador discreto no globo (visão afastada) onde fica o lote.
func _update_home_marker() -> void:
	if _session.lot().is_empty():
		_hud.set_home(Vector3.ZERO)
		if _home_marker:
			_home_marker.queue_free()
			_home_marker = null
		return
	var p := home_point()
	_hud.set_home(p.normalized())
	if _home_marker == null:
		_home_marker = Sprite3D.new()
		_home_marker.texture = HomeIcon.texture()
		_home_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_home_marker.fixed_size = true
		_home_marker.pixel_size = 0.0014
		_home_marker.shaded = false
		_home_marker.offset = Vector2(0, 32)  # a base da casinha fica no ponto
		_home_marker.visible = false
		add_child(_home_marker)
	_home_marker.position = p + p.normalized() * 2.0


func _fail(message: String) -> void:
	push_warning(message)
	if _is_automation():
		printerr("Goblo: " + message)
		get_tree().quit(1)
		return
	_hud.show_status(message + tr("\nTentando de novo em %d s…") % int(RETRY_SECONDS))
	if world == null and not _ui.server_setup.visible and not _server_asked:
		# Sem mundo: talvez o servidor seja outro (jogar com amigos).
		_server_asked = true
		_ui.server_setup.open(_server_url)
		_ui.server_setup.chosen.connect(func(url: String) -> void:
			_server_url = url
			_api.base_url = url
			_hud.show_status(tr("Conectando a %s…") % url))
	await get_tree().create_timer(RETRY_SECONDS).timeout
	if world == null:
		_request_world()
	else:
		get_tree().reload_current_scene()


func _read_cached_version() -> String:
	if _args.has("no-cache") or not FileAccess.file_exists(CACHE_FILE):
		return ""
	return FileAccess.get_file_as_string(CACHE_VERSION_FILE).strip_edges()


func _write_cache(body: PackedByteArray, version: String) -> void:
	if version.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if f:
		f.store_buffer(body)
		f.close()
		var v := FileAccess.open(CACHE_VERSION_FILE, FileAccess.WRITE)
		v.store_string(version)
		v.close()
	_cached_version = version


func _clear_cache() -> void:
	DirAccess.remove_absolute(CACHE_FILE)
	DirAccess.remove_absolute(CACHE_VERSION_FILE)
	_cached_version = ""


static func _header_version(headers: PackedStringArray) -> String:
	for h in headers:
		if h.to_lower().begins_with("x-world-version:"):
			return h.substr(h.find(":") + 1).strip_edges()
	return ""


# --- Jogo ---------------------------------------------------------------------------------

func _on_cell_changed(id: int) -> void:
	_hud.show_cell(world, id)
	_highlight.mesh = GlobeBuilder.highlight(world, id)


## Mudou o país embaixo do personagem (posição exata, ADR 0031). Com passaporte, a
## primeira visita ganha carimbo (e gobolares); andando, aparece a plaquinha de boas-vindas.
func _on_country_changed(code: String, walked: bool) -> void:
	_hud.set_country(code, _tracker.name_of(code))
	var subtitle := ""
	# Com o tempo real, quem carimba é o servidor (_on_stamped); sem ele, pede aqui.
	if _session.has_passport(code) and not _session.stamped(code) and not _flying and not _net.connected():
		var r := await _api.request("POST", "/passport/stamp", {"country": code})
		if r["ok"] and r["data"].get("stamp") != null:
			_session.set_passport_book(r["data"]["passport"])
			subtitle = tr("Carimbo novo no passaporte!  +%s") % _session.coins_text(int(r["data"]["reward"]))
			if not walked:
				_ui.toast(subtitle)
	if walked:
		_hud.welcome(_tracker.name_of(code), subtitle)
		_season_fx.confetti(_player.global_position + _player.global_position.normalized() * 1.2)
		_ui.restore_control()


## Coisas fora da ModelLibrary para o pré-aquecimento dos shaders: animais (com a
## animação tocando), corações, partículas das estações, linha de fronteira, o arco do voo e
## o destaque transparente.
func _warm_extras() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for sp: String in Animals._scenes:
		var a := (Animals._scenes[sp] as PackedScene).instantiate() as Node3D
		a.set_meta("warm_size", maxf(Player._model_height(a), 0.1))
		var aps := a.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var ap := aps[0] as AnimationPlayer
			if ap.has_animation("Idle"):
				ap.play("Idle")
		out.append(a)
	# Os personagens dos outros jogadores (um de cada já basta: mesmos materiais).
	for c: String in RemotePlayers._scenes.keys().slice(0, 2):
		var m := (RemotePlayers._scenes[c] as PackedScene).instantiate() as Node3D
		m.set_meta("warm_size", 1.0)
		out.append(m)
	var heart := Sprite3D.new()
	heart.texture = Animals._heart_texture()
	heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	heart.no_depth_test = true
	heart.set_meta("warm_size", 0.25)
	out.append(heart)
	# Fase 4.5: o brilho e a pedra das cavernas, e o disco do aviso do chefe.
	var glow := MeshInstance3D.new()
	glow.mesh = ModelLibrary.get_model("primitive:cave_crystal")["mesh"]
	glow.material_override = CaveWorld.glow_material()
	glow.set_meta("warm_size", 0.8)
	out.append(glow)
	var rock := MeshInstance3D.new()
	rock.mesh = BoxMesh.new()
	rock.material_override = CaveWorld.rock_material()
	rock.set_meta("warm_size", 1.0)
	out.append(rock)
	out.append_array(_season_fx.warm_nodes())
	out.append_array(_border_lines.warm_nodes())
	out.append_array(_airports.warm_nodes())
	# Arco do voo (contas num MultiMesh e o pontinho), sem a escala do globo.
	var arc := _flight_arc(Vector3(0, 0, 1), Vector3(0, 0.02, 1).normalized())
	for c in arc.get_children():
		arc.remove_child(c)
		(c as Node3D).position = Vector3.ZERO
		if c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				mm.set_instance_transform(i, Transform3D.IDENTITY)
		out.append(c)
	arc.free()
	# Destaque da célula (transparente), com os vértices trazidos para perto da origem.
	var hm := GlobeBuilder.highlight(world, 0)
	var arrays := hm.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var shift := world.centers[0] * world.surface_radius(0)
	for i in verts.size():
		verts[i] -= shift
	arrays[Mesh.ARRAY_VERTEX] = verts
	var glow_mesh := ArrayMesh.new()
	glow_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	glow_mesh.surface_set_material(0, hm.surface_get_material(0))
	var glow := MeshInstance3D.new()
	glow.mesh = glow_mesh
	out.append(glow)
	return out


## Onde o personagem está, para o registro de travadas.
func hitch_where() -> String:
	if world == null or _player.cell_id < 0:
		return "carregando"
	var ll := WorldData.vec_to_lat_lon(_player.global_position)
	return tr("%s · célula %d (%s) · %s · %d fps · qualidade %s") % [WorldData.format_lat_lon(ll.x, ll.y), _player.cell_id,
		world.biome_label(_player.cell_id), _tracker.current if _tracker else "?", Engine.get_frames_per_second(), Quality.label()]


## O que está acontecendo agora (estado, não eventos), para o registro de travadas.
func hitch_context() -> PackedStringArray:
	var out := PackedStringArray()
	if _flying:
		out.append("voando")
	if _camera.far_amount > 0.05:
		out.append(tr("câmera afastada %.0f%%") % (_camera.far_amount * 100.0))
	if _photo.active:
		out.append("modo foto")
	if _api.in_flight > 0:
		out.append(tr("%d pedidos ao servidor em andamento") % _api.in_flight)
	out.append(tr("%d animais carregados") % _animals.active_count)
	if not get_window().has_focus() and DisplayServer.get_name() != "headless":
		out.append("janela sem foco (o Mac desacelera)")
	return out


## Encostou numa fronteira fechada: a cortina faz uma onda a partir do ponto (no máximo
## uma a cada 0,8 s).
var _touch_at := -10.0


func _border_touch(pos: Vector3, target: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _touch_at < 0.8:
		return
	_touch_at = now
	var here := _tracker.exact_at(pos, _player.cell_id)
	_border_lines.touch(pos + pos.normalized() * 0.5, here, target)


## O ponto está no lote do jogador ou na margem em volta (Service.InLotArea no servidor)?
func _in_own_lot_area(lot: Dictionary, p: Vector3) -> bool:
	var f := _data.frame(int(lot["cell"]))
	if p.normalized().dot(f["center"]) < 0.99:
		return false
	var xy := WorldData.frame_coords(f, p)
	var x0 := float(lot["x0"])
	var y0 := float(lot["y0"])
	var size := _session.tile_size * _session.lot_tiles
	var m := float(_session.rules.get("borders", {}).get("lot_margin", 2.0))
	return xy.x >= x0 - m and xy.x <= x0 + size + m and xy.y >= y0 - m and xy.y <= y0 + size + m


## Nome de um país (com ou sem hexágono).
func country_name(code: String) -> String:
	return _tracker.name_of(code) if _tracker else code


## Barreira do passaporte (ADR 0035): devolve a direção para dentro do país proibido, ou
## ZERO se pode passar. Fica no cliente enquanto o servidor não sabe a posição do jogador.
func _border_guard(from: Vector3, probe: Vector3) -> Vector3:
	if not barrier_on or _player.noclip or _flying:
		return Vector3.ZERO
	var cell := world.find_cell(probe, _player.cell_id)
	var lot := _session.lot()
	if not lot.is_empty() and int(lot["cell"]) == cell:
		return Vector3.ZERO  # o hexágono de casa é sempre livre
	if not lot.is_empty() and _in_own_lot_area(lot, probe):
		return Vector3.ZERO  # lote e margem contam como o país do dono (ADR 0037)
	var target := _tracker.exact_at(probe, cell)
	if target.is_empty() or _session.has_passport(target):
		return Vector3.ZERO
	if _tracker.exact_at(from, _player.cell_id) == target:
		return Vector3.ZERO  # já está dentro (chegou por teleporte): anda livre
	var now := Time.get_ticks_msec() / 1000.0
	if now - _barrier_msg_at > 4.0:
		_barrier_msg_at = now
		_ui.toast(tr("Para entrar aqui, você precisa do passaporte deste país: %s. Ele pode ser comprado em qualquer aeroporto.") % country_name(target))
		_ui.restore_control()
	_border_touch(from, target)
	var bn := _data.borders.border_normal(from, _player.cell_id, world.surface_radius(_player.cell_id), target)
	if bn.is_empty() or (bn["normal"] as Vector3) == Vector3.ZERO:
		return (probe - from).normalized()
	# Perto da linha, a normal da borda; se ainda assim o passo atravessaria, segura tudo.
	var n: Vector3 = bn["normal"]
	return n if float(bn["dist"]) > 0.25 else (probe - from).normalized()


# --- Viagem ---------------------------------------------------------------------------------

## Compra a passagem (e o passaporte do destino, se `buy`) e voa até lá.
func travel(from_airport: Dictionary, quote: Dictionary, buy: bool) -> void:
	var r := await _api.request("POST", "/travel", {"from": from_airport.get("country", ""), "to": quote["country"], "buy_passport": buy})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	await _arrive(from_airport, r["data"])


## Compra só o passaporte. Devolve true se deu certo.
func buy_passport(code: String) -> bool:
	var r := await _api.request("POST", "/passport/buy", {"country": code})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return false
	_session.set_passport_book(r["data"]["passport"])
	_ui.toast(str(r["data"]["message"]))
	return true


func _arrive(from_airport: Dictionary, res: Dictionary) -> void:
	_session.set_passport_book(res["passport"])
	var dest: Dictionary = res["airport"]
	dest["cell"] = int(dest["cell"])
	var origin := from_airport
	if origin.is_empty():
		origin = {"lat": WorldData.vec_to_lat_lon(_player.global_position).x, "lon": WorldData.vec_to_lat_lon(_player.global_position).y}
	await _fly(origin, dest)
	var subtitle := str(dest["name"])
	if res.get("stamp") != null:
		subtitle += tr("\nCarimbo novo no passaporte!  +%s") % _session.coins_text(int(res["reward"]))
	_hud.welcome(country_name(str(dest["country"])), subtitle)
	_ui.restore_control(true)


## Voo: escurece um pouco, afasta a câmera até o globo, desenha um arco do aeroporto de
## origem ao de destino com um pontinho viajando (o dia e a noite do globo são os de
## agora) e aproxima de novo no destino.
func _fly(from_airport: Dictionary, dest: Dictionary) -> void:
	_ui.close_windows()
	_build.exit()
	_photo.exit()
	_flying = true
	var zoom_before := _camera.zoom
	var visual: Node3D = _player.get_node("Visual")
	_player.set_physics_process(false)
	_hud.fade(0.28, 0.6)
	_camera.zoom = 0.86
	await get_tree().create_timer(1.3).timeout
	visual.visible = false
	var a := WorldData.lat_lon_to_vec(float(from_airport["lat"]), float(from_airport["lon"]))
	var b := WorldData.lat_lon_to_vec(float(dest["lat"]), float(dest["lon"]))
	var arc := _flight_arc(a, b)
	add_child(arc)
	var dot: Node3D = arc.get_meta("dot")
	var angle := a.angle_to(b)
	var duration := clampf(2.5 + angle * 2.2, 2.5, 6.0)
	var t := 0.0
	var arc_at := func(k: float) -> Vector3:
		return a.slerp(b, k).normalized() * (world.radius + 18.0 + sin(k * PI) * angle * 70.0)
	while t < duration:
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, t / duration)
		var dir := a.slerp(b, k).normalized()
		dot.position = arc_at.call(k)
		# O avião olha para onde o arco vai (com o "em cima" para fora do globo).
		var ahead: Vector3 = (arc_at.call(minf(k + 0.01, 1.0)) as Vector3) - (arc_at.call(maxf(k - 0.01, 0.0)) as Vector3)
		if ahead.length() > 0.001:
			dot.basis = Basis.looking_at(ahead.normalized(), dir).scaled(Vector3.ONE * FLIGHT_PLANE_SCALE)
		_player.global_position = dir * (world.radius + 1.0)
		await get_tree().process_frame
	await _teleport(_airports.arrival_point(dest), "travel")
	_player.set_physics_process(false)
	arc.queue_free()
	_camera.zoom = zoom_before
	visual.visible = true
	await get_tree().create_timer(1.2).timeout
	_player.set_physics_process(true)
	_flying = false
	_hud.fade(0.0, 0.6)
	# Fim da animação: o cursor volta a ser do jogo na hora, sem precisar de clique.
	_ui.restore_control(true)


## Tamanho do avião no voo (o globo fica longe da câmera).
const FLIGHT_PLANE_SCALE := 16.0


## Arco pontilhado entre dois pontos do globo e o avião (meta "dot").
func _flight_arc(a: Vector3, b: Vector3) -> Node3D:
	var root := Node3D.new()
	var angle := a.angle_to(b)
	var n := maxi(8, int(angle * 60.0))
	var bead := SphereMesh.new()
	bead.radius = 2.2
	bead.height = 4.4
	bead.radial_segments = 8
	bead.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("fff3c4")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bead.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bead
	mm.instance_count = n + 1
	for i in n + 1:
		var k := float(i) / n
		var dir := a.slerp(b, k).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(), dir * (world.radius + 18.0 + sin(k * PI) * angle * 70.0)))
	var mmi := MultiMeshInstance3D.new()
	# Parado: sem interpolação de física (com ela, entrar na cena lê o MultiMesh de volta da
	# placa e espera o quadro inteiro; fase 4.2, ADR 0053).
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.multimesh = mm
	root.add_child(mmi)
	# O avião (o mesmo do aeroporto, maior).
	var dot := MeshInstance3D.new()
	dot.mesh = PlaneModel.flying_mesh()
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.scale = Vector3.ONE * FLIGHT_PLANE_SCALE
	root.add_child(dot)
	root.set_meta("dot", dot)
	return root


func _on_equipped() -> void:
	var id := _session.equipped
	if id.is_empty():
		_player.set_tool(null)
		return
	var lib := ModelLibrary.get_model(str(_session.items.get(id, {}).get("model", "")))
	_player.set_tool(lib.get("mesh"))
	_ui.toast(tr("Na mão: %s") % _session.item_name(id), id)


func _process(delta: float) -> void:
	if world == null or not _player.visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is SpinBox
	_player.input_blocked = typing or _ui.menu_open() or _photo.selfie()
	_bob_intro_arrow()
	# Com o diálogo aberto, o "pular" fica dentro da caixa.
	if _intro_skip:
		_intro_skip.visible = is_instance_valid(intro_guide) and not _ui.dialog.visible
	_hud.set_help_visible(not _ui.any_open())
	# A barra rápida some atrás das janelas (bolso, bancada, dev, configurações).
	_ui.hotbar.visible = not _ui.menu_open() and not _photo.active
	# Cada parte que roda a cada quadro anota no registro de travadas se passar de 2 ms
	# (fase 4.2: travadas sem anotação nenhuma ao andar).
	cave.update(delta)
	if cave.active:
		# Na caverna o globo está escondido: nada de pedaços, vegetação, céu ou estação.
		_send_movement(delta)
		return
	legends.update(delta)
	var t := Time.get_ticks_usec()
	_collision_timer -= delta
	if _collision_timer <= 0.0 and not _flying:
		_collision_timer = 0.25
		_terrain.update_collision(_player.global_position)
	t = _timed("colisão do chão (procura)", t)
	if not _flying:
		_data.update_focus(_player.global_position, delta)
	t = _timed("pedaços do servidor", t)
	_vegetation.update_focus(_player.global_position, _camera.far_amount, delta)
	t = _timed("vegetação", t)
	_airports.update(_player.global_position, _camera.far_amount, delta)
	t = _timed("aeroportos", t)
	_border_lines.update_view(_camera.far_amount)
	_animals.update_view(_camera.far_amount)
	_update_season(delta)
	t = _timed("fronteira, animais e estação", t)
	_neighborhood.daylight = _day_night.local_day
	_neighborhood.update_lights(_player.global_position, delta)
	t = _timed("luzes do bairro", t)
	_day_night.update(delta, _player.global_position.normalized(), _camera.far_amount)
	_clouds.update(delta, _camera.far_amount, maxf(_day_night.local_day, _camera.far_amount))
	_hud.show_time(_day_night.local_hours(world.lons[_player.cell_id]), _day_night.speed)
	_hud.update_navigation(_camera.global_basis, _player.global_position.normalized(), _day_night.sun_dir, _player.facing)
	t = _timed("céu, nuvens e HUD", t)
	if _home_marker:
		var far := _camera.far_amount
		_home_marker.visible = far > 0.25
		_home_marker.modulate.a = smoothstep(0.25, 0.6, far)
	_send_movement(delta)
	if _hud.perf_visible():
		_hud.show_perf(tr("%d fps · %.1f ms\n%d draw calls · %d mil triângulos\n%d objetos · %d lotes · %d animais · %d pedidos\nqualidade %s") % [
			Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			_vegetation.instance_count, _data.all_lots().size(), _animals.active_count, _api.in_flight, Quality.label()]
			+ tr("\nrede: %s · ping %d ms · ↓%d ↑%d pacotes/s · %d jogadores visíveis") % [_net.state, _net.ping_ms, _net.pps_in, _net.pps_out, _remotes.visible_count]
			+ "\n\n" + HitchLog.summary())
	if _highlight.mesh:
		var mat := _highlight.mesh.surface_get_material(0) as StandardMaterial3D
		mat.albedo_color.a = 0.22 + 0.08 * sin(Time.get_ticks_msec() / 300.0)
		_highlight.visible = _camera.far_amount < 0.5 and not _build.active


## Anota no registro de travadas o trecho que passou de 2 ms; devolve o tempo de agora.
func _timed(what: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	if now - since > 2000:
		HitchLog.note(what, (now - since) / 1000.0)
	return now


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_F2:
			_hud.toggle_perf()
		KEY_F3:
			time_faster()
		KEY_F4:
			time_real()
		KEY_F6:
			_ui.settings.toggle()
		KEY_F11:
			SettingsUi.toggle_fullscreen()
	if not _ready_to_play:
		return
	if key == KEY_C and not _ui.chat.is_open() and (not _ui.menu_open() or wardrobe.visible):
		var was_open := wardrobe.visible
		_ui.close_windows()
		if not was_open:
			wardrobe.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("dev_panel"):
		if _session.dev:
			_ui.dev.toggle()
		else:
			_ui.toast("Modo dev desligado. Rode o servidor com GOBLO_DEV=1.")
	elif event.is_action_pressed("ui_cancel"):
		if _ui.close_windows():
			get_viewport().set_input_as_handled()
		elif not _build.active:
			_ui.release_mouse()  # Esc sem menu: solta o cursor (clique na janela captura)
	elif _ui.first_access != null:
		return
	elif event.is_action_pressed("inventory"):
		_ui.craft.visible = false
		_ui.inventory.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build"):
		if not _build.active:
			_ui.close_windows()
			_build.enter()
	elif event.is_action_pressed("home"):
		go_home()
	elif event.is_action_pressed("passport"):
		var was_open := _ui.passport.visible
		_ui.close_windows()
		if not was_open:
			_ui.passport.toggle()
		get_viewport().set_input_as_handled()
	elif (key == KEY_ENTER or key == KEY_KP_ENTER) and not _ui.menu_open() and not _ui.chat.is_open():
		_ui.chat.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("emotes"):
		var was_open := _ui.emotes.visible
		_ui.close_windows()
		if not was_open:
			_ui.emotes.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("players"):
		var was_open := _ui.players.visible
		_ui.close_windows()
		if not was_open:
			_ui.players.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedia"):
		var was_open := _ui.pedia.visible
		_ui.close_windows()
		if not was_open:
			_ui.pedia.toggle()
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_5 and not _ui.menu_open():
		_ui.hotbar.press(key - KEY_1)


## Aplica quality: antisserrilhado e sombras (a vegetação se recarrega sozinha).
func _apply_quality() -> void:
	var q := Quality.current()
	get_viewport().msaa_3d = q["msaa"]
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q["fxaa"] else Viewport.SCREEN_SPACE_AA_DISABLED
	var splits := {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, 4: DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS}
	_sun.directional_shadow_mode = splits.get(int(q["shadow_splits"]), DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	get_viewport().mesh_lod_threshold = float(q["lod_threshold"])
	if _neighborhood:
		_neighborhood.set_view_distance(float(q["lot_radius"]))
	_day_night.set_shadows_wanted(q["shadows"])
	# Névoa: começa no meio do raio das árvores e fecha um pouco antes de elas acabarem.
	_day_night.set_fog_distance(float(q["big_radius"]) * 0.3, float(q["big_radius"]) * 0.95)
	_day_night.set_glow(q["glow"])
	_sun.directional_shadow_max_distance = maxf(1.0, q["shadow_distance"])
	_apply_render_scale()
	if _data:
		_data.radius = float(q["big_radius"]) + 20.0


## Resolução do 3D: em telas grandes (Retina), o 3D é renderizado menor e ampliado com
## FSR; a interface continua nítida, na resolução cheia (Quality.render_scale).
func _apply_render_scale() -> void:
	var vp := get_viewport()
	var s := Quality.render_scale(float(DisplayServer.window_get_size().y))
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = s
	vp.fsr_sharpness = 0.2


## Tamanho da interface escolhido nas configurações (multiplica a escala da janela).
func _apply_ui_scale() -> void:
	get_tree().root.content_scale_factor = Quality.ui_scale()


# --- Ações chamadas pelas janelas ----------------------------------------------------------

func building() -> bool:
	return _build.active


## Ponto de "casa": na frente do lote, do lado de dentro.
func home_point() -> Vector3:
	var lot := _session.lot()
	if lot.is_empty():
		return world.centers[_player.cell_id] * world.surface_radius(_player.cell_id)
	var f := _data.frame(int(lot["cell"])) if _data.world else world.cell_frame(int(lot["cell"]))
	return LotGeom.point(f, lot, _session.tile_size, _session.lot_tiles * 0.5, 1.2)


func go_home() -> void:
	if _session.lot().is_empty():
		_ui.toast("Você ainda não tem lote.")
		return
	await _teleport(home_point(), "home")
	_ui.toast("Bem-vindo de volta para casa!")


## Ponto seguro em terra: se `pos` cair numa célula de oceano, vai para o centro da
## célula de terra mais perto. Vale para teleporte, chegada de voo, nascimento e casa (H).
func land_point(pos: Vector3) -> Vector3:
	var cell := world.find_cell(pos, _player.cell_id)
	if world.is_land(cell):
		return pos
	var land := world.nearest_land(cell)
	return world.centers[land] * world.surface_radius(land)


## `why` diz ao servidor por que o personagem pulou de lugar: "home" (H), "travel" (chegada
## do voo pago), "dev" (modo dev e testes) ou "spawn".
func _teleport(pos: Vector3, why := "dev") -> void:
	# Teleporte para o globo (casa, voo, modo dev) saindo de dentro de uma caverna.
	if cave and cave.active:
		cave.leave_now()
	pos = land_point(pos)
	_build.exit()
	_tracker.mark_teleport()
	_player.set_physics_process(false)
	_player.teleport(pos)
	_net.teleport(why, _player.global_position)
	_last_sent = []
	_terrain.update_collision(pos, -1)
	_camera.snap_behind_target()
	await _data.load_now(pos, 40.0)
	_vegetation.load_now(pos)
	_player.set_physics_process(true)
	_ui.restore_control(true)


func teleport_to(pos: Vector3, why := "dev") -> void:
	await _teleport(pos, why)


func net_teleport(why: String, pos: Vector3) -> void:
	_net.teleport(why, pos)
	_last_sent = []


func my_id() -> int:
	return _net.player_id


## Liga ou desliga o modo caverna (fase 4.5): o globo, o céu e o sol somem; o ambiente fica
## meio escuro, como a noite do jogo, com brilhos e tochas.
func set_cave_mode(on: bool) -> void:
	_player.cave_mode = on
	_camera.cave_mode = on
	for n: Node3D in [_terrain, _vegetation, _clouds, _neighborhood, _airports, _border_lines, _animals, _highlight, _season_fx, legends, $Moon]:
		if n:
			n.visible = not on
	if _home_marker:
		_home_marker.visible = not on
	_sun.visible = not on
	var env := _env()
	if on:
		_cave_env = {"bg": env.background_mode, "bg_color": env.background_color, "amb_src": env.ambient_light_source,
			"amb": env.ambient_light_color, "amb_e": env.ambient_light_energy, "fog": env.fog_enabled,
			"fog_color": env.fog_light_color, "fog_d": env.fog_density}
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("07080d")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("7480a8")
		env.ambient_light_energy = 0.8
		env.fog_enabled = true
		env.fog_light_color = Color("0c0e16")
		env.fog_density = 0.02
		_camera.zoom = minf(_camera.zoom, 0.3)
	elif not _cave_env.is_empty():
		env.background_mode = _cave_env["bg"]
		env.background_color = _cave_env["bg_color"]
		env.ambient_light_source = _cave_env["amb_src"]
		env.ambient_light_color = _cave_env["amb"]
		env.ambient_light_energy = _cave_env["amb_e"]
		env.fog_enabled = _cave_env["fog"]
		env.fog_light_color = _cave_env["fog_color"]
		env.fog_density = _cave_env["fog_d"]
		_moon_restore()


## Nome do lugar no HUD (a caverna no lugar do país).
func show_place(name: String) -> void:
	_hud.set_country("", name)


func _moon_restore() -> void:
	_hud.set_country(_tracker.current, country_name(_tracker.current))
	# O DayNight decide sol e lua no próximo quadro.
	_day_night.update(0.0, _player.global_position.normalized(), _camera.far_amount)


func _teleport_to_cell(cell: int) -> void:
	await _teleport(world.centers[cell] * world.surface_radius(cell))


func teleport_country(code: String) -> void:
	# Célula de terra do país mais perto do "centro" dele, preferindo biomas agradáveis.
	var sum := Vector3.ZERO
	var cells: Array[int] = []
	for i in world.cell_count():
		if world.country_codes[i] == code and world.land[i] == 1:
			cells.append(i)
			sum += world.centers[i]
	if cells.is_empty():
		_ui.dev.status("Esse país não tem células no mundo.")
		return
	var anchor := sum.normalized()
	var nice := [WorldData.Biome.GRASSLAND, WorldData.Biome.FOREST, WorldData.Biome.TROPICAL_FOREST, WorldData.Biome.BEACH]
	var best := cells[0]
	var best_score := -INF
	for c in cells:
		var score := world.centers[c].dot(anchor) + (0.5 if int(world.biomes[c]) in nice else 0.0)
		if score > best_score:
			best_score = score
			best = c
	await _teleport_to_cell(best)
	_ui.dev.status(tr("Você está em %s.") % world.countries.get(code, code))


func teleport_lat_lon(lat: float, lon: float) -> void:
	var cell := world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(lat, lon)))
	await _teleport_to_cell(cell)
	_ui.dev.status(tr("Teleportado para %s.") % WorldData.format_lat_lon(world.lats[cell], world.lons[cell]))


func set_noclip(on: bool) -> void:
	if on and not _session.dev:
		return
	_player.set_noclip(on)
	_ui.toast("Voando: Espaço sobe, Ctrl desce, Shift acelera" if on else "Voltou a andar")


func time_faster() -> void:
	_day_night.faster()
	_hud.flash(tr("Tempo ×%d") % int(_day_night.speed))


func time_real() -> void:
	_day_night.real_time()
	_hud.flash("Horário real")


## Resposta de /lot/place, /lot/remove ou /lot/house: inventário e lote novos.
func apply_lot_result(res: Dictionary) -> void:
	_session.set_inventory(res["inventory"], int(res["slots_used"]))
	_session.set_lot(res["lot"])


# --- Estações ------------------------------------------------------------------------------

## Agora para as estações: a data forçada pelo modo dev ou o relógio do servidor.
func season_now() -> float:
	if Seasons.override_unix > 0.0:
		return Seasons.override_unix
	if _data and _data.world:
		return _data.server_time()
	var day: Variant = _session.me.get("day")
	if day is Dictionary:
		return float(day["server_time"])
	return Time.get_unix_time_from_system()


## Aplica a estação (fase no norte): chão, mini mapa, árvores e grama. Os modelos de outono
## e neve que ainda não estiverem carregados entram antes (só acontece ao forçar a data).
func apply_season(north: float) -> void:
	if _season_busy:
		return
	_season_busy = true
	var missing := Seasons.models_needed(_session.object_models, north).filter(
		func(m: String) -> bool: return ModelLibrary.get_cached(m).is_empty())
	if not missing.is_empty():
		_hud.show_status("Preparando a estação…")
		await ModelLibrary.preload_all(missing, get_tree())
		_hud.hide_status()
	_season_north = north
	var t0 := Time.get_ticks_usec()
	GlobeBuilder.land_material().set_shader_parameter("season_phase", north)
	_hud.set_season_phase(north)
	_vegetation.set_season(north)
	HitchLog.note("troca de estação (fase %.3f)" % north, (Time.get_ticks_usec() - t0) / 1000.0)
	_season_busy = false


## A cada quadro: partículas e o nome da estação no HUD; a cada 20 s, confere se a fase
## andou o bastante (umas 4 horas) para remontar as árvores e a grama.
func _update_season(delta: float) -> void:
	_season_timer -= delta
	if _season_timer <= 0.0:
		_season_timer = 20.0
		var north := Seasons.north_phase(season_now())
		if _season_north < 0.0 or absf(north - _season_north) > 0.002:
			apply_season(north)
	if _season_north < 0.0:
		return
	var cell := _player.cell_id
	var autumn := 0.0
	var winter := 0.0
	var label := "none"
	if Seasons.cell_has_seasons(world, cell):
		var ph := Seasons.phase_at(_season_north, world.lats[cell])
		autumn = Seasons.weight(ph, 2)
		winter = Seasons.weight(ph, 3)
		label = Seasons.NAMES[int(ph) % 4]
	_hud.set_season_label(Seasons.LABELS[label] if label != "none" else "")
	_season_fx.update(_camera, autumn, winter, _camera.far_amount)


## Modo dev: força uma estação (no hemisfério norte; o sul fica com a oposta) ou volta para
## a data real ("real").
func dev_force_season(season: String) -> void:
	if season == "real":
		Seasons.override_unix = 0.0
		_ui.dev.status("Estações pela data real.")
	else:
		var year := int(Time.get_datetime_dict_from_unix_time(int(season_now()))["year"])
		var md: Array = {"spring": [4, 25], "summer": [7, 25], "autumn": [10, 28], "winter": [1, 25]}[season]
		Seasons.override_unix = float(Time.get_unix_time_from_datetime_dict({"year": year, "month": md[0], "day": md[1], "hour": 12, "minute": 0, "second": 0}))
		_ui.dev.status(tr("Data forçada: %02d/%02d (%s no norte, %s no sul).") % [md[1], md[0],
			Seasons.LABELS[season].to_lower(), Seasons.LABELS[Seasons.NAMES[(Seasons.NAMES.find(season) + 2) % 4]].to_lower()])
	# O servidor confere as fotos de árvores e flores de estação pela mesma data (fase 4.2).
	await _api.request("POST", "/dev/season", {"unix": Seasons.override_unix})
	await apply_season(Seasons.north_phase(season_now()))


## Um animal comeu a frutinha (o servidor já marcou a amizade na Goblopédia).
func on_animal_fed(_species: String) -> void:
	pass


## Pedido ao servidor para as janelas (mesmo token do jogador).
func api_request(method: String, path: String, body: Variant = null) -> Dictionary:
	return await _api.request(method, path, body)


## Vende na caixa de vendas: [{"item", "count"}].
func sell(items: Array) -> Dictionary:
	if items.is_empty():
		_ui.toast("Nada para vender.")
		return {}
	var r := await _api.request("POST", "/sell", {"items": items})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return r
	_session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	_session.set_coins(int(r["data"]["coins"]))
	_ui.toast("+%s" % _session.coins_text(int(r["data"]["earned"])))
	return r


## Loja da praça: comprar (o estoque do dia; o servidor confere a distância e o preço).
func shop_buy(country: String, item: String, count: int) -> void:
	var r := await _api.request("POST", "/shop/buy", {"country": country, "item": item, "count": count})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	_session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	_session.set_coins(int(r["data"]["coins"]))
	_ui.toast(str(r["data"]["message"]), item)


## Loja da praça: vender (paga mais que a caixa de vendas).
func shop_sell(country: String, items: Array) -> void:
	if items.is_empty():
		return
	var r := await _api.request("POST", "/shop/sell", {"country": country, "items": items})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	_session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	_session.set_coins(int(r["data"]["coins"]))
	_ui.toast("+%s" % _session.coins_text(int(r["data"]["total"])))


func open_shop(country: String) -> void:
	_ui.close_windows()
	_ui.shop.open(country)


func open_shop_sell(country: String) -> void:
	_ui.close_windows()
	_ui.sell.open_mode("shop", country)


func craft(recipe: String) -> void:
	var r := await _api.request("POST", "/craft", {"recipe": recipe, "times": 1})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	_session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	var made: Dictionary = r["data"]["crafted"]
	_ui.toast("+%d %s" % [int(made["count"]), _session.item_name(made["item"])], made["item"])
	on_intro_task(str(r["data"].get("intro_task", "")), int(r["data"].get("intro_reward", 0)))


func start_house_placement() -> void:
	_build.enter_house()


func upgrade_house() -> void:
	var lot := _session.lot()
	var r := await _api.request("POST", "/lot/house", {"lot": lot["id"], "x": 0, "y": 0, "rot": 0})
	if not r["ok"]:
		var details: Variant = r.get("details")
		if details is Dictionary and (details as Dictionary).get("blockers") is Array:
			# Decorações no caminho: marca em vermelho e oferece guardar no bolso.
			var blockers: Array = details["blockers"]
			var ids := blockers.map(func(b: Dictionary) -> int: return int(b["id"]))
			_neighborhood.highlight_placements(int(lot["id"]), ids)
			_ui.craft.show_blockers(str(r["message"]), ids)
			return
		_ui.toast(str(r["message"]))
		return
	_ui.craft.clear_blockers()
	apply_lot_result(r["data"])
	_ui.toast("A reforma começou! Fica pronta amanhã às 5h.")


func clear_blocker_highlight() -> void:
	var lot := _session.lot()
	if not lot.is_empty():
		_neighborhood.highlight_placements(int(lot["id"]), [])


## Guarda no bolso os objetos que atrapalham a obra e tenta melhorar de novo.
func store_blockers_and_upgrade(ids: Array) -> void:
	for id: int in ids:
		var r := await _api.request("POST", "/lot/remove", {"placement": id})
		if not r["ok"]:
			_ui.toast(str(r["message"]))
			return
		apply_lot_result(r["data"])
	_ui.craft.clear_blockers()
	_ui.toast(tr("Guardei %d objeto%s no bolso.") % [ids.size(), "" if ids.size() == 1 else "s"])
	await upgrade_house()


# --- Modo dev -------------------------------------------------------------------------------

func _dev(path: String, body: Dictionary, done: String) -> Dictionary:
	var r := await _api.request("POST", path, body)
	if not r["ok"]:
		_ui.dev.status(tr("Erro: %s") % r["message"])
		_ui.toast(str(r["message"]))
		return r
	if r["data"] is Dictionary and (r["data"] as Dictionary).has("inventory"):
		_session.set_me(r["data"])
	_ui.dev.status(done)
	return r


func dev_give(item: String, count: int) -> void:
	await _dev("/dev/give", {"item": item, "count": count}, tr("Você ganhou %d× %s.") % [count, _session.item_name(item)])


func dev_starter_kit() -> void:
	for pair in [["axe", 1], ["pickaxe", 1], ["wood", 99], ["stone", 99], ["branch", 30], ["flower_red", 10], ["flower_yellow", 10]]:
		if _session.count(pair[0]) < int(pair[1]) or pair[0] != "axe" and pair[0] != "pickaxe":
			await _dev("/dev/give", {"item": pair[0], "count": pair[1]}, "Kit inicial entregue.")


func dev_coins(amount: int) -> void:
	await _dev("/dev/coins", {"amount": amount}, tr("Saldo: %s.") % _session.coins_text(_session.coins + amount))
	_ui.dev.status(tr("Saldo: %s.") % _session.coins_text(_session.coins))


func dev_passport(action: String, code: String) -> void:
	var r := await _api.request("POST", "/dev/passport", {"action": action, "country": code})
	if not r["ok"]:
		_ui.dev.status(tr("Erro: %s") % r["message"])
		return
	_session.set_passport_book(r["data"])
	var done := {"give": tr("Passaporte de %s entregue.") % country_name(code), "remove": tr("Passaporte de %s retirado.") % country_name(code),
		"complete": tr("Passaporte completo: %d passaportes, %d carimbos.") % [(r["data"]["passports"] as Array).size(), (r["data"]["stamps"] as Array).size()],
		"reset": "Passaportes e carimbos zerados (fica o do seu país)."}
	_ui.dev.status(str(done.get(action, "Pronto.")))


## Voo de graça para o aeroporto do país (modo dev), sem passaporte.
func dev_travel(code: String) -> void:
	var here := WorldData.vec_to_lat_lon(_player.global_position)
	var r := await _api.request("POST", "/dev/travel", {"from": _tracker.current, "to": code})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	await _arrive({"lat": here.x, "lon": here.y}, r["data"])


func set_barrier(on: bool) -> void:
	barrier_on = on
	_ui.dev.status(tr("Barreira da fronteira %s.") % ("ligada" if on else "desligada"))


## Modo dev: fronteiras todas abertas, todas fechadas ou pelos passaportes ("").
func set_border_view(mode: String) -> void:
	_border_lines.view_override = mode
	_border_lines.refresh_state(true)
	_ui.dev.status({"open": "Todas as fronteiras abertas (só a visão).", "closed": "Todas as fronteiras fechadas (só a visão).", "": "Fronteiras pelos seus passaportes."}[mode])


func set_border_lines(lines: bool, debug: bool) -> void:
	_border_lines.set_mode(lines, debug)
	_ui.dev.status(tr("Linhas de fronteira %s%s.") % ["ligadas" if lines else "desligadas", ", com os polígonos de debug" if debug else ""])


func dev_spawn_animal(species: String) -> void:
	var fwd := -_player.global_basis.z
	var ok := _animals.spawn_debug(species, _player.global_position + fwd * 3.0)
	_ui.dev.status(tr("%s criado aqui perto (só neste computador).") % _session.animal_species[species]["name"] if ok else "Não coube aqui (lote ou borda do hexágono).")


# --- Modo dev das cavernas e do folclore (fase 4.5) -----------------------------------------

## Caverna mais perto do jogador (id), pela lista de bocas.
func nearest_cave() -> int:
	var best := -1
	var best_d := -2.0
	var up := _player.global_position.normalized()
	for cv: Dictionary in cave.caves:
		var d := (world.centers[int(cv["cell"])] as Vector3).dot(up)
		if d > best_d:
			best_d = d
			best = int(cv["id"])
	return best


## Vai até a boca de caverna mais perto (no globo).
func dev_cave_mouth() -> void:
	var id := nearest_cave()
	for cv: Dictionary in cave.caves:
		if int(cv["id"]) == id:
			var f := _data.frame(int(cv["cell"]))
			var dir := ((f["east"] as Vector3) * cos(float(cv["yaw"])) + (f["north"] as Vector3) * sin(float(cv["yaw"]))).normalized()
			await _teleport(cave.mouth_point(cv) + dir * 2.5)
			_player.face(cave.mouth_point(cv))
			_ui.dev.status(tr("Na boca da caverna %d (%s).") % [id, country_name(str(cv["country"]))])


## Entra numa caverna de qualquer lugar (-1 = a mais perto).
func dev_cave_enter(id: int) -> void:
	if cave.active:
		cave.leave_now()
	await cave.enter(id if id >= 0 else nearest_cave(), true)


## Vai direto para a sala do chefe (dentro da caverna). sleep = o chefe já dorme e o
## jogador conta como quem desviou o bastante.
func dev_cave_boss(sleep: bool) -> void:
	if not cave.active:
		await dev_cave_enter(-1)
	if cave.cw == null:
		return
	var rm: Dictionary = cave.cw.boss_room
	var at := cave.cw.to_global(CaveWorld.local(float(rm["x"]) - float(rm["r"]) * 0.55, float(rm["y"]) + 0.5, float(rm["z"])))
	_player.teleport(at)
	_player.face(cave.cw.boss_point)
	net_teleport("dev", _player.global_position)
	_camera.snap_behind_target()
	if sleep:
		await _dev("/dev/cave/boss-sleep", {"cave": cave.cave_id}, "O golem dormiu (e você conta como quem desviou).")


func dev_cave_god(on: bool) -> void:
	await _dev("/dev/cave/god", {"on": on}, "Invencível contra o chefe." if on else "O chefe volta a acertar.")


func dev_cave_kit() -> void:
	var r := await _api.request("POST", "/dev/cave/kit", {})
	if r["ok"]:
		_session.set_me(r["data"])
		_ui.dev.status("Picaretas, machados, tochas, minérios, barras, fornalha, baú e capacete no bolso.")


func dev_fill_chest() -> void:
	var lot := _session.lot()
	for p: Dictionary in lot.get("placements", []):
		if str(p.get("item", "")) == "chest":
			var r := await _api.request("POST", "/dev/chest/fill", {"id": int(p["id"])})
			_ui.dev.status("Baú cheio." if r["ok"] else str(r["message"]))
			return
	_ui.dev.status("Coloque um baú no lote antes (B).")


func dev_legend(id: String) -> void:
	await legends.dev_spawn(id)


## Leva até um lugar onde a espécie nova vive (procura nas células carregáveis pelo bioma e
## pela região de animals.json) e faz um aparecer perto.
func dev_new_animal(species: String) -> void:
	_animals.spawn_debug(species, _player.global_position)
	_ui.dev.status(tr("%s apareceu perto de você (só para você, modo dev).") % _session.animal_species.get(species, {}).get("name", species))


func dev_list_animals() -> void:
	_ui.dev.status(_animals.describe())


func dev_pedia(action: String) -> void:
	var r := await _api.request("POST", "/dev/pedia", {"action": action})
	if not r["ok"]:
		_ui.dev.status(tr("Erro: %s") % r["message"])
		return
	if action == "reset":
		PediaPhotos.clear(_session.photo_account())
	_ui.pedia.set_entries(r["data"]["entries"])
	_ui.dev.status("Goblopédia completa." if action == "complete" else "Goblopédia zerada (as fotos continuam no álbum).")


func dev_finish_house() -> void:
	await _dev("/dev/finish-house", {}, "Obra concluída!")


func dev_next_day() -> void:
	var r := await _dev("/dev/next-day", {}, "Bom dia! Os limites diários voltaram e as obras ficaram prontas.")
	if r["ok"]:
		_data.refresh_all()


func dev_real_time() -> void:
	var r := await _dev("/dev/real-time", {}, "O relógio do servidor voltou para a hora real.")
	if r["ok"]:
		_data.refresh_all()


func dev_fake_neighbors(count: int) -> void:
	var r := await _dev("/dev/fake-neighbors", {"cell": _player.cell_id, "count": count}, "")
	if r["ok"]:
		_ui.dev.status(tr("%d vizinhos falsos criados aqui perto.") % int(r["data"]["created"]))
		_data.refresh_all()


func dev_set_country(code: String) -> void:
	var r := await _dev("/dev/country", {"country": code}, tr("Agora você mora em %s.") % world.countries.get(code, code))
	if r["ok"]:
		_data.refresh_all()
		await go_home()


func dev_reset(what: String) -> void:
	var r := await _dev("/dev/reset", {"what": what}, tr("Pronto: %s resetado.") % what)
	if not r["ok"]:
		return
	if what == "player":
		_session.clear_token()
		get_tree().reload_current_scene()
		return
	_data.refresh_all()


# --- Automação para testes e screenshots ---------------------------------------------------

func _is_automation() -> bool:
	for k in ["smoke-test", "screenshot", "route", "perf-test", "tour", "play-test", "camera-test", "profile-scene", "border-test", "animal-test", "photo-test", "season-test", "travel-test", "dev-test", "cursor-test", "hitch-test", "mp-test", "crowd-test", "npc-test", "body-test", "cpu-test", "cave-test"]:
		if _args.has(k):
			return true
	return false


func _run_automation() -> void:
	if _args.has("tour"):
		await _tour()
		return
	if _args.has("route"):
		await _route_test()
		return
	if _args.has("perf-test"):
		await _perf_test()
		return
	if _args.has("play-test"):
		await _play_test()
		return
	if _args.has("camera-test"):
		await _camera_test()
		return
	if _args.has("border-test"):
		await _border_test()
		return
	if _args.has("animal-test"):
		await _animal_test()
		return
	if _args.has("photo-test"):
		await _photo_test()
		return
	if _args.has("season-test"):
		await _season_test()
		return
	if _args.has("cursor-test"):
		await _cursor_test()
		return
	if _args.has("hitch-test"):
		await _hitch_test()
		return
	if _args.has("mp-test"):
		await _mp_test()
		return
	if _args.has("crowd-test"):
		await _crowd_test()
		return
	if _args.has("cpu-test"):
		await _cpu_test()
		return
	if _args.has("travel-test"):
		await _travel_test()
		return
	if _args.has("dev-test"):
		await _dev_test()
		return
	if _args.has("npc-test"):
		await _npc_test()
		return
	if _args.has("cave-test"):
		await _cave_test()
		return
	if _args.has("body-test"):
		await _body_test()
		return
	if _args.has("profile-scene"):
		await _profile_scene()
		return
	if not (_args.has("smoke-test") or _args.has("screenshot")):
		return
	if _args.has("screenshot"):
		await _screenshot_setup()
	var start_cell := _player.cell_id
	var walk := float(_args.get("walk", 3.0 if _args.has("smoke-test") else 0.0))
	await get_tree().create_timer(0.5).timeout
	if _args.has("jump"):
		_player.request_jump()
		var peak := 0.0
		var base := _player.global_position.length()
		for i in 60:
			await get_tree().physics_frame
			peak = maxf(peak, _player.global_position.length() - base)
		print("Goblo: pulo subiu %.2f (pulos: %d)" % [peak, _player.jumps])
		_player.request_jump()  # segundo pedido no ar não pode virar pulo duplo
	if walk > 0.0:
		if _args.has("run"):
			Input.action_press("run")
		var action := "move_" + str(_args.get("dir", "forward"))
		Input.action_press(action)
		await get_tree().create_timer(walk).timeout
		if not _args.has("moving"):
			Input.action_release(action)
			Input.action_release("run")
			await get_tree().create_timer(0.5).timeout

	if _args.has("smoke-test"):
		var id := _player.cell_id
		var r := _player.global_position.length()
		var expected := world.surface_radius(id)
		print("Goblo: smoke-test célula %d → %d, %s, %s (%s), raio do personagem %.2f (superfície %.2f), no chão: %s, animação %.2f" % [
			start_cell, id, world.country_name(id), world.biome_label(id),
			WorldData.format_lat_lon(world.lats[id], world.lons[id]), r, expected, _player.is_on_floor(), _player.anim_blend])
		print("Goblo: smoke-test vegetação: %d instâncias (grama, plantas e flores decorativas e objetos do servidor)" % _vegetation.instance_count)
		var ok := world.is_land(id) and absf(r - expected) < 0.5 and _player.is_on_floor()
		print("Goblo: smoke-test %s" % ("OK" if ok else "FALHOU"))
		get_tree().quit(0 if ok else 1)
		return

	if not _args.has("moving"):
		await get_tree().create_timer(float(_args.get("settle", 1.0))).timeout
	match str(_args.get("ui", "")):
		"inventory":
			_ui.inventory.toggle()
		"craft":
			_ui.craft.open()
		"house":
			_ui.craft.open()
			_ui.craft.get_child(0).get_child(1).current_tab = 1
		"dev":
			_ui.dev.toggle()
		"settings":
			_ui.settings.toggle()
		"build":
			_build.enter()
			Input.warp_mouse(get_viewport().get_visible_rect().size * Vector2(0.55, 0.6))
		"dev-viagem", "dev-natureza":
			_ui.dev.toggle()
			var tabs: TabContainer = _ui.dev.find_children("*", "TabContainer", true, false)[0]
			for i in tabs.get_tab_count():
				if tabs.get_tab_title(i).to_lower() == str(_args["ui"]).substr(4):
					tabs.current_tab = i
		"pedia":
			_ui.pedia.toggle()
		"passport":
			_ui.passport.toggle()
		"perf":
			_hud.toggle_perf()
	if _args.has("ui"):
		await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var path := str(_args["screenshot"])
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Goblo: screenshot salvo em %s (erro %d, %d objetos transparentes na frente da câmera)" % [path, err, _occlusion.faded_count()])
	get_tree().quit(0 if err == OK else 1)


## Cenas das capturas (fase 2.6), antes do `--ui` e da foto (servidor dev):
##   --season=winter|autumn|spring|summer  força a estação
##   --look=GRAUS                          gira a câmera em volta do personagem
##   --ui=welcome | photo | selfie | hearts | travel | flight | airport | pedia-full | passport-full
##        | shop | sell | dialog | intro | trade  (fase 3.5)
func _screenshot_setup() -> void:
	if _args.has("season"):
		await dev_force_season(str(_args["season"]))
		await get_tree().create_timer(1.5).timeout
	var ui := str(_args.get("ui", ""))
	match ui:
		"pedia-photos":
			# Fase 4.5: galeria com duas fotos de um animal (uma registra a página).
			await dev_give("camera", 1)
			_session.equip("camera")
			await get_tree().create_timer(0.5).timeout
			var an := _animals.nearest(_player.global_position, 40.0)
			if not an.is_empty():
				var anp: Vector3 = an["pos"]
				await _teleport(anp + anp.normalized().cross(Vector3.UP).normalized() * 6.0)
				await get_tree().create_timer(0.3).timeout
			_photo.enter()
			for k in 2:
				if not an.is_empty():
					_aim_at((_animals.nearest(_player.global_position, 40.0)["pos"] as Vector3) + (an["pos"] as Vector3).normalized() * 0.6)
				await get_tree().create_timer(0.6).timeout
				await _photo.take_photo()
			_photo.exit()
			_ui.pedia.toggle()
			_ui.pedia.open_section("photos")
			await get_tree().create_timer(1.0).timeout
		"photo", "selfie":
			await dev_give("camera", 1)
			_session.equip("camera")
			await get_tree().create_timer(0.5).timeout
			var a := _animals.nearest(_player.global_position, 40.0)
			if not a.is_empty():
				# Perto e centralizado: a mira fica dourada com o nome (ou ???).
				var ap: Vector3 = a["pos"]
				var aup := ap.normalized()
				await _teleport(ap + aup.cross(Vector3.UP).normalized() * 6.0)
				await get_tree().create_timer(0.3).timeout
			_photo.enter()
			if not a.is_empty():
				_aim_at((a["pos"] as Vector3) + (a["pos"] as Vector3).normalized() * 0.6)
			if ui == "selfie":
				# De costas para o animal: ele aparece atrás do personagem.
				_camera._heading = -_camera._heading
				_photo.set_selfie(true)
			await get_tree().create_timer(1.5).timeout
		"hearts":
			var a := _animals.nearest(_player.global_position, 40.0)
			if not a.is_empty():
				var p: Vector3 = a["pos"]
				var up := p.normalized()
				var side := up.cross(Vector3.UP).normalized()
				await _teleport(p + side * 1.8)
				_player.face(p)
				_camera.snap_behind_target()
				_animals.pet(int(a["id"]))
				await get_tree().create_timer(0.7).timeout
		"welcome":
			_hud.welcome(country_name(_tracker.current), tr("Carimbo novo no passaporte!  +%s") % _session.coins_text(10))
			await get_tree().create_timer(0.6).timeout
		"cave", "cave-boss", "cave-torch":
			# Fase 4.5: dentro da caverna mais perto (modo dev), no começo ou na sala do chefe.
			await dev_cave_kit()
			await dev_cave_enter(-1)
			await get_tree().create_timer(1.0).timeout
			if ui == "cave-boss":
				await dev_cave_god(true)
				await dev_cave_boss(false)
				await get_tree().create_timer(2.6).timeout
			if ui == "cave-torch":
				_session.equip("torch")
				await get_tree().create_timer(0.5).timeout
			_camera.snap_behind_target()
			await get_tree().create_timer(1.0).timeout
		"legend":
			# Fase 4.5: uma lenda aparecendo na frente do personagem (--legend=ID).
			await get_tree().create_timer(1.0).timeout
			await dev_legend(str(_args.get("legend", "legend_saci")))
			await get_tree().create_timer(2.5).timeout
		"cape":
			# Fase 4.5: escolha das bandeiras da capa (todos os carimbos, cinco escolhidos).
			await dev_wear()
			await dev_passport("complete", "")
			await wear("flag_cape")
			var stamped: Array = _player.look_view.get("stamped", [])
			await set_cape(stamped.slice(0, 5))
			await get_tree().create_timer(1.0).timeout
			wardrobe.toggle()
			wardrobe.open_cape()
			await get_tree().create_timer(1.5).timeout
		"wardrobe", "editor", "cook", "body":
			# Fase 4.0: guarda-roupa, editor, fogueira e o HUD do corpo.
			if ui != "cook":
				await dev_wear()
				await wear("coat")
				await wear("beanie")
			await dev_body({"temp": -8})
			await get_tree().create_timer(1.5).timeout
			match ui:
				"wardrobe":
					wardrobe.toggle()
				"editor":
					open_look_editor()
				"cook":
					await dev_body_kit()
					await body.light_fire()
					body.open_cook()
			await get_tree().create_timer(1.5).timeout
		"airport", "travel":
			var a := _airports.of_country(str(_args.get("country", _tracker.current)))
			await _teleport(_airports.arrival_point(a))
			if _args.has("plaza"):
				# --plaza=U,V: em qualquer ponto da praça (ao lado do avião, dos carros…).
				var uv := str(_args["plaza"]).split(",")
				await get_tree().create_timer(0.5).timeout
				await _teleport(_airports.plaza_point(a, float(uv[0]), float(uv[1])))
			await get_tree().create_timer(2.5).timeout
			if ui == "travel":
				await dev_coins(300)
				_ui.travel.open(a)
				await get_tree().create_timer(1.0).timeout
				_ui.travel._list.select(3)
				_ui.travel._show()
		"flight":
			dev_travel(str(_args.get("country", "JPN")))
			await get_tree().create_timer(float(_args.get("wait", 4.0))).timeout
		"shop", "dialog", "sell":
			# Praça: o lojista (diálogo), a loja aberta ou a venda na loja.
			var a := _airports.of_country(str(_args.get("country", _tracker.current)))
			await _teleport(_airports.arrival_point(a))
			await get_tree().create_timer(2.5).timeout
			await dev_starter_kit()
			for cell: int in _airports._built:
				for n in (_airports._built[cell] as Node3D).get_meta("npcs", []):
					if is_instance_valid(n) and (n as Npc).role == "shopkeeper" and (n as Npc).country == str(a["country"]):
						await _teleport(n.global_position - n.global_basis.z * 1.6)
						_player.face(n.global_position)
						_camera.snap_behind_target()
						await get_tree().create_timer(0.8).timeout
						await talk(n)
			await get_tree().create_timer(2.5).timeout
			if ui != "dialog":
				_dialog_choose(0 if ui == "shop" else 1)
				await get_tree().create_timer(1.0).timeout
		"intro":
			await restart_intro()
			await get_tree().create_timer(2.5).timeout
		"trade":
			await dev_starter_kit()
			await dev_trade_bot()
			await get_tree().create_timer(1.0).timeout
			_ui.trade._offer_items = [{"item": "stone", "count": 5}, {"item": "branch", "count": 2}]
			_ui.trade._send_offer()
			await get_tree().create_timer(0.8).timeout
			net_send({"t": "trade_ready", "on": true})
			await get_tree().create_timer(1.0).timeout
		"pedia-full", "pedia-legends", "pedia-caves":
			await _dev("/dev/pedia", {"action": "complete"}, "")
			_ui.pedia.toggle()
			if ui != "pedia-full":
				await get_tree().create_timer(0.5).timeout
				_ui.pedia.open_section("legend" if ui == "pedia-legends" else "cave")
			await get_tree().create_timer(2.5).timeout
		"furnace":
			await dev_cave_kit()
			_ui.furnace.open(-1)
			await api_request("POST", "/dev/cave/enter", {"cave": 0})
			await get_tree().create_timer(1.0).timeout
		"passport-full":
			await dev_passport("complete", "")
			_ui.passport.toggle()
			await get_tree().create_timer(1.0).timeout
	if _args.has("look"):
		_camera._turn(deg_to_rad(float(_args["look"])))
		await get_tree().create_timer(0.5).timeout


## Testa o ciclo do jogo de ponta a ponta contra um servidor com GOBLO_DEV=1:
## coleta (sacudir, cortar, quebrar, colher), fabricação, decoração e casa.
func _play_test() -> void:
	var fails: Array[String] = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: play-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	check.call(_session.dev, "servidor em modo dev")
	# Menus capturam a roda do mouse: com a bancada aberta, a roda não mexe no zoom.
	_ui.craft.open()
	var zoom_before := _camera.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(wheel)
	await get_tree().process_frame
	await get_tree().process_frame
	check.call(is_equal_approx(_camera.zoom, zoom_before) and _player.input_blocked, "menu aberto segura a roda do mouse e o movimento")
	_ui.close_windows()
	await dev_starter_kit()
	check.call(_session.count("axe") == 1 and _session.count("wood") >= 99, "kit inicial (machado e madeira)")

	# Coleta: acha uma árvore, uma pedra e uma flor perto de casa e interage com cada uma.
	for spec in [["tree", "", "branch"], ["tree", "axe", "wood"], ["rock", "pickaxe", "stone"], ["flower", "", ""]]:
		var kind: String = spec[0]
		var obj := {}
		for o: Dictionary in _data.objects_near(_player.global_position, 140.0):
			if o["kind"] == kind and not (kind == "tree" and (o.get("drop", "") != "branch" or not o.get("chop", false))):
				var st: Dictionary = o.get("state", {}) if o.get("state") is Dictionary else {}
				if st.is_empty():
					obj = o
					break
		if obj.is_empty():
			check.call(false, "achar %s perto de casa" % kind)
			continue
		_session.equip(spec[1])
		var up: Vector3 = obj["up"]
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		await _teleport((obj["pos"] as Vector3) + side * 1.1)
		await get_tree().create_timer(0.3).timeout
		_interaction.target = {"type": "object", "obj": obj}
		var before := _session.count(spec[2]) if spec[2] != "" else _session.count(str(obj.get("item", "")))
		var r: Dictionary = await _interaction.interact()
		var after := _session.count(spec[2]) if spec[2] != "" else _session.count(str(obj.get("item", "")))
		check.call(r.get("ok", false) and after > before, "interagir com %s (%s): %d → %d" % [kind, spec[1] if spec[1] != "" else "mão", before, after])
	# Limite diário: sacudir a mesma árvore de novo falha.
	_session.equip("")

	await go_home()
	var lot := _session.lot()
	# Fabricação.
	await craft("lantern")
	check.call(_session.count("lantern") >= 1, "fabricar lampião")
	# Decoração: coloca o lampião no primeiro lugar livre.
	var placed := false
	for y in range(0, _session.lot_tiles):
		for x in range(0, _session.lot_tiles):
			if placed:
				break
			var r := await _api.request("POST", "/lot/place", {"lot": lot["id"], "item": "lantern", "x": x, "y": y, "rot": 0})
			if r["ok"]:
				apply_lot_result(r["data"])
				placed = true
		if placed:
			break
	check.call(placed, "colocar o lampião no lote")
	# Casa: barraca no meio do lote, concluída na hora pelo modo dev.
	var house := false
	for y in [6, 4, 2, 0]:
		var r := await _api.request("POST", "/lot/house", {"lot": lot["id"], "x": 2, "y": y, "rot": 0})
		if r["ok"]:
			apply_lot_result(r["data"])
			house = true
			break
	check.call(house, "começar a obra da barraca")
	await dev_finish_house()
	var h: Variant = _session.lot().get("house")
	check.call(h is Dictionary and int(h["level"]) == 1, "barraca pronta pelo modo dev")
	await get_tree().create_timer(0.5).timeout
	var node := _neighborhood.lot_node(int(lot["id"]))
	check.call(node != null and node.get_child_count() >= 4, "casa e lampião desenhados no lote")
	# Melhoria: lampiões atrás e na frente da barraca bloqueiam a casinha; o servidor lista
	# o objeto e "guardar no bolso e melhorar" resolve.
	for pair in [["wood", 30], ["stone", 20], ["lantern", 2]]:
		await dev_give(pair[0], pair[1])
	var hx := int(_session.lot()["house"]["x"])
	var hy := int(_session.lot()["house"]["y"])
	for pos in [[hx + 1, hy + 6], [hx + 1, hy - 1]]:
		var pr := await _api.request("POST", "/lot/place", {"lot": lot["id"], "item": "lantern", "x": pos[0], "y": pos[1], "rot": 0})
		if pr["ok"]:
			apply_lot_result(pr["data"])
	await upgrade_house()
	var blocked := not _ui.craft._blockers.is_empty()
	check.call(blocked, "melhoria bloqueada lista os objetos no caminho")
	if blocked:
		await store_blockers_and_upgrade(_ui.craft._blockers.duplicate())
	var hp: Variant = _session.lot().get("house")
	check.call(hp is Dictionary and int(hp["pending_level"]) == 2, "guardar no bolso e melhorar começa a obra da casinha")
	# Caixa de vendas: o lote novo já vem com ela; vender madeira credita o preço certo.
	_ui.close_windows()
	var sell_box: Array = _interaction._own_placements("sell_box")
	check.call(not sell_box.is_empty(), "caixa de vendas no lote")
	var coins_before := _session.coins
	var wood_before := _session.count("wood")
	var price := int(_session.sell_prices.get("wood", 0))
	await sell([{"item": "wood", "count": 2}])
	check.call(_session.coins == coins_before + 2 * price and _session.count("wood") == wood_before - 2,
		"vender 2 madeiras: %d → %d gobolares" % [coins_before, _session.coins])
	_ui.close_windows()
	print("Goblo: play-test %s (%d falhas)" % ["OK" if fails.is_empty() else "FALHOU", fails.size()])
	if _args.has("screenshot"):
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(_args["screenshot"]))
	get_tree().quit(0 if fails.is_empty() else 1)


## Mede quanto cada parte da cena custa, parado no mesmo lugar e com a mesma câmera:
## desliga uma parte por vez e compara GPU, CPU de render e draw calls com tudo ligado.
func _profile_scene() -> void:
	if _args.has("neighbors"):
		await dev_fake_neighbors(int(_args["neighbors"]))
		await get_tree().create_timer(2.0).timeout
	# Fase 4.1: bots com roupas (--bots=N) e fogueiras acesas em volta (--fires=N).
	if _args.has("bots"):
		await dev_bots(int(_args["bots"]))
		await get_tree().create_timer(4.0).timeout
	if _args.has("fires"):
		_profile_fires(int(_args["fires"]))
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await get_tree().create_timer(2.0).timeout
	var measure := func() -> Dictionary:
		await get_tree().create_timer(0.6).timeout
		var n := 0
		var gpu := 0.0
		var cpu := 0.0
		var dc := 0.0
		var prim := 0.0
		var t0 := Time.get_ticks_usec()
		while n < 90:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			n += 1
		var frame_ms := (Time.get_ticks_usec() - t0) / 1000.0 / n
		return {"gpu": gpu / n, "cpu": cpu / n, "dc": dc / n, "prim": prim / n / 1000.0, "frame": frame_ms}
	var parts := {
		"sombras": [func() -> void: _day_night.set_shadows_wanted(false), func() -> void: _apply_quality()],
		"antisserrilhado (MSAA/FXAA)": [func() -> void:
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED, func() -> void: _apply_quality()],
		"árvores e pedras (servidor)": [func() -> void: _set_layer_visible("big", false), func() -> void: _set_layer_visible("big", true)],
		"grama e plantinhas (cliente)": [func() -> void: _set_layer_visible("small", false), func() -> void: _set_layer_visible("small", true)],
		"casas e lotes": [func() -> void: _neighborhood.visible = false, func() -> void: _neighborhood.visible = true],
		"chão e oceano": [func() -> void: _terrain.visible = false, func() -> void: _terrain.visible = true],
		"nuvens": [func() -> void: _clouds.visible = false, func() -> void: _clouds.visible = true],
		"névoa": [func() -> void: _env().fog_enabled = false, func() -> void: _env().fog_enabled = true],
		"glow": [func() -> void: _env().glow_enabled = false, func() -> void: _apply_quality()],
		"tonemapping AgX e ajuste de cor": [func() -> void:
			_env().tonemap_mode = Environment.TONE_MAPPER_LINEAR
			_env().adjustment_enabled = false, func() -> void:
			_env().tonemap_mode = Environment.TONE_MAPPER_AGX
			_env().adjustment_enabled = true],
		"vento e variação (shader de folhagem)": [func() -> void: _set_foliage(false), func() -> void: _set_foliage(true)],
		"outros personagens": [func() -> void: _remotes.visible = false, func() -> void: _remotes.visible = true],
		"fogueiras (luz e fogo)": [func() -> void: body.visible_fires(false), func() -> void: body.visible_fires(true)],
		"flores decorativas": [func() -> void: _set_flowers_visible(false), func() -> void: _set_flowers_visible(true)],
		"céu": [func() -> void: (get_node("WorldEnvironment") as WorldEnvironment).environment.background_mode = Environment.BG_COLOR,
			func() -> void: (get_node("WorldEnvironment") as WorldEnvironment).environment.background_mode = Environment.BG_SKY],
	}
	# --off=nevoa,glow,tonemap,folhagem,sombras: desliga desde o começo e só mede o total
	# (trocar no meio recompila shaders e atrapalha a medição seguinte).
	if _args.has("off"):
		var offs := str(_args["off"]).split(",")
		for o in offs:
			match o:
				"nevoa": _env().fog_enabled = false
				"glow": _env().glow_enabled = false
				"tonemap":
					_env().tonemap_mode = Environment.TONE_MAPPER_LINEAR
					_env().adjustment_enabled = false
				"folhagem": _set_foliage(false)
				"sombras": _day_night.set_shadows_wanted(false)
		await get_tree().create_timer(3.0).timeout
		var only: Dictionary = await measure.call()
		print("Goblo: perfil-off %s (qualidade %s): %.1f fps (quadro %.1f ms), GPU %.1f ms, CPU render %.1f ms, %d draw calls" % [
			str(_args["off"]), Quality.current_name(), 1000.0 / maxf(0.1, only["frame"]), only["frame"], only["gpu"], only["cpu"], int(only["dc"])])
		get_tree().quit()
		return
	var base: Dictionary = await measure.call()
	var win := DisplayServer.window_get_size()
	print("Goblo: perfil (%s, qualidade %s, janela %d × %d, 3D em %d%%): tudo ligado: GPU %.1f ms, CPU render %.1f ms, quadro %.1f ms, %d draw calls, %.0f mil triângulos, %d objetos" % [
		world.biome_label(_player.cell_id), Quality.current_name(), win.x, win.y, roundi(get_viewport().scaling_3d_scale * 100.0),
		base["gpu"], base["cpu"], base["frame"], int(base["dc"]), base["prim"], _vegetation.instance_count])
	for name: String in parts:
		(parts[name][0] as Callable).call()
		var m: Dictionary = await measure.call()
		(parts[name][1] as Callable).call()
		print("Goblo: perfil   sem %s: GPU %.1f ms (−%.1f), CPU render %.1f ms (−%.1f), draw calls %d (−%d), triângulos −%.0f mil" % [
			name, m["gpu"], base["gpu"] - m["gpu"], m["cpu"], base["cpu"] - m["cpu"], int(m["dc"]), int(base["dc"] - m["dc"]), base["prim"] - m["prim"]])
	get_tree().quit()


func _env() -> Environment:
	return (get_node("WorldEnvironment") as WorldEnvironment).environment


## Liga/desliga o shader de folhagem (volta ao material simples), para medir o custo.
func _set_foliage(on: bool) -> void:
	for mmi in _vegetation.find_children("*", "MultiMeshInstance3D", true, false):
		if on and mmi.has_meta("foliage"):
			(mmi as MultiMeshInstance3D).material_override = mmi.get_meta("foliage")
		elif not on and (mmi as MultiMeshInstance3D).material_override:
			mmi.set_meta("foliage", (mmi as MultiMeshInstance3D).material_override)
			(mmi as MultiMeshInstance3D).material_override = null


## Fogueiras falsas em volta do jogador (só para medir; não existem no servidor).
func _profile_fires(n: int) -> void:
	var f := world.cell_frame(_player.cell_id)
	for i in n:
		var a := TAU * i / maxf(n, 1)
		var r := 3.0 + 2.0 * (i % 3)
		var q := WorldData.frame_coords(f, _player.global_position)
		body.add_fire({"id": 900000 + i, "cell": _player.cell_id, "x": q.x + cos(a) * r, "y": q.y + sin(a) * r, "left": 3600})


func _set_flowers_visible(on: bool) -> void:
	for c in _vegetation.get_children():
		if c.has_meta("layer") and c.get_meta("layer") == "small":
			for mmi in c.get_children():
				if str(mmi.get_meta("model", "")).contains("flower"):
					(mmi as Node3D).visible = on


func _set_layer_visible(layer: String, on: bool) -> void:
	for c in _vegetation.get_children():
		if c.has_meta("layer") and c.get_meta("layer") == layer:
			(c as Node3D).visible = on


## Animais: existem perto de campos e florestas, ficam no trajeto comum, reagem ao carinho
## e à frutinha, o tímido foge de quem corre e nenhuma animação de ataque é usada.
func _animal_test() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: animal-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	# Procura animais de verdade (do servidor) em campos e florestas conhecidos.
	var found := false
	for spot: Array in [[-34.6, -60.5], [48.5, 2.0], [46.5, 4.5], [52.0, 20.0], [-31.0, -56.0], [38.0, -97.0]]:
		await teleport_exact(spot[0], spot[1])
		await get_tree().create_timer(1.2).timeout
		if _animals.active_count > 0:
			found = true
			break
	check.call(found, "animais do servidor perto (%d com modelo)" % _animals.active_count)
	if found:
		# Sem reação, o animal fica exatamente no trajeto comum (todo mundo vê igual). Compara
		# com a pose do horário da última atualização dele (os mais longe atualizam menos).
		var worst := 0.0
		for id: int in _animals._active:
			var e: Dictionary = _animals._active[id]
			var pose := AnimalPath.at(e["animal"], float(e.get("t", _data.server_time())))
			var f := _data.frame(int(e["animal"]["cell"]))
			var want := WorldData.frame_point(f, pose["x"], pose["y"])
			worst = maxf(worst, (e["node"] as Node3D).global_position.distance_to(want))
		check.call(worst < 0.3, "animais no trajeto comum (maior diferença %.3f)" % worst)
	# Animais criados aqui (modo dev) para testar as reações num lugar conhecido.
	await teleport_exact(-34.6, -60.5)
	await get_tree().create_timer(0.6).timeout
	var made := _animals.spawn_debug("cow", _player.global_position) and _animals.spawn_debug("deer", _player.global_position + _player.global_basis.x * 2.0)
	await get_tree().create_timer(1.0).timeout
	check.call(made and _animals.active_count >= 2, "criar animais perto (modo dev)")
	var cow := {}
	var deer := {}
	for id: int in _animals._active:
		var sp := str(_animals._active[id]["animal"]["species"])
		if id < 0 and sp == "cow":
			cow = _animals._active[id]
		elif id < 0 and sp == "deer":
			deer = _animals._active[id]
	if not cow.is_empty():
		var cid := int(cow["animal"]["id"])
		await _teleport((cow["node"] as Node3D).global_position + _player.global_basis.z * 1.2)
		await get_tree().create_timer(0.4).timeout
		_interaction._timer = 0.0
		await get_tree().create_timer(0.2).timeout
		_session.inventory = _session.inventory.filter(func(st: Dictionary) -> bool: return st["item"] != "berries")
		var t: Dictionary = _interaction.target
		check.call(t.get("type", "") == "animal", "E perto do animal mira nele (%s)" % _interaction._prompt_text(t))
		_interaction.target = {"type": "animal", "animal": {"id": cid, "species": "cow", "name": "Vaca", "pos": (cow["node"] as Node3D).global_position}}
		_interaction._timer = 10.0
		await _interaction.interact()
		await get_tree().create_timer(0.3).timeout
		var hold: String = cow["anim"]
		check.call(hold in ["Idle_2", "Jump_toIdle", "Jump_ToIdle"], "carinho: o animal reage (%s)" % hold)
		await dev_give("berries", 3)
		await get_tree().create_timer(2.0).timeout
		var berries := _session.count("berries")
		# Mira na vaca (o cervo pode estar mais perto).
		_interaction.target = {"type": "animal", "animal": {"id": cid, "species": "cow", "name": "Vaca", "pos": (cow["node"] as Node3D).global_position}}
		_interaction._timer = 10.0
		await _interaction.interact()
		await get_tree().create_timer(0.3).timeout
		check.call(_animals.is_friend(cid) and str(cow["anim"]) == "Eating", "frutinha: come e vira amigo (%s)" % cow["anim"])
		check.call(_session.count("berries") == berries, "animal do modo dev não gasta frutinha do servidor")
	if not deer.is_empty():
		# Corre na direção do cervo: ele foge galopando e depois volta ao trajeto.
		var did := int(deer["animal"]["id"])
		# Começa a 5 unidades do cervo (sem árvore no caminho atrapalhando a corrida).
		var dp: Vector3 = (deer["node"] as Node3D).global_position
		var dup := dp.normalized()
		var side := _player.global_position - dp
		side = (side - dup * side.dot(dup)).normalized()
		await _teleport(dp + side * 5.0)
		_player.autopilot = true
		_player.auto_run = true
		var fled := false
		for i in 180:
			var to := (deer["node"] as Node3D).global_position - _player.global_position
			_player.auto_wish = to - _player.global_position.normalized() * to.dot(_player.global_position.normalized())
			await get_tree().physics_frame
			if str(deer["anim"]) == "Gallop":
				fled = true
		_player.autopilot = false
		_player.auto_wish = Vector3.ZERO
		var disp: Vector2 = _animals._local_state(did)["disp"]
		check.call(fled and disp.length() > 1.0, "tímido foge galopando (desvio %.1f)" % disp.length())
	var bad := []
	for id: int in _animals._active:
		var ap: AnimationPlayer = _animals._active[id]["ap"]
		if ap and (ap.current_animation.begins_with("Attack") or ap.current_animation == "Death"):
			bad.append(ap.current_animation)
	check.call(bad.is_empty(), "nenhuma animação de ataque ou morte")
	# Custo: tempo do _process dos animais por quadro (headless: só CPU).
	var total := 0
	for i in 120:
		var t0 := Time.get_ticks_usec()
		_animals._process(1.0 / 60.0)
		total += Time.get_ticks_usec() - t0
		await get_tree().process_frame
	print("Goblo: animal-test custo: %.3f ms por quadro com %d animais (CPU, sem desenho)" % [total / 120.0 / 1000.0, _animals.active_count])
	print("Goblo: animal-test %s" % ("tudo certo" if fails.is_empty() else "%d falhas" % fails.size()))
	get_tree().quit(1 if not fails.is_empty() else 0)


## Câmera fotográfica e Goblopédia, do modo foto ao álbum.
func _photo_test() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: photo-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	await _dev("/dev/pedia", {"action": "reset"}, "")
	await dev_give("camera", 1)
	_session.equip("camera")
	await teleport_exact(-34.6, -60.5)
	await get_tree().create_timer(1.5).timeout
	# Um animal do servidor (o trajeto comum: o servidor confere a foto por ele).
	var pick := {}
	var best := INF
	for id: int in _animals._active:
		var d := (_animals._active[id]["node"] as Node3D).global_position.distance_to(_player.global_position)
		if id >= 0 and d < best:
			best = d
			pick = _animals._active[id]
	check.call(not pick.is_empty(), "um animal do servidor por perto (%.0f unidades)" % best)
	if pick.is_empty():
		get_tree().quit(1)
		return
	var aid := int(pick["animal"]["id"])
	var sp := str(pick["animal"]["species"])
	var node: Node3D = pick["node"]
	# Fica a 7 unidades dele (a cada quadro: ele anda) e mira no meio dele.
	var last := node.global_position
	var stand := func(dist: float) -> void:
		if is_instance_valid(node):
			last = node.global_position
		var up := last.normalized()
		var side := up.cross(Vector3.UP).normalized()
		_teleport(last + side * dist)
		await get_tree().create_timer(0.3).timeout
		if _animals._active.has(aid):
			node = _animals._active[aid]["node"]

	await stand.call(7.0)
	_photo.enter()
	check.call(_photo.active and _camera.photo_mode, "botão direito com a câmera na mão entra no modo foto")
	_aim_at(node.global_position + node.global_position.normalized() * float(_animals.species[sp]["height"]) * 0.55)
	await get_tree().create_timer(0.4).timeout
	var subjects := _photo.find_subjects()
	check.call(not subjects.is_empty() and str(subjects[0]["entry"]) == sp, "%s centralizado é o assunto: %s" % [sp, str(subjects.map(func(x: Dictionary) -> String: return x["entry"]))])
	check.call(not _photo.aim.is_empty() and _photo._aim_label.text == "???", "mira dourada com ??? (ainda não descoberto): %s" % _photo._aim_label.text)
	var coins := _session.coins
	_aim_at(node.global_position + node.global_position.normalized() * float(_animals.species[sp]["height"]) * 0.55)
	var reg := await _photo.take_photo()
	var first: Dictionary = reg[0] if reg.size() == 1 else {}
	check.call(reg.size() == 1 and str(first.get("entry", "")) == sp and bool(first.get("first", false)) and _session.coins == coins + int(first.get("reward", 0)),
		"primeira foto registra só o assunto e paga (%s, %d → %d gobolares)" % [str(reg), coins, _session.coins])
	check.call(_photo._aim_label.text == _photo.entry_name(sp), "depois do registro, a mira mostra o nome: %s" % _photo._aim_label.text)
	_aim_at(node.global_position + node.global_position.normalized() * float(_animals.species[sp]["height"]) * 0.55)
	var reg2 := await _photo.take_photo()
	check.call(not reg2.is_empty() and not bool(reg2[0]["first"]) and int(reg2[0]["reward"]) == 0, "segunda foto não paga de novo")
	# Fora do centro: virado 35° para o lado, o animal não conta.
	_camera._turn(deg_to_rad(35.0))
	await get_tree().create_timer(0.3).timeout
	check.call(_photo.find_subjects().filter(func(x: Dictionary) -> bool: return x["entry"] == sp).is_empty(), "fora do centro (35°), o animal não conta")
	# Escondido: uma parede entre a câmera e o animal.
	_aim_at(node.global_position + node.global_position.normalized() * float(_animals.species[sp]["height"]) * 0.55)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(3, 3, 0.3)
	wall.add_child(shape)
	add_child(wall)
	var eye := _camera.global_position
	var mid := eye.lerp(node.global_position, 0.5)
	wall.look_at_from_position(mid, node.global_position, mid.normalized())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hidden: Array = _photo.find_subjects().filter(func(x: Dictionary) -> bool: return x["entry"] == sp)
	if not hidden.is_empty():
		var q := PhysicsRayQueryParameters3D.create(_camera.global_position, hidden[0]["at"])
		print("parede: ", get_world_3d().direct_space_state.intersect_ray(q))
	check.call(hidden.is_empty(), "escondido atrás de uma parede, não conta")
	wall.queue_free()
	await get_tree().physics_frame
	# Primeira pessoa: câmera nos olhos e corpo escondido.
	var head := _player.global_position + _player.global_position.normalized() * CameraRig.EYE_HEIGHT
	check.call(_camera.global_position.distance_to(head) < 0.3 and not _player.body_visible(),
		"primeira pessoa: câmera nos olhos (%.2f) e corpo escondido" % _camera.global_position.distance_to(head))
	# F: selfie, de costas para o animal (ele aparece atrás do personagem, no meio da foto).
	var key_f := InputEventKey.new()
	key_f.keycode = KEY_F
	key_f.pressed = true
	Input.parse_input_event(key_f)
	await get_tree().create_timer(0.3).timeout
	# No selfie, a câmera fica para o lado do heading e olha de volta: o animal, do outro lado.
	var up0 := _player.global_position.normalized()
	var away := _player.global_position - node.global_position
	_camera._heading = (away - up0 * away.dot(up0)).normalized()
	await get_tree().create_timer(0.4).timeout
	var to_cam := _camera.global_position - _player.global_position
	check.call(_photo.selfie() and _player.body_visible() and _player.pose_blend > 0.5 and to_cam.dot(-_player.global_basis.z) > 1.0 and _player.input_blocked,
		"F liga o selfie: câmera na frente, corpo à vista, pose (%.2f), parado" % _player.pose_blend)
	var in_selfie: Array = _photo.find_subjects().map(func(x: Dictionary) -> String: return str(x["entry"]))
	check.call(sp in in_selfie, "selfie: %s atrás do personagem enquadrado: %s" % [sp, str(in_selfie)])
	var reg3 := await _photo.take_photo()
	var horse_selfie: bool = not reg3.is_empty() and reg3[0]["entry"] == sp
	check.call(not reg3.is_empty() and not in_selfie.is_empty() and reg3[0]["entry"] == in_selfie[0],
		"selfie registra só o mais centralizado (%s)" % (str(reg3[0]["entry"]) if not reg3.is_empty() else "nada"))
	Input.parse_input_event(key_f)
	await get_tree().create_timer(0.3).timeout
	check.call(not _photo.selfie() and not _player.body_visible(), "F de novo volta para a primeira pessoa")
	# Longe: a 55 unidades fica pequeno demais (ou longe demais) e não conta.
	_aim_at(node.global_position)
	var at_far := node.global_position
	await stand.call(55.0)
	_aim_at(at_far)
	await get_tree().create_timer(0.3).timeout
	check.call(_photo.find_subjects().filter(func(x: Dictionary) -> bool: return x["entry"] == sp).is_empty(), "a 55 unidades, não conta")
	# Flores, de perto: uma do servidor e uma decorativa (as que houver por aqui).
	var picked := {}
	for x: Dictionary in _photo_flowers_near(40.0):
		if not picked.has(x["decor"]):
			picked[x["decor"]] = x
	check.call(not picked.is_empty(), "flores por perto para fotografar (%s)" % ", ".join(picked.keys().map(func(k: bool) -> String: return "decorativa" if k else "do servidor")))
	for decor: bool in picked:
		var flower: Dictionary = picked[decor]
		var fp: Vector3 = flower["pos"]
		var up := fp.normalized()
		var side := up.cross(Vector3.UP).normalized()
		_teleport(fp + side * 3.4)
		await get_tree().create_timer(0.5).timeout
		_aim_at(fp + up * 0.18)
		await get_tree().create_timer(0.3).timeout
		var fs := _photo.find_subjects()
		var kind := "decorativa" if decor else "do servidor"
		check.call(not fs.is_empty() and str(fs[0]["entry"]) == str(flower["item"]), "flor %s (%s) centralizada é o assunto: %s" % [flower["item"], kind, str(fs.map(func(x: Dictionary) -> String: return x["entry"]))])
		_aim_at(fp + up * 0.18)
		var reg4 := await _photo.take_photo()
		check.call(not reg4.is_empty() and str(reg4[0]["entry"]) == str(flower["item"]), "flor %s registra: %s" % [kind, str(reg4)])
	_photo.exit()
	check.call(_player.body_visible() and not _player.posing, "sair do modo foto mostra o corpo de novo")
	check.call(not _camera.photo_mode, "botão direito ou Esc sai do modo foto")
	_ui.pedia.toggle()
	await get_tree().create_timer(1.0).timeout
	var page: Array = _ui.pedia._entries.filter(func(e: Dictionary) -> bool: return e["id"] == sp)
	var want := 3 if horse_selfie else 2
	check.call(not page.is_empty() and bool(page[0]["discovered"]) and int(page[0]["sightings"]) == want and str(page[0]["country"]) == "ARG",
		"Goblopédia: %s descoberto na Argentina, %d fotos (%s)" % [sp, want, str(page)])
	check.call(_ui.pedia._entries.size() >= 15, "álbum com %d páginas" % _ui.pedia._entries.size())
	_ui.close_windows()
	print("Goblo: photo-test %s" % ("tudo certo" if fails.is_empty() else "%d falhas" % fails.size()))
	get_tree().quit(1 if not fails.is_empty() else 0)


## Teste: vira a câmera do modo foto (primeira pessoa) para o ponto.
func _aim_at(point: Vector3) -> void:
	var up := _player.global_position.normalized()
	var eye := _player.global_position + up * CameraRig.EYE_HEIGHT
	var to := point - eye
	var flat := to - up * to.dot(up)
	_camera._heading = flat.normalized()
	_camera.photo_pitch = clampf(rad_to_deg(atan2(to.dot(up), flat.length())), -10.0, 50.0)


## Teste: flores que registram perto do personagem (do servidor e decorativas que nascem ali).
func _photo_flowers_near(r: float) -> Array:
	var out: Array = []
	var entries := _photo._flower_entries()
	for o: Dictionary in _data.objects_near(_player.global_position, r):
		if str(o["kind"]) == "flower" and entries.has(str(o.get("item", ""))):
			out.append({"pos": o["pos"], "item": o["item"], "decor": false})
	var models := _photo._flower_models()
	for f: Array in _vegetation.decor_flowers_near(_player.global_position, r):
		var item := str(models.get(f[1], ""))
		if entries.has(item) and _photo._grows_here(item, f[0]):
			out.append({"pos": f[0], "item": item, "decor": true})
	return out


## Estações: no norte e no sul, árvores trocam de modelo pela estação, o HUD mostra o
## nome, os trópicos não mudam e a árvore de outono entra na Goblopédia.
func _season_test() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: season-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	var variants := func() -> Dictionary:
		var out := {"autumn": 0, "snow": 0, "": 0}
		for key: int in _data.loaded_keys():
			for o: Dictionary in _data.chunk(key).get("objects", []):
				if o.has("season_variant") and o["season_variant"] in out:
					out[o["season_variant"]] += 1
		return out
	var settle := func() -> void:
		for i in 40:
			await get_tree().process_frame
		await get_tree().create_timer(0.6).timeout
		_season_timer = 0.0
		await get_tree().process_frame
	await teleport_exact(50.5, 10.0)  # floresta na Alemanha
	await dev_force_season("winter")
	_vegetation.load_now(_player.global_position)
	await settle.call()
	var v: Dictionary = variants.call()
	check.call(v["snow"] > 0 and _hud._season_label == "Inverno", "inverno na Alemanha: %d objetos com neve, HUD \"%s\"" % [v["snow"], _hud._season_label])
	await dev_force_season("autumn")
	_vegetation.load_now(_player.global_position)
	await settle.call()
	v = variants.call()
	check.call(v["autumn"] > 0 and v["snow"] == 0 and _hud._season_label == "Outono", "outono: %d árvores de outono, HUD \"%s\"" % [v["autumn"], _hud._season_label])
	# Foto de uma árvore de outono: entra na Goblopédia.
	await _dev("/dev/pedia", {"action": "reset"}, "")
	await dev_give("camera", 1)
	_session.equip("camera")
	var tree := {}
	for o: Dictionary in _data.objects_near(_player.global_position, 25.0):
		if _vegetation.season_entry(o) == "tree_autumn":
			tree = o
			break
	if not tree.is_empty():
		var p: Vector3 = tree["pos"]
		var up := p.normalized()
		var away := (_player.global_position - p)
		away = (away - up * away.dot(up)).normalized()
		await _teleport(p + away * 7.0)
		_photo.enter()
		_aim_at(p + up * 2.0)
		await get_tree().create_timer(0.5).timeout
		var reg := await _photo.take_photo()
		_photo.exit()
		var got: Array = reg.map(func(r: Dictionary) -> String: return str(r["entry"]))
		check.call("tree_autumn" in got, "foto de árvore de outono na Goblopédia: %s" % str(got))
	else:
		check.call(false, "achar uma árvore de outono perto")
	# Inverno forçado no modo dev: a árvore com neve também entra (o servidor usa a mesma data).
	await dev_force_season("winter")
	_vegetation.load_now(_player.global_position)
	await settle.call()
	var snowy := {}
	for o: Dictionary in _data.objects_near(_player.global_position, 25.0):
		if _vegetation.season_entry(o) == "tree_snow":
			snowy = o
			break
	if not snowy.is_empty():
		var sp: Vector3 = snowy["pos"]
		var sup := sp.normalized()
		var side := sup.cross(Vector3.UP).normalized()
		await _teleport(sp + side * 7.0)
		_photo.enter()
		_aim_at(sp + sup * 2.0)
		await get_tree().create_timer(0.5).timeout
		var reg_s := await _photo.take_photo()
		_photo.exit()
		var got_s: Array = reg_s.map(func(r: Dictionary) -> String: return str(r["entry"]))
		check.call("tree_snow" in got_s, "foto de árvore com neve (inverno forçado no modo dev) na Goblopédia: %s" % str(got_s))
	else:
		check.call(false, "achar uma árvore com neve perto")
	# Sul: com o norte no inverno, a Argentina está no verão (sem neve, sem outono).
	await dev_force_season("winter")
	await teleport_exact(-34.6, -60.5)
	_vegetation.load_now(_player.global_position)
	await settle.call()
	check.call(_hud._season_label == "Verão", "Argentina no inverno do norte: \"%s\"" % _hud._season_label)
	# Trópicos: Manaus não tem estação.
	await teleport_exact(-3.1, -60.0)
	_vegetation.load_now(_player.global_position)
	await settle.call()
	v = variants.call()
	check.call(_hud._season_label == "" and v["snow"] == 0, "Manaus sem estação (HUD \"%s\", %d com neve)" % [_hud._season_label, v["snow"]])
	# Volta para a data real: fim de outubro = outono no norte.
	await dev_force_season("real")
	await teleport_exact(50.5, 10.0)
	await settle.call()
	var real := Seasons.season_at(season_now(), 50.5)
	check.call(_hud._season_label == Seasons.LABELS[real], "data real na Alemanha: %s (HUD \"%s\")" % [real, _hud._season_label])
	print("Goblo: season-test %s" % ("tudo certo" if fails.is_empty() else "%d falhas" % fails.size()))
	get_tree().quit(1 if not fails.is_empty() else 0)


## Passaportes e viagem: a barreira segura quem não tem passaporte, o passaporte libera e
## carimba, o balcão do aeroporto abre as viagens e o avião leva até o destino.
func _travel_test() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: travel-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	var r := await _api.request("POST", "/dev/passport", {"action": "reset"})
	_session.set_passport_book(r["data"])
	var walk_west := func(seconds: float) -> void:
		_player.autopilot = true
		_player.auto_run = true
		var t := 0.0
		while t < seconds:
			var up := _player.global_position.normalized()
			_player.auto_wish = up.cross(Vector3.UP).normalized()
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		_player.autopilot = false
	check.call(_session.passports() == ["BRA"], "começa só com o passaporte do Brasil: %s" % str(_session.passports()))
	await teleport_exact(-25.50, -54.35)
	await get_tree().create_timer(0.5).timeout
	_barrier_msg_at = -10.0
	await walk_west.call(6.0)
	await get_tree().create_timer(0.3).timeout
	check.call(_tracker.current == "BRA" and _barrier_msg_at > 0.0, "sem passaporte, a fronteira segura (país: %s, aviso: %s)" % [_tracker.current, _barrier_msg_at > 0.0])
	r = await _api.request("POST", "/dev/passport", {"action": "give", "country": "PRY"})
	_session.set_passport_book(r["data"])
	var coins := _session.coins
	await walk_west.call(4.0)
	await get_tree().create_timer(1.0).timeout
	check.call(_tracker.current == "PRY" and _session.stamped("PRY") and _session.coins > coins, "com passaporte, entra no Paraguai e ganha carimbo (%s, %d → %d gobolares)" % [_tracker.current, coins, _session.coins])
	# Aeroporto do Brasil: o balcão abre as viagens.
	var bra := _airports.of_country("BRA")
	check.call(not bra.is_empty(), "aeroporto do Brasil (%s)" % bra.get("name", "?"))
	await _teleport(_airports.arrival_point(bra))
	await get_tree().create_timer(1.5).timeout
	_interaction._timer = 0.0
	await get_tree().create_timer(0.2).timeout
	check.call(_interaction.target.get("type", "") in ["airport", "npc"], "E no balcão do aeroporto (%s)" % _interaction._prompt_text(_interaction.target))
	await _interaction.interact()
	await get_tree().create_timer(0.5).timeout
	# A atendente pergunta o destino: "Ver destinos".
	if _ui.dialog.is_open():
		_dialog_choose(0)
	await get_tree().create_timer(1.0).timeout
	var quotes: Array = _ui.travel._quotes
	check.call(_ui.travel.visible and quotes.size() > 100, "balcão com %d destinos" % quotes.size())
	var arg := {}
	for q: Dictionary in quotes:
		if q["country"] == "ARG":
			arg = q
	_ui.close_windows()
	await _dev("/dev/coins", {"amount": 500}, "")
	coins = _session.coins
	await travel(bra, arg, true)
	await get_tree().create_timer(1.0).timeout
	var paid := int(arg["fare"]) + int(arg["passport_price"])
	var reward := coins - paid
	check.call(not _flying and _player.is_physics_processing() and _tracker.current == "ARG", "viagem de avião até a Argentina (%s)" % _tracker.current)
	check.call(_session.has_passport("ARG") and _session.stamped("ARG") and _session.coins > reward - 1 and _session.coins < coins,
		"passaporte da Argentina comprado junto e carimbo na chegada (%d → %d gobolares, passagem + passaporte %d)" % [coins, _session.coins, paid])
	_ui.passport.toggle()
	await get_tree().create_timer(0.8).timeout
	check.call(_ui.passport._grid.get_child_count() >= 2, "livro do passaporte com %d carimbos" % _ui.passport._grid.get_child_count())
	_ui.close_windows()
	print("Goblo: travel-test %s" % ("tudo certo" if fails.is_empty() else "%d falhas" % fails.size()))
	get_tree().quit(1 if not fails.is_empty() else 0)


## Multidão (fase 3): quanto custa por quadro (CPU) ter 0, 10, 20 e 40 bots por perto.
func _crowd_test() -> void:
	Engine.max_fps = 0
	var measure := func() -> float:
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while frames < 240:
			await get_tree().process_frame
			frames += 1
		return (Time.get_ticks_usec() - t0) / 1000.0 / frames
	await get_tree().create_timer(2.0).timeout
	var base: float = await measure.call()
	print("Goblo: crowd-test   0 jogadores: %.2f ms por quadro" % base)
	var made := 0
	for target in [10, 20, 40]:
		await dev_bots(target - made)
		made = target
		await get_tree().create_timer(3.0).timeout
		var ms: float = await measure.call()
		print("Goblo: crowd-test %3d bots criados (%d visíveis): %.2f ms por quadro (+%.3f ms por jogador)" % [
			target, _remotes.visible_count, ms, (ms - base) / maxf(1.0, _remotes.visible_count)])
	await dev_bots(0)
	get_tree().quit(0)


## CPU por script (fase 4.1): mede o quadro com tudo e depois com o _process (e o
## _physics_process) de cada script desligado, um por vez. Com --bots=N, cria bots antes.
func _cpu_test() -> void:
	Engine.max_fps = 0
	if _args.has("bots"):
		await dev_bots(int(_args["bots"]))
	var measure := func() -> float:
		await get_tree().create_timer(0.5).timeout
		var frames := 0
		var t0 := Time.get_ticks_usec()
		while frames < 240:
			await get_tree().process_frame
			frames += 1
		return (Time.get_ticks_usec() - t0) / 1000.0 / frames
	await get_tree().create_timer(3.0).timeout
	var groups := {}  # script → [nós]
	for n: Node in get_tree().root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc == null or not (n.is_processing() or n.is_physics_processing()):
			continue
		var key := sc.resource_path.get_file()
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(n)
	var base: float = await measure.call()
	print("Goblo: cpu-test tudo ligado: %.2f ms por quadro" % base)
	for key: String in groups:
		var list: Array = groups[key]
		var states := []
		for n: Node in list:
			states.append([n.is_processing(), n.is_physics_processing()])
			n.set_process(false)
			n.set_physics_process(false)
		var ms: float = await measure.call()
		for i in list.size():
			if is_instance_valid(list[i]):
				(list[i] as Node).set_process(states[i][0])
				(list[i] as Node).set_physics_process(states[i][1])
		print("Goblo: cpu-test   sem %s (%d nós): %.2f ms (−%.2f)" % [key, list.size(), ms, base - ms])
	get_tree().quit(0)


## Dois clientes (fase 3): cada um vê o outro, o chat chega e o movimento aparece liso.
func _mp_test() -> void:
	var role := str(_args["mp-test"])
	var peer := str(_args.get("peer", ""))
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: mp-test[%s] %s %s" % [role, "ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	var heard := []
	_net.chat_received.connect(func(_id: int, nick: String, text: String) -> void:
		if nick == peer:
			heard.append(text))
	var find_peer := func() -> int:
		for id: int in _remotes.ids():
			if str(_remotes.info(id).get("nick", "")) == peer:
				return id
		return -1
	var t := 0.0
	while find_peer.call() < 0 and t < 40.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	var pid: int = find_peer.call()
	check.call(pid >= 0, "vê %s (em %.1f s, conexão %s)" % [peer, t, _net.state])
	if pid < 0:
		get_tree().quit(1)
		return
	if role == "b":
		await get_tree().create_timer(1.0).timeout
		_net.send_json({"t": "chat", "text": "oi do b"})
		Input.action_press("move_forward")
		await get_tree().create_timer(2.5).timeout
		Input.action_release("move_forward")
		t = 0.0
		while not heard.has("oi do a") and t < 30.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		check.call(heard.has("oi do a"), "chat de %s chegou: %s" % [peer, str(heard)])
		# Fica mais um pouco para o a terminar.
		await get_tree().create_timer(2.0).timeout
	else:
		t = 0.0
		while not heard.has("oi do b") and t < 30.0:
			await get_tree().create_timer(0.1).timeout
			t += 0.1
		check.call(heard.has("oi do b"), "chat de %s chegou: %s" % [peer, str(heard)])
		# O b anda logo depois de falar: a posição desenhada acompanha, sem saltos.
		var start := _remotes.position_of(pid)
		var biggest := 0.0
		var last := start
		for i in 60:
			await get_tree().process_frame
			await get_tree().create_timer(0.05).timeout
			var p := _remotes.position_of(pid)
			biggest = maxf(biggest, p.distance_to(last))
			last = p
		var moved := start.distance_to(last)
		check.call(moved > 3.0 and biggest < 2.0, "%s andou %.1f unidades na tela, maior salto entre quadros %.2f" % [peer, moved, biggest])
		_net.send_json({"t": "chat", "text": "oi do a"})
		await get_tree().create_timer(3.0).timeout
	print("Goblo: mp-test[%s] %s" % [role, "tudo certo" if fails.is_empty() else "%d falhas" % fails.size()])
	get_tree().quit(1 if not fails.is_empty() else 0)


## Travadas (fase 2.6): passeio pelos momentos que podem travar, com o registro ligado.
## No headless mede só a CPU; com janela (tools/sem_foco.sh), entra a compilação de shader.
func _hitch_test() -> void:
	var start_total := HitchLog.total
	var marks: Array = []
	var run := func(seconds: float, turn: float) -> void:
		_player.autopilot = true
		_player.auto_run = true
		var t := 0.0
		var heading := -_player.global_basis.z
		while t < seconds:
			var up := _player.global_position.normalized()
			heading = (heading - up * heading.dot(up)).normalized().rotated(up, turn * get_physics_process_delta_time())
			_player.auto_wish = heading
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		_player.autopilot = false
	var step := func(what: String) -> void:
		if not marks.is_empty():
			marks[-1].append_array([HitchLog.worst_ms, HitchLog.over_33, HitchLog.frames])
		HitchLog.reset_stats()
		marks.append([what, HitchLog.total])
		print("Goblo: hitch-test → %s" % what)
	if str(_args.get("hitch-test", "")) == "walk":
		# Só as etapas andando (fase 4.2: iterar nas travadas de carregar pedaços).
		await _hitch_walk(step, run, marks, start_total)
		return
	await step.call("correndo perto de casa")
	await run.call(8.0, 0.15)
	await step.call("câmera afastada até o globo e de volta")
	_camera.zoom = 1.0
	await get_tree().create_timer(3.0).timeout
	_camera.zoom = 0.18
	await get_tree().create_timer(2.5).timeout
	await step.call("Alemanha (floresta, estação)")
	await teleport_exact(50.5, 10.0)
	await run.call(8.0, -0.1)
	await step.call("pampa com animais")
	await teleport_exact(-34.6, -60.5)
	await run.call(8.0, 0.2)
	await step.call("modo foto e selfie")
	await dev_give("camera", 1)
	_session.equip("camera")
	await get_tree().create_timer(0.3).timeout
	_photo.enter()
	await get_tree().create_timer(1.0).timeout
	_photo.set_selfie(true)
	await get_tree().create_timer(1.0).timeout
	_photo.exit()
	await step.call("voo até o Japão")
	await dev_travel("JPN")
	await run.call(5.0, 0.1)
	await step.call("casa (H)")
	await go_home()
	await run.call(5.0, -0.2)
	await step.call("inverno forçado e volta")
	await dev_force_season("winter")
	await get_tree().create_timer(2.0).timeout
	await dev_force_season("real")
	await get_tree().create_timer(2.0).timeout
	await _hitch_walk(step, run, marks, start_total)


## Fase 4.2: andando normalmente (sem teleporte), carregando pedaços novos: a meta é o pior
## quadro abaixo de 33 ms. Primeiro espera o mundo em volta assentar.
func _hitch_walk(step: Callable, run: Callable, marks: Array, start_total: int) -> void:
	await teleport_exact(-3.0, -60.0)
	await get_tree().create_timer(3.0).timeout
	await step.call("andando 40 s na floresta tropical")
	await run.call(40.0, 0.05)
	await step.call("teleporte para o pampa")
	await teleport_exact(-34.6, -60.5)
	await get_tree().create_timer(3.0).timeout
	await step.call("andando 30 s no pampa")
	await run.call(30.0, -0.04)
	await step.call("fim")
	marks[-1] = ["fim", HitchLog.total]
	print("Goblo: hitch-test travadas por etapa (acima de 25 ms · pior quadro · acima de 33 ms):")
	for i in marks.size() - 1:
		print("Goblo: hitch-test   %-40s %3d · %6.1f ms · %d de %d quadros" % [marks[i][0], int(marks[i + 1][1]) - int(marks[i][1]),
			float(marks[i][2]), int(marks[i][3]), int(marks[i][4])])
	var worst := 0.0
	for e: Dictionary in HitchLog.recent:
		worst = maxf(worst, float(e["ms"]))
	print("Goblo: hitch-test %d travadas no total (pior das últimas %d: %.0f ms); detalhes em %s" % [
		HitchLog.total - start_total, HitchLog.recent.size(), worst, ProjectSettings.globalize_path(HitchLog.LOG_FILE)])
	get_tree().quit(0)


## Cursor (fase 2.6): finge a janela na frente e a captura ligada, passa por todos os fluxos
## que mexem no cursor e confere que, no fim de cada um, o cursor volta a ser capturado e o
## movimento do mouse gira a câmera, sem clique.
func _cursor_test() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: cursor-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	_ui.assume_focus = true
	_ui.mouse_capture = true
	var frames := func(n: int) -> void:
		for i in n:
			await get_tree().process_frame
	# O mouse gira a câmera? (movimento de 60 px, como o de uma pessoa)
	var turns := func() -> bool:
		var before := _camera._heading
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(60, 0)
		Input.parse_input_event(ev)
		await get_tree().process_frame
		await get_tree().process_frame
		return _camera._heading.angle_to(before) > 0.01
	var back := func(what: String) -> void:
		await frames.call(2)
		var t: bool = await turns.call()
		check.call(_ui.cursor_captured and t, "%s: cursor capturado (%s) e mouse gira a câmera (%s)" % [what, _ui.cursor_captured, t])
	await back.call("começo do jogo")
	# Menu: solta; fechar devolve.
	_ui.inventory.toggle()
	await frames.call(2)
	check.call(not _ui.cursor_captured, "bolso aberto solta o cursor")
	_ui.close_windows()
	await back.call("fechar o bolso")
	# Esc solta de propósito; um clique captura de novo.
	_ui.release_mouse()
	await frames.call(2)
	check.call(not _ui.cursor_captured, "Esc solta o cursor")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(click)
	var up := click.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	await back.call("clique depois do Esc")
	# Voo: balcão aberto com o foco no campo de busca, clique duplo num destino (o botão
	# ainda segurado quando a janela fecha).
	await dev_coins(2000)
	var bra := _airports.of_country("BRA")
	await _teleport(_airports.arrival_point(bra))
	await back.call("teleporte até o aeroporto")
	_ui.travel.open(bra)
	await get_tree().create_timer(1.0).timeout
	_ui.travel._search.grab_focus()
	_ui.travel._search.text = "chile"
	_ui.travel._fill()
	await frames.call(2)
	check.call(not _ui.cursor_captured, "balcão aberto solta o cursor")
	_ui.travel._list.select(0)
	_ui.travel._show()
	var press := click.duplicate() as InputEventMouseButton
	Input.parse_input_event(press)
	var flight := _ui.travel._travel
	flight.call()
	await frames.call(3)
	Input.parse_input_event(up)
	while not _flying:
		await get_tree().process_frame
	while _flying:
		await get_tree().process_frame
	await back.call("fim do voo (%s)" % _tracker.current)
	# Casa (H).
	await go_home()
	await back.call("tecla H")
	# Teleporte do modo dev: painel aberto com o foco num campo de número.
	_ui.dev.toggle()
	_ui.dev._item_search.grab_focus()
	await frames.call(2)
	await teleport_lat_lon(48.5, 2.0)
	_ui.dev.toggle()
	await back.call("teleporte do modo dev")
	# Aviso da fronteira e plaquinha de boas-vindas.
	_barrier_msg_at = -10.0
	await teleport_exact(-25.50, -54.35)
	_border_guard(_player.global_position, WorldData.lat_lon_to_vec(-25.45, -54.85) * world.surface_radius(_player.cell_id))
	await back.call("aviso da fronteira")
	_on_country_changed("BRA", true)
	await back.call("plaquinha de boas-vindas")
	_ui.mouse_capture = false
	print("Goblo: cursor-test %s" % ("tudo certo" if fails.is_empty() else "%d falhas" % fails.size()))
	get_tree().quit(1 if not fails.is_empty() else 0)


## Botões novos do painel dev (fase 2.5).
func _dev_test() -> void:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: dev-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	# O servidor carimba o país de casa ao nascer (e paga): espera isso antes de contar.
	await get_tree().create_timer(1.5).timeout
	var c0 := _session.coins
	await dev_coins(250)
	check.call(_session.coins == c0 + 250, "dar gobolares (%d → %d)" % [c0, _session.coins])
	await dev_coins(-100)
	check.call(_session.coins == c0 + 150, "tirar gobolares (%d)" % _session.coins)
	await dev_passport("give", "LUX")
	check.call(_session.has_passport("LUX"), "dar o passaporte de Luxemburgo")
	await dev_passport("remove", "LUX")
	check.call(not _session.has_passport("LUX"), "tirar o passaporte")
	await dev_passport("complete", "")
	check.call(_session.passports().size() > 200 and _session.stamped("JPN"), "completar o passaporte (%d)" % _session.passports().size())
	await dev_passport("reset", "")
	check.call(_session.passports().size() == 1 and not _session.stamped("JPN"), "zerar o passaporte")
	set_barrier(false)
	check.call(not barrier_on and _border_guard(Vector3.ONE, Vector3.ONE) == Vector3.ZERO, "desligar a barreira")
	set_barrier(true)
	await teleport_exact(-25.50, -54.35)
	await get_tree().create_timer(0.6).timeout
	set_border_lines(false, false)
	check.call(_border_lines._chunks.is_empty(), "esconder as linhas de fronteira")
	set_border_lines(true, true)
	check.call(not _border_lines._chunks.is_empty(), "linhas com os polígonos de debug (%d pedaços)" % _border_lines._chunks.size())
	set_border_lines(true, false)
	dev_spawn_animal("shiba")
	await get_tree().create_timer(1.0).timeout
	dev_list_animals()
	check.call(_ui.dev._status.text.contains("Shiba"), "criar e listar animais: %s" % _ui.dev._status.text.split("\n")[0])
	await dev_pedia("complete")
	var r := await _api.request("GET", "/pedia")
	var all_found: bool = r["ok"] and (r["data"]["entries"] as Array).all(func(e: Dictionary) -> bool: return bool(e["discovered"]))
	check.call(all_found, "completar a Goblopédia")
	await dev_pedia("reset")
	r = await _api.request("GET", "/pedia")
	check.call(r["ok"] and (r["data"]["entries"] as Array).all(func(e: Dictionary) -> bool: return not bool(e["discovered"])), "zerar a Goblopédia")
	await dev_travel("JPN")
	await get_tree().create_timer(1.0).timeout
	check.call(_tracker.current == "JPN" and not _flying, "voar de graça para o Japão (%s)" % _tracker.current)
	print("Goblo: dev-test %s" % ("tudo certo" if fails.is_empty() else "%d falhas" % fails.size()))
	get_tree().quit(1 if not fails.is_empty() else 0)


## Ponto do chão (topo plano da célula) na lat/lon exata, não no centro do hexágono.
func ground_at(lat: float, lon: float) -> Vector3:
	var dir := WorldData.lat_lon_to_vec(lat, lon)
	var cell := world.find_cell(dir)
	return dir * (world.surface_radius(cell) / dir.dot(world.centers[cell]))


func teleport_exact(lat: float, lon: float) -> void:
	await _teleport(ground_at(lat, lon))


## Fronteiras: país exato em pontos conhecidos (os mesmos do teste em Go), linha no chão perto
## da tríplice fronteira e uma caminhada que cruza do Brasil para o Paraguai.
func _border_test() -> void:
	var fails := 0
	var points := [
		[-25.50, -54.35, "BRA"], [-25.45, -54.85, "PRY"], [-25.85, -54.40, "ARG"],
		[-19.05, -57.40, "BRA"], [-18.95, -57.95, "BOL"], [-4.30, -69.70, "BRA"], [-4.00, -69.95, "COL"],
		[48.55, 7.45, "FRA"], [48.55, 8.10, "DEU"], [49.70, 6.10, "LUX"], [42.55, 1.57, "AND"],
	]
	for p: Array in points:
		await teleport_exact(p[0], p[1])
		await get_tree().create_timer(0.3).timeout
		var got := _tracker.exact_at(_player.global_position, _player.cell_id)
		var ok: bool = got == p[2]
		if not ok:
			fails += 1
		print("Goblo: border-test %s (%.2f, %.2f): %s, esperado %s (HUD: %s)" % ["ok   " if ok else "FALHOU", p[0], p[1], got, p[2], _tracker.current])
	await teleport_exact(-25.50, -54.35)
	await get_tree().create_timer(0.5).timeout
	var lines := _border_lines.get_child_count()
	print("Goblo: border-test %s linhas de fronteira montadas em %d pedaços" % ["ok   " if lines > 0 else "FALHOU", lines])
	if lines == 0:
		fails += 1
	# Anda para o oeste até mudar de país (sem a barreira do passaporte: aqui o teste é a
	# detecção; a barreira tem o --travel-test).
	barrier_on = false
	var changes: Array = []
	var on_change := func(code: String, walked: bool) -> void: changes.append([code, walked])
	_tracker.country_changed.connect(on_change)
	_player.autopilot = true
	_player.auto_run = true
	var t := 0.0
	while t < 20.0 and changes.is_empty():
		var up := _player.global_position.normalized()
		var west := up.cross(Vector3.UP).normalized()
		_player.auto_wish = west
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_player.autopilot = false
	_tracker.country_changed.disconnect(on_change)
	var crossed: bool = not changes.is_empty() and changes[0][1]
	print("Goblo: border-test %s andando para o oeste: %s em %.1f s" % ["ok   " if crossed else "FALHOU", str(changes), t])
	if not crossed:
		fails += 1
	fails += await _border_live_test()
	print("Goblo: border-test %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Fronteira viva (fase 3): peças montadas, fechada sem passaporte, onda ao encostar, abre
## animando ao ganhar o passaporte, visão do modo dev e nenhuma travada andando ao longo
## dela. Devolve o número de falhas.
func _border_live_test() -> int:
	var fails: Array = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: border-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	const PAIR := "BRA|PRY"
	await dev_passport("reset", "")
	barrier_on = true
	await teleport_exact(-25.50, -54.35)
	for i in 30:
		await get_tree().process_frame
	# Peças do par Brasil–Paraguai.
	var meshes := 0
	var markers := 0
	for chunk in _border_lines.get_children():
		for g in chunk.get_children():
			if str(g.get_meta("pair", "")) != PAIR:
				continue
			for c in g.get_children():
				if c is MeshInstance3D:
					meshes += 1
				elif c is MultiMeshInstance3D:
					markers = maxi(markers, (c as MultiMeshInstance3D).multimesh.instance_count)
	check.call(meshes >= 3 and markers >= 2, "cortina, faixa e bandeirolas (%d malhas) e %d marcos no par %s" % [meshes, markers, PAIR])
	# Bandeirinhas (fase 3.6): de cada lado do marco, a bandeira do país do outro lado. A
	# face da frente é vista do lado +x do marco; ela mostra o país do lado -x.
	var flags_ok := 0
	var flags_bad := 0
	for chunk in _border_lines.get_children():
		for g in chunk.get_children():
			if str(g.get_meta("pair", "")) != PAIR or not g.has_node("Flags"):
				continue
			var fl := g.get_node("Flags") as MultiMeshInstance3D
			var fl_markers: Array = fl.get_meta("markers", [])
			var fl_codes: Array = fl.get_meta("codes", [])
			for i in fl_markers.size():
				var xf: Transform3D = fl_markers[i]
				var plus := xf.origin + xf.basis.x.normalized() * 1.5
				var minus := xf.origin - xf.basis.x.normalized() * 1.5
				var c_plus := _data.borders.country_at(plus, world.find_cell(plus, _player.cell_id))
				var c_minus := _data.borders.country_at(minus, world.find_cell(minus, _player.cell_id))
				if c_plus == c_minus or c_plus in ["", "?"] or c_minus in ["", "?"]:
					continue  # marco numa curva fechada: o teste de 1,5 unidade não diz nada
				# A face da frente (vista do lado +x) mostra codes[i][1], o país do lado -x.
				if str(fl_codes[i][0]) == c_plus and str(fl_codes[i][1]) == c_minus:
					flags_ok += 1
				else:
					flags_bad += 1
	check.call(flags_ok >= 2 and flags_bad == 0, "bandeirinhas com o país do outro lado (%d certas, %d trocadas)" % [flags_ok, flags_bad])
	check.call(is_zero_approx(_border_lines.openness(PAIR)), "sem o passaporte do Paraguai, fechada (%.2f)" % _border_lines.openness(PAIR))
	# Encostar: anda para o oeste com a barreira e a cortina faz a onda.
	var rippled := false
	_player.autopilot = true
	var t := 0.0
	while t < 4.0 and not rippled:
		var up := _player.global_position.normalized()
		_player.auto_wish = up.cross(Vector3.UP).normalized()
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		rippled = float(_border_lines._pairs.get(PAIR, {}).get("ripple", -1.0)) >= 0.0
	_player.autopilot = false
	check.call(rippled and _tracker.current == "BRA", "ao encostar, a cortina faz a onda (e segura: %s)" % _tracker.current)
	# Ganhou o passaporte: abre animando.
	await dev_passport("give", "PRY")
	await get_tree().create_timer(0.5).timeout
	var mid := _border_lines.openness(PAIR)
	await get_tree().create_timer(1.6).timeout
	check.call(mid > 0.05 and mid < 0.95 and is_equal_approx(_border_lines.openness(PAIR), 1.0),
		"com o passaporte, abre com animação (%.2f no meio, %.2f no fim)" % [mid, _border_lines.openness(PAIR)])
	set_border_view("closed")
	await get_tree().create_timer(1.8).timeout
	check.call(is_zero_approx(_border_lines.openness(PAIR)), "modo dev: todas fechadas")
	set_border_view("")
	await get_tree().create_timer(1.8).timeout
	# Desempenho: 20 s andando ao longo da fronteira (sem limite de fps, para medir só o
	# trabalho de cada quadro), contando os quadros acima de 25 ms.
	var fps_before := Engine.max_fps
	Engine.max_fps = 0
	var hitches_before := HitchLog.total
	var worst := 0.0
	# Trabalho do jogo por quadro (FrameWork): as pausas que o macOS dá em programas headless
	# de fundo (~46 ms a cada ~3,6 s, até num loop vazio) não contam como travada do jogo.
	FrameWork.attach(self)
	# Linha de base: 10 s parado, nas mesmas condições (mostra quantas pausas o sistema dá).
	var base := 0
	t = 0.0
	while t < 10.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if FrameWork.last_ms > HitchLog.LIMIT_MS:
			base += 1
	var heavy := 0
	var worst_work := 0.0
	hitches_before = HitchLog.total
	_player.autopilot = true
	_player.auto_run = true
	t = 0.0
	while t < 20.0:
		var pos := _player.global_position
		var up := pos.normalized()
		var north := (Vector3.UP - up * up.dot(Vector3.UP)).normalized()
		var wish := north
		var bn := _data.borders.border_normal(pos, _player.cell_id, world.surface_radius(_player.cell_id), "PRY")
		if not bn.is_empty() and (bn["normal"] as Vector3) != Vector3.ZERO:
			var n: Vector3 = bn["normal"]
			var tangent := up.cross(n).normalized()
			if tangent.dot(north) < 0.0:
				tangent = -tangent
			# Fica a uns 2 unidades da linha, do lado brasileiro.
			wish = (tangent + n * clampf(float(bn["dist"]) - 2.0, -1.0, 1.0) * 0.6).normalized()
		_player.auto_wish = wish
		await get_tree().process_frame
		t += get_process_delta_time()
		worst_work = maxf(worst_work, FrameWork.last_ms)
		if FrameWork.last_ms > HitchLog.LIMIT_MS:
			heavy += 1
	_player.autopilot = false
	Engine.max_fps = fps_before
	var n_hitch := HitchLog.total - hitches_before
	for e: Dictionary in HitchLog.recent.slice(maxi(0, HitchLog.recent.size() - n_hitch)):
		worst = maxf(worst, float(e["ms"]))
	var ll := WorldData.vec_to_lat_lon(_player.global_position)
	# Andando, no máximo o dobro das pausas de quem está parado (+1), e nada absurdo.
	check.call(heavy <= base * 4 + 2 and worst_work < 100.0, "20 s andando ao longo da fronteira (até %s): %d quadros com mais de 25 ms de trabalho (pior %.1f ms); parado 10 s: %d (pausas do sistema); entre quadros: %d acima de 25 ms, pior %.0f ms" % [
		WorldData.format_lat_lon(ll.x, ll.y), heavy, worst_work, base, n_hitch, worst])
	if heavy > 0:
		for e: Dictionary in HitchLog.recent.slice(maxi(0, HitchLog.recent.size() - n_hitch)):
			print("Goblo: border-test   travada %.0f ms: %s" % [e["ms"], "; ".join(e["what"])])
	return fails.size()


## A câmera só muda de distância quando o jogador mexe: encosta o personagem em casas
## (vizinhos falsos) e em árvores da floresta, gira a câmera 360° e confere, a cada passo,
## que a distância continua a do zoom, que a câmera não está abaixo do chão e que tudo o
## que fica entre ela e o personagem (ou em volta dela) está transparente.
func _camera_test() -> void:
	var fails: Array[String] = []
	var space := get_world_3d().direct_space_state
	var terrain_body: StaticBody3D = _terrain.get("_body")
	var spin_and_check := func(label: String) -> void:
		var bad := 0
		var blocked := 0
		var pitch_before := _camera.pitch_degrees
		for step in 24:
			_camera._turn(TAU / 24.0)
			await get_tree().create_timer(0.35).timeout
			var cam := _camera.global_position
			var up := _player.global_position.normalized()
			var head := _player.global_position + up * 0.6
			var cell := world.find_cell(cam)
			var problem := ""
			if absf(cam.distance_to(head) - _camera.distance) > _camera.distance * 0.02:
				problem = "distância mudou sozinha (%.2f, zoom pede %.2f)" % [cam.distance_to(head), _camera.distance]
			elif cam.length() < world.surface_radius(cell) + 0.05:
				problem = "abaixo do chão"
			else:
				# Algo no caminho (ou a câmera dentro de algo) precisa estar desbotado.
				var q := PhysicsRayQueryParameters3D.create(head, cam)
				q.exclude = [_player.get_rid(), terrain_body.get_rid()]
				q.hit_from_inside = true
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					blocked += 1
					if _occlusion.faded_count() == 0 or _occlusion.min_alpha() > CameraOcclusion.ALPHA + 0.05:
						problem = "%s na frente sem transparência" % str(hit["collider"])
			if not problem.is_empty():
				bad += 1
				print("Goblo: camera-test   %s" % problem)
		if not is_equal_approx(_camera.pitch_degrees, pitch_before):
			bad += 1
			print("Goblo: camera-test   o ângulo vertical mudou sozinho")
		print("Goblo: camera-test %s %s (%d de 24 posições ruins, %d com algo no caminho, %d objetos desbotados no fim)" % [
			"ok   " if bad == 0 else "FALHOU", label, bad, blocked, _occlusion.faded_count()])
		if bad > 0:
			fails.append(label)
	_camera.set_zoom_now(0.22)
	# 1) Casas: cria vizinhos e encosta o personagem do lado de fora de uma parede.
	await dev_fake_neighbors(12)
	await get_tree().create_timer(1.0).timeout
	var walls := 0
	for lot: Dictionary in _data.all_lots():
		var h: Variant = lot.get("house")
		if not (h is Dictionary) or int(h["level"]) == 0 or walls >= 3:
			continue
		var hl := _session.house_level(int(h["level"]))
		var fp := LotGeom.rotated(Vector2i(int(hl["footprint"][0]), int(hl["footprint"][1])), int(h["rot"]))
		var f := _data.frame(int(lot["cell"]))
		var pos := LotGeom.point(f, lot, _session.tile_size, int(h["x"]) + fp.x * 0.5, int(h["y"]) - 0.6, 0.2)
		await _teleport(pos)
		_player.face(LotGeom.point(f, lot, _session.tile_size, int(h["x"]) + fp.x * 0.5, int(h["y"]) - 5.0))
		_camera.snap_behind_target()  # personagem de costas para a casa: câmera do lado dela
		await _neighborhood.settle()  # lotes que chegam aos poucos e malhas juntadas em thread
		await get_tree().create_timer(0.6).timeout
		await spin_and_check.call("encostado na casa de %s" % lot.get("owner", "?"))
		if walls == 0 and _args.has("screenshot"):
			# Fotos: casa entre a câmera e o personagem (pontilhada) e câmera dentro dela.
			var base := str(_args["screenshot"]).get_basename()
			_camera.snap_behind_target()  # personagem de costas para a casa: casa no meio
			_camera.pitch_degrees = 22.0
			_camera.set_zoom_now(0.0)
			await get_tree().create_timer(0.8).timeout
			await _save_shot(base + "_dentro.png")  # câmera dentro da casa: ela some
			_camera.set_zoom_now(0.15)
			await get_tree().create_timer(0.8).timeout
			await _save_shot(base + "_casa.png")  # casa pontilhada na frente do personagem
			_camera.pitch_degrees = 50.0
			await get_tree().create_timer(0.8).timeout
			await _save_shot(base + "_telhado.png")  # telhado entre a câmera e o personagem
			_camera.pitch_degrees = 28.0
			_camera.set_zoom_now(0.22)
		walls += 1
	if walls == 0:
		fails.append("nenhuma casa por perto")
	# 2) Floresta tropical densa: encosta numa árvore e gira.
	await _teleport(world.centers[world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(-3.0, -60.0)))] * world.surface_radius(world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(-3.0, -60.0)))))
	await get_tree().create_timer(0.5).timeout
	for o: Dictionary in _data.objects_near(_player.global_position, 30.0):
		if o["kind"] == "tree":
			var up: Vector3 = o["up"]
			var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
			await _teleport((o["pos"] as Vector3) + side * 0.6 + up * 0.2)
			break
	await get_tree().create_timer(0.6).timeout
	await spin_and_check.call("na floresta tropical, colado numa árvore")
	if _args.has("screenshot"):
		# Foto de baixo, com copas entre a câmera e o personagem (ficam transparentes).
		_camera.pitch_degrees = 12.0
		_camera.set_zoom_now(0.32)
		for i in 24:
			_camera._turn(TAU / 24.0)
			await get_tree().create_timer(0.15).timeout
			if _occlusion.faded_count() > 0:
				break
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(_args["screenshot"]))
		print("Goblo: camera-test foto com %d objetos desbotados" % _occlusion.faded_count())
	print("Goblo: camera-test %s (%d falhas)" % ["OK" if fails.is_empty() else "FALHOU", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)


## Salva um PNG da tela agora (testes).
func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Goblo: foto %s (%d objetos desbotados, opacidade mínima %.2f, câmera a %.2f)" % [
		path, _occlusion.faded_count(), _occlusion.min_alpha(), _camera.distance])


## Piloto automático até --route=LAT,LON. Segue o grande círculo; se ficar preso (árvore,
## degrau alto, costa), pula e depois desvia um pouco para o lado.
func _route_test() -> void:
	var parts := str(_args["route"]).split(",")
	var target := WorldData.lat_lon_to_vec(float(parts[0]), float(parts[1]))
	var target_cell := world.find_cell(target)
	var start := _player.global_position
	_player.autopilot = true
	_player.auto_run = _args.has("run")
	var elapsed := 0.0
	var stuck := 0.0
	var detour := 0.0
	var detour_sign := 1.0
	var limit := float(_args.get("limit", 600.0))
	var last := _player.global_position
	var path_len := 0.0
	await get_tree().physics_frame
	while elapsed < limit:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		var pos := _player.global_position
		path_len += pos.distance_to(last)
		last = pos
		var up := pos.normalized()
		if up.angle_to(target) * world.radius < 12.0 or _player.cell_id == target_cell:
			break
		var dir := target - up * target.dot(up)
		dir = dir.normalized()
		var speed := (_player.get_real_velocity() - up * _player.get_real_velocity().dot(up)).length()
		stuck = stuck + dt if speed < _player.walk_speed * 0.3 else 0.0
		if stuck > 0.25:
			_player.request_jump()
		if stuck > 0.8:
			detour = 1.2
			detour_sign = -detour_sign
			stuck = 0.0
		if detour > 0.0:
			detour -= dt
			dir = dir.rotated(up, detour_sign * deg_to_rad(70.0))
		_player.auto_wish = dir
	_player.autopilot = false
	var straight := start.normalized().angle_to(target) * world.radius
	print("Goblo: rota %s → %s: %.1f s (%s), caminho %.0f u, linha reta %.0f u, pulos %d, %s" % [
		WorldData.format_lat_lon(spawn_lat, spawn_lon), str(_args["route"]), elapsed,
		"correndo" if _args.has("run") else "andando", path_len, straight, _player.jumps,
		"chegou" if elapsed < limit else "NÃO chegou"])
	get_tree().quit(0 if elapsed < limit else 1)


## Mede fps andando pela região por --perf-test=SEG segundos (depois de 3 s de aquecimento).
func _perf_test() -> void:
	var seconds := float(_args["perf-test"])
	_player.autopilot = true
	_player.auto_run = _args.has("run")
	var heading := -_player.global_basis.z
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await get_tree().create_timer(3.0).timeout
	var phys_ms := 0.0
	var gpu_ms := 0.0
	var cpu_ms := 0.0
	var times: Array[float] = []
	var draw_calls := 0.0
	var primitives := 0.0
	var t := 0.0
	var stuck := 0.0
	var turn := 0.0
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		times.append(dt)
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		var up := _player.global_position.normalized()
		heading = (heading - up * heading.dot(up)).normalized()
		var v := _player.get_real_velocity()
		stuck = stuck + dt if (v - up * v.dot(up)).length() < 1.0 else 0.0
		if stuck > 0.3:
			_player.request_jump()
			turn = 1.0
			stuck = 0.0
		if turn > 0.0:
			turn -= dt
			heading = heading.rotated(up, dt * 1.5)
		_player.auto_wish = heading
	_player.autopilot = false
	times.sort()
	var total := 0.0
	for x in times:
		total += x
	var n := times.size()
	var worst := times.slice(int(n * 0.99))
	var worst_avg := 0.0
	for x in worst:
		worst_avg += x
	worst_avg /= maxf(1.0, worst.size())
	print("Goblo: desempenho (%s, qualidade %s): média %.1f fps, 1%% piores %.1f fps, pior quadro %.1f ms, %d draw calls, %.0f mil triângulos, %d objetos, %s" % [
		world.biome_label(_player.cell_id), Quality.current_name(), n / total, 1.0 / worst_avg, times[n - 1] * 1000.0,
		int(draw_calls / n), primitives / n / 1000.0, _vegetation.instance_count, Engine.get_version_info()["string"]])
	print("Goblo: tempo médio por quadro: física %.1f ms, render CPU %.1f ms, GPU %.1f ms; GPU: %s" % [
		phys_ms / n, cpu_ms / n, gpu_ms / n, RenderingServer.get_video_adapter_name()])
	var vp := get_viewport()
	var win := DisplayServer.window_get_size()
	print("Goblo: janela %d × %d (%s), 3D em %d%% (%d × %d, %s), interface %d%%" % [win.x, win.y,
		"tela cheia" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "janela",
		roundi(vp.scaling_3d_scale * 100.0), int(win.x * vp.scaling_3d_scale), int(win.y * vp.scaling_3d_scale),
		"FSR" if vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR else "bilinear", roundi(Quality.ui_scale() * 100.0)])
	get_tree().quit()


func _tour() -> void:
	_camera.set_zoom_now(0.12)
	_camera.spin_speed = 0.45
	await get_tree().create_timer(0.5).timeout
	Input.action_press("move_forward")
	await get_tree().create_timer(2.0).timeout
	_player.request_jump()
	await get_tree().create_timer(1.5).timeout
	Input.action_release("move_forward")
	await _zoom_to(1.0, 3.5)
	await get_tree().create_timer(3.0).timeout
	await _zoom_to(0.15, 3.5)
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _zoom_to(z: float, seconds: float) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "zoom", z, seconds)
	await tween.finished


func _parse_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	return args


func _resolve_server_url() -> String:
	var url := str(_args.get("server", ""))
	if url.is_empty():
		url = OS.get_environment("GOBLO_SERVER_URL")
	if url.is_empty():
		# Jogo exportado para um amigo: arquivo goblo-servidor.txt ao lado do executável.
		var beside := OS.get_executable_path().get_base_dir().path_join("goblo-servidor.txt")
		if OS.has_feature("template") and FileAccess.file_exists(beside):
			url = FileAccess.get_file_as_string(beside).strip_edges()
	if url.is_empty() and not _is_automation():
		var cfg := ConfigFile.new()
		if cfg.load(Quality.SETTINGS_FILE) == OK:
			url = str(cfg.get_value("network", "server_url", ""))
	if url.is_empty():
		url = str(ProjectSettings.get_setting("goblo/server_url", DEFAULT_SERVER))
	return url.trim_suffix("/")


# --- NPCs, diálogos e apresentação do guia (fase 3.5, ADR 0043) -------------------------------

## O guia da apresentação (aparece ao lado do jogador; null fora da apresentação).
var intro_guide: Npc
var _talking: Npc
var _item_of_day := ""
## Tarefa guiada em andamento ("" = nenhuma) e a seta que aponta o alvo.
var _intro_task := ""
var _intro_arrow: Node3D
var _intro_skip: Control


func _setup_dialogs() -> void:
	_ui.dialog.dialogs = _session.dialogs
	_ui.dialog.action.connect(_on_dialog_action)
	_ui.dialog.on_skip = skip_intro
	_ui.dialog.finished.connect(func() -> void:
		_talking = null
		_ui.restore_control())
	_ui.settings.on_intro = restart_intro
	_ui.settings.on_trades = set_accept_trades
	_ui.dev.fill_dialogs(_session.dialogs.keys())
	# "Pular apresentação": sempre visível enquanto a apresentação está em andamento.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.offset_top = 70
	var b := UiStyle.button("Pular apresentação  (Alt + clique)", false)
	b.pressed.connect(skip_intro)
	box.add_child(b)
	box.visible = false
	_ui.add_child(box)
	_intro_skip = box


## Conversa com um NPC: abre o diálogo dele (o guia da apresentação fala o trecho atual).
func talk(npc: Npc) -> void:
	if npc == null or _ui.dialog.is_open():
		return
	npc.face(_player.global_position)
	_talking = npc
	var id := npc.dialog
	var with_skip := false
	if npc == intro_guide:
		id = _intro_dialog()
		with_skip = true
	if npc.role == "shopkeeper":
		_item_of_day = await _shop_item_of_day(npc.country)
	open_dialog(id, npc, with_skip)


## Abre um diálogo pelo id (também pelo painel dev). `npc` dá nome, cargo e cor.
func open_dialog(id: String, npc: Npc = null, with_skip := false) -> void:
	var country := npc.country if npc else str(_session.me.get("country", ""))
	var role := npc.role if npc else "guide"
	var info: Dictionary = _session.npc_roles.get(role, {})
	_ui.dialog.vars = {"player": str(_session.me.get("nickname", "")), "country": country_name(country),
		"item_of_day": _item_of_day if not _item_of_day.is_empty() else "uma novidade",
		"currency": str(_session.currency.get("plural", "gobolares")), "slang": str(_session.currency.get("slang", "goblinhos"))}
	var who := npc.npc_name if npc else _session.npc_name(role, country)
	var title := npc.title if npc else str(info.get("title", ""))
	_ui.close_windows()
	_ui.dialog.start(id, who, title, Color(str(info.get("tint", "#ffd27f"))), with_skip)


## Um item rotativo do estoque de hoje (o lojista comenta).
func _shop_item_of_day(country: String) -> String:
	var r := await _api.request("GET", "/shop?country=" + country)
	if not r["ok"]:
		return ""
	var pick := ""
	for st: Dictionary in r["data"].get("stock", []):
		if str(st.get("kind", "")) != "fixed":
			pick = str(st.get("name", ""))
			if str(st.get("kind", "")) == "regional":
				break
	return pick.to_lower()


func _on_dialog_action(act: String, opt: Dictionary) -> void:
	var country := _talking.country if _talking else str(_session.me.get("country", ""))
	var ap := _airports.airport_of(country)
	match act:
		"open_shop":
			open_shop(country)
		"open_shop_sell":
			open_shop_sell(country)
		"open_travel":
			_ui.close_windows()
			if not ap.is_empty():
				_ui.travel.open(ap)
		"open_passports":
			_ui.close_windows()
			if not ap.is_empty():
				_ui.travel.open_passports(ap)
		"intro_task":
			_start_intro_task(str(opt.get("task", "")))
		"intro_done":
			finish_intro(false)
		"intro_restart":
			restart_intro()


## Trecho da apresentação a falar agora: o "depois" da última tarefa cumprida.
func _intro_dialog() -> String:
	var id := str(_session.intro_cfg.get("start", "intro_hello"))
	var done: Array = _session.intro.get("tasks", [])
	for t: Dictionary in _session.intro_cfg.get("tasks", []):
		if done.has(str(t["id"])):
			id = str(t["after"])
	return id


## Confere a apresentação ao entrar: conta nova vê; no modo dev e nas automações, pula.
func _check_intro() -> void:
	var r := await _api.request("GET", "/intro")
	if not r["ok"]:
		return
	_session.intro = r["data"]
	if bool(_session.intro.get("done", true)):
		return
	var forced := FileAccess.file_exists(_intro_flag())
	if forced:
		DirAccess.remove_absolute(_intro_flag())
	if (_session.dev and not forced) or _is_automation():
		await _set_intro(true)
		return
	await get_tree().create_timer(1.2).timeout
	# O editor de personagem já veio antes de entrar no mundo (fase 4.1).
	start_intro()


## Arquivo local que faz o modo dev mostrar a apresentação no próximo login.
func _intro_flag() -> String:
	return tr("user://%s_intro.flag") % _session.profile


## Modo dev: marca a apresentação como não vista (aparece no próximo login).
func dev_intro_unseen() -> void:
	await _set_intro(false)
	var f := FileAccess.open(_intro_flag(), FileAccess.WRITE)
	if f:
		f.store_string("1")
	_ui.dev.status("Apresentação marcada como não vista: aparece no próximo login.")


## Modo dev: repõe o estoque da loja do país onde o jogador está.
func dev_shop_restock() -> void:
	var c := _tracker.current if _tracker else str(_session.me.get("country", ""))
	var r := await _dev("/dev/shop/restock", {"country": c}, tr("Estoque de %s reposto.") % country_name(c))
	if r["ok"] and _ui.shop.visible:
		_ui.shop.open(c)


## Modo dev: um bot parado do lado e uma troca aberta com ele.
func dev_trade_bot() -> void:
	var r := await _dev("/dev/trade-bot", {}, "")
	if r["ok"]:
		_ui.dev.status(tr("Troca aberta com %s.") % str(r["data"]["bot"]))


func _set_intro(done: bool) -> void:
	var r := await _api.request("POST", "/intro", {"done": done})
	if r["ok"]:
		_session.intro = r["data"]


## Começa (ou retoma) a apresentação: o guia aparece ao lado do jogador e fala.
func start_intro() -> void:
	if not is_instance_valid(intro_guide):
		var country := str(_session.me.get("country", ""))
		var ap := _airports.airport_of(country)
		var gname := str((ap.get("npcs", {}) as Dictionary).get("guide", _session.npc_name("guide", country)))
		intro_guide = Npc.create("guide", _session.npc_roles.get("guide", {}), gname, country)
		add_child(intro_guide)
		var up := _player.global_position.normalized()
		var fwd := -_player.global_basis.z
		fwd = (fwd - up * fwd.dot(up)).normalized()
		var p := land_point(_player.global_position + fwd * 2.2)
		intro_guide.global_position = p.normalized() * (_terrain_height(p))
		intro_guide.face(_player.global_position)
	_intro_skip.visible = true
	_clear_intro_arrow()
	talk(intro_guide)


## Altura do chão num ponto (o topo plano da célula).
func _terrain_height(p: Vector3) -> float:
	var c := world.find_cell(p, _player.cell_id)
	return world.surface_radius(c) if c >= 0 else p.length()


## Rever a apresentação (F6, o guia da praça, modo dev): marca como não vista e começa.
func restart_intro() -> void:
	await _set_intro(false)
	start_intro()


## Pula (ou termina) a apresentação: o servidor guarda; o guia vai embora.
func skip_intro() -> void:
	finish_intro(true)


func finish_intro(skipped: bool) -> void:
	_ui.dialog.close()
	_intro_task = ""
	_clear_intro_arrow()
	_intro_skip.visible = false
	if is_instance_valid(intro_guide):
		intro_guide.queue_free()
	intro_guide = null
	await _set_intro(true)
	_ui.toast("Apresentação pulada. Dá para rever pelo F6." if skipped else "Boas aventuras no Goblo!")


## O guia pediu uma tarefa: mostra a seta em cima do alvo.
func _start_intro_task(task: String) -> void:
	_intro_task = task
	_clear_intro_arrow()
	var target := _intro_target(task)
	if target == Vector3.ZERO:
		return
	_intro_arrow = _make_arrow()
	add_child(_intro_arrow)
	_intro_arrow.global_position = target + target.normalized() * 3.2
	_intro_arrow.set_meta("base", _intro_arrow.global_position)
	_intro_arrow.global_basis = Basis.looking_at(-target.normalized(), Vector3.UP if absf(target.normalized().y) < 0.99 else Vector3.FORWARD)


## Onde a seta aponta: a árvore mais perto (sacudir) ou a bancada do lote (fabricar).
func _intro_target(task: String) -> Vector3:
	for t: Dictionary in _session.intro_cfg.get("tasks", []):
		if str(t["id"]) != task:
			continue
		if not str(t.get("recipe", "")).is_empty():
			var wbs := _interaction._own_placements("workbench")
			return wbs[0] if not wbs.is_empty() else Vector3.ZERO
		var best := Vector3.ZERO
		var best_d := INF
		for o: Dictionary in _data.objects_near(_player.global_position, 25.0):
			if str(o["kind"]) == "tree":
				var d := (o["pos"] as Vector3).distance_to(_player.global_position)
				if d < best_d:
					best_d = d
					best = o["pos"]
		return best
	return Vector3.ZERO


## Setinha amarela que balança em cima do alvo (cone apontando para baixo).
func _make_arrow() -> Node3D:
	var root := Node3D.new()
	root.name = "IntroArrow"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.38
	cone.height = 0.7
	cone.radial_segments = 8
	var stem := CylinderMesh.new()
	stem.top_radius = 0.14
	stem.bottom_radius = 0.14
	stem.height = 0.6
	stem.radial_segments = 8
	var m := _arrow_material()
	for part: Array in [[cone, Vector3(0, 0, -0.35)], [stem, Vector3(0, 0, 0.3)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = part[1]
		mi.rotation.x = -PI / 2  # o eixo do cilindro (Y) vira -Z: a ponta olha para o alvo
		root.add_child(mi)
	return root


static var _arrow_mat: StandardMaterial3D


static func _arrow_material() -> StandardMaterial3D:
	if _arrow_mat == null:
		_arrow_mat = StandardMaterial3D.new()
		_arrow_mat.albedo_color = Color("ffcf4a")
		_arrow_mat.emission_enabled = true
		_arrow_mat.emission = Color("ffb020")
		_arrow_mat.emission_energy_multiplier = 0.6
	return _arrow_mat


func _clear_intro_arrow() -> void:
	if is_instance_valid(_intro_arrow):
		_intro_arrow.queue_free()
	_intro_arrow = null


## A seta balança devagar (chamado no _process).
func _bob_intro_arrow() -> void:
	if not is_instance_valid(_intro_arrow):
		return
	var base: Vector3 = _intro_arrow.get_meta("base")
	_intro_arrow.global_position = base + base.normalized() * sin(Time.get_ticks_msec() * 0.004) * 0.25


## A resposta de uma ação (coleta, bancada) disse que uma tarefa da apresentação foi
## cumprida: paga (já pago no servidor), tira a seta e o guia comenta.
func on_intro_task(task: String, reward: int) -> void:
	if task.is_empty():
		return
	var tasks: Array = _session.intro.get("tasks", [])
	if not tasks.has(task):
		tasks.append(task)
	_session.intro["tasks"] = tasks
	if reward > 0:
		_session.set_coins(_session.coins + reward)
		_ui.toast(tr("Tarefa da apresentação!  +%s") % _session.coins_text(reward))
	if _intro_task == task:
		_intro_task = ""
		_clear_intro_arrow()
	if is_instance_valid(intro_guide):
		await get_tree().create_timer(0.8).timeout
		_ui.close_windows()
		talk(intro_guide)



# --- Teste da fase 3.5: NPCs, diálogos, apresentação, loja e troca (--npc-test) ---------------

## Completa as falas até a que tem respostas e escolhe a resposta i.
func _dialog_choose(i: int) -> void:
	var guard := 0
	while _ui.dialog.is_open() and guard < 30:
		_ui.dialog.advance()
		guard += 1
		var line: Dictionary = _ui.dialog._lines[_ui.dialog._index]
		if _ui.dialog._line_done() and not (line.get("options", []) as Array).is_empty():
			_ui.dialog.choose(i)
			return


func _npc_test() -> void:
	var fails: Array[String] = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: npc-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	check.call(_session.dev, "servidor em modo dev")
	await get_tree().create_timer(0.5).timeout
	check.call(bool(_session.intro.get("done", false)), "modo dev pula a apresentação sozinho")
	check.call(not _session.dialogs.is_empty() and not _session.npc_roles.is_empty(), "diálogos e NPCs vieram do /content (%d diálogos)" % _session.dialogs.size())

	# Apresentação: o guia aparece, fala e pede para sacudir uma árvore.
	await restart_intro()
	await get_tree().create_timer(0.3).timeout
	check.call(is_instance_valid(intro_guide) and _ui.dialog.is_open() and _ui.dialog._skip.visible, "guia aparece com o diálogo e o botão de pular")
	check.call(_ui.dialog._text.contains(intro_guide.npc_name if intro_guide else "?"), "fala com o nome do guia: %s" % _ui.dialog._text)
	_dialog_choose(0)
	await get_tree().create_timer(0.2).timeout
	check.call(_intro_task == "shake" and is_instance_valid(_intro_arrow), "tarefa sacudir com a seta em cima da árvore")
	var tree := {}
	for o: Dictionary in _data.objects_near(_player.global_position, 140.0):
		if o["kind"] == "tree":
			var st: Dictionary = o.get("state", {}) if o.get("state") is Dictionary else {}
			if st.is_empty():
				tree = o
				break
	var coins := _session.coins
	if not tree.is_empty():
		_session.equip("")
		var up: Vector3 = tree["up"]
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		await _teleport((tree["pos"] as Vector3) + side * 1.1)
		await get_tree().create_timer(0.3).timeout
		_interaction.target = {"type": "object", "obj": tree}
		await _interaction.interact()
		await get_tree().create_timer(1.5).timeout
	check.call(_session.coins > coins and (_session.intro.get("tasks", []) as Array).has("shake"), "sacudir cumpre a tarefa e paga (%d → %d)" % [coins, _session.coins])
	check.call(_ui.dialog.is_open() and _ui.dialog._lines == _session.dialogs.get("intro_after_shake"), "o guia comenta depois da tarefa")
	skip_intro()
	await get_tree().create_timer(0.8).timeout
	check.call(not is_instance_valid(intro_guide) and bool(_session.intro.get("done", false)) and not _intro_skip.visible, "pular a apresentação guarda no servidor")

	# Praça central do Brasil: lojista e atendente.
	var bra := _airports.of_country("BRA")
	await _teleport(_airports.arrival_point(bra))
	await get_tree().create_timer(1.5).timeout
	var shopkeeper: Npc = null
	var attendant: Npc = null
	for cell: int in _airports._built:
		for n in (_airports._built[cell] as Node3D).get_meta("npcs", []):
			if is_instance_valid(n) and (n as Npc).country == "BRA":
				if (n as Npc).role == "shopkeeper":
					shopkeeper = n
				elif (n as Npc).role == "attendant":
					attendant = n
	check.call(shopkeeper != null and attendant != null, "praça com lojista e atendente")
	if shopkeeper:
		await _teleport(shopkeeper.global_position + (shopkeeper.global_basis.z * -1.2))
		await get_tree().create_timer(0.5).timeout
		_interaction._timer = 0.0
		await get_tree().create_timer(0.2).timeout
		check.call(_interaction.target.get("type", "") == "npc", "E perto do lojista: %s" % _interaction._prompt_text(_interaction.target))
		await talk(shopkeeper)
		await get_tree().create_timer(0.2).timeout
		check.call(_ui.dialog.is_open() and not _item_of_day.is_empty(), "lojista fala do item do dia (%s)" % _item_of_day)
		_dialog_choose(0)
		await get_tree().create_timer(1.0).timeout
		check.call(_ui.shop.visible, "\"Quero comprar\" abre a loja")
		await _dev("/dev/coins", {"amount": 300}, "")
		var seeds := _session.count("seeds")
		await shop_buy("BRA", "seeds", 2)
		check.call(_session.count("seeds") == seeds + 2, "comprar 2 sementes na loja")
		coins = _session.coins
		await shop_sell("BRA", [{"item": "seeds", "count": 1}])
		check.call(_session.coins > coins and _session.count("seeds") == seeds + 1, "vender para a loja paga (%d → %d)" % [coins, _session.coins])
		_ui.close_windows()
	if attendant:
		await talk(attendant)
		await get_tree().create_timer(0.2).timeout
		_dialog_choose(1)
		await get_tree().create_timer(1.0).timeout
		check.call(_ui.travel.visible and _ui.travel._tabs.current_tab == 1, "atendente oferece o passaporte (aba de passaportes)")
		_ui.close_windows()

	# Troca com um bot do modo dev (ele oferece 3 madeiras e acompanha).
	await _dev("/dev/give", {"item": "stone", "count": 5}, "")
	var wood := _session.count("wood")
	var stone := _session.count("stone")
	await dev_trade_bot()
	var t := 0.0
	while not _ui.trade.trading() and t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	check.call(_ui.trade.visible and _ui.trade.trading(), "troca com o bot aberta")
	await get_tree().create_timer(0.6).timeout
	var theirs: Dictionary = _ui.trade.view.get("theirs", {})
	check.call(str(theirs).contains("wood"), "o bot oferece madeira: %s" % str(theirs))
	_ui.trade._offer_items = [{"item": "stone", "count": 2}]
	_ui.trade._send_offer()
	await get_tree().create_timer(0.5).timeout
	net_send({"t": "trade_ready", "on": true})
	await get_tree().create_timer(0.8).timeout
	check.call(bool(_ui.trade.view.get("both_ready", false)), "os dois prontos")
	net_send({"t": "trade_confirm"})
	t = 0.0
	while _ui.trade.trading() and t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	check.call(_session.count("wood") == wood + 3 and _session.count("stone") == stone - 2, "troca feita: madeira %d → %d, pedra %d → %d" % [wood, _session.count("wood"), stone, _session.count("stone")])
	await dev_bots(0)

	if fails.is_empty():
		print("Goblo: npc-test OK")
	else:
		print("Goblo: npc-test FALHOU: %s" % ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)


## Automação da fase 4.0 (servidor dev): corpo, temperatura, velocidade, fogueira, comida,
## roupas, editor e modo tranquilo.
func _body_test() -> void:
	var fails: Array[String] = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: body-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	var t := 0.0
	while body.body.is_empty() and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	check.call(not body.body.is_empty(), "corpo chegou do servidor (%.0f °C, nível %s)" % [float(body.body.get("felt", 0)), body.body.get("level", "?")])
	await dev_body({"need": "all", "value": 100})
	await dev_body({"temp": 20})
	check.call(str(body.body.get("level", "")) == "optimal" and _player.speed_mult > 1.0, "tudo cheio: ótimo, mais rápido (×%.2f)" % _player.speed_mult)
	await dev_body({"need": "hunger", "value": 0})
	await get_tree().create_timer(2.5).timeout
	check.call(_player.speed_mult < 1.0 and body._dizzy.visible, "fome no mínimo: mais devagar (×%.2f) e tela zonza" % _player.speed_mult)
	await dev_body({"need": "all", "value": 60})
	check.call(is_equal_approx(_player.speed_mult, 1.0) and not bool(body.body.get("dizzy", true)), "neutro: velocidade de sempre")
	await dev_body({"temp": -12})
	await get_tree().create_timer(0.4).timeout
	check.call(bool(body.body.get("cold", false)) and body._breath.emitting and absf(_player.shiver) > 0.0 or bool(body.body.get("cold", false)) and body._breath.emitting,
		"−12 °C: com frio, vapor da respiração e tremendo")
	await dev_body({"temp": 40})
	await get_tree().create_timer(0.3).timeout
	check.call(bool(body.body.get("hot", false)) and body._sweat.emitting and _player.fanning, "40 °C: com calor, suando e se abanando")
	await dev_body({"unforce": true})
	# Fogueira no chão, cozinhar e comer.
	await dev_body_kit()
	var lit := await body.light_fire()
	check.call(lit and not body.fires.is_empty(), "fogueira acesa no chão (%d)" % body.fires.size())
	_interaction._timer = 0.0
	await get_tree().create_timer(0.3).timeout
	check.call(_interaction.target.get("type", "") == "fire", "E perto da fogueira: %s" % _interaction._prompt_text(_interaction.target))
	await _interaction.interact()
	check.call(body.cook_open(), "janela da fogueira abriu")
	await body.cook("roasted_berries")
	check.call(_session.count("roasted_berries") == 1, "cozinhou frutinhas assadas")
	_ui.close_windows()
	await dev_body({"need": "all", "value": 30})
	await body.consume("roasted_berries")
	check.call(float(body.body.get("hunger", 0)) > 30.0 and (body.body.get("buffs", []) as Array).size() == 1,
		"comeu: fome %.0f e bônus %s" % [float(body.body.get("hunger", 0)), str(body.body.get("buffs", []))])
	# Roupas e visual.
	await dev_wear()
	await wear("coat")
	await wear("beanie")
	await get_tree().create_timer(1.0).timeout
	var worn: Dictionary = _player.look_view.get("wear", {})
	check.call(worn.has("body") and worn.has("head") and _session.count("coat") == 0, "vestiu casaco e gorro (proteção contra frio %d)" % int(body.body.get("cold_protection", 0)))
	check.call(_player._look_mi != null and is_instance_valid(_player._look_mi), "malha do visual montada no personagem")
	await wear("straw_hat")
	check.call(str((_player.look_view.get("wear", {}) as Dictionary).get("head", {}).get("item", "")) == "straw_hat" and _session.count("beanie") == 1,
		"chapéu de palha no lugar do gorro (o gorro voltou ao bolso)")
	await dye("body", "paint_red")
	check.call(str((_player.look_view.get("wear", {}) as Dictionary).get("body", {}).get("color", "")) == str(_session.items["paint_red"]["color"]), "casaco pintado de vermelho")
	var look: Dictionary = (_player.look_view.get("look", {}) as Dictionary).duplicate()
	look["head"] = "female-e"
	look["skin"] = "#9c6644"
	look["accessory"] = "aid-glasses"
	await save_look(look)
	check.call(str((_player.look_view.get("look", {}) as Dictionary).get("head", "")) == "female-e", "editor salvou a cabeça nova")
	# Modo tranquilo.
	await body.set_quiet(true)
	check.call(body.quiet() and is_equal_approx(_player.speed_mult, 1.0), "modo tranquilo ligado")
	await body.set_quiet(false)
	check.call(not body.quiet(), "modo tranquilo desligado")
	if fails.is_empty():
		print("Goblo: body-test OK")
	else:
		print("Goblo: body-test FALHOU: %s" % ", ".join(fails))
	get_tree().quit(0 if fails.is_empty() else 1)


## Fase 4.5: o ciclo das cavernas (servidor dev): boca no globo, entrar pelo E, minerar até
## quebrar, tocha na parede e de volta, fornalha antiga, sala do chefe (invencível), dormir e
## vencer, sair pela boca; e uma lenda aparecendo no globo.
func _cave_test() -> void:
	var fails: Array[String] = []
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: cave-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails.append(what)
	check.call(_session.dev, "servidor em modo dev")
	check.call(cave.caves.size() > 100, "bocas de caverna do servidor (%d)" % cave.caves.size())
	await dev_cave_kit()
	await dev_cave_mouth()
	await get_tree().create_timer(1.0).timeout
	_interaction._timer = 0.0
	await get_tree().create_timer(0.3).timeout
	var t := _interaction.target
	check.call(not t.is_empty() and str(t.get("what", "")) == "enter", "E na boca da caverna: %s" % _interaction._prompt_text(t))
	if not t.is_empty() and str(t.get("what", "")) == "enter":
		await _interaction.interact()
	else:
		await dev_cave_enter(-1)
	await get_tree().create_timer(0.8).timeout
	check.call(cave.active and cave.cw != null and _player.cave_mode, "dentro da caverna (%s)" % str(cave.view.get("name", "")))
	check.call(not _terrain.visible and not _sun.visible, "globo e sol escondidos")
	var bag_before := _session.count("coal") + _session.count("iron_ore")
	# Minério da entrada (carvão ou ferro): golpes até quebrar.
	var ore := {}
	for id: int in cave.cw.ores:
		var o: Dictionary = cave.cw.ores[id]["ore"]
		if int(o["min_tier"]) <= 1:
			ore = {"id": id, "node": cave.cw.ores[id]["node"], "ore": o}
			break
	check.call(not ore.is_empty(), "minério na caverna")
	if not ore.is_empty():
		var node: Node3D = ore["node"]
		var up := node.global_position.normalized()
		var side := up.cross(cave.cw.global_basis.x).normalized()
		_player.teleport(node.global_position + side * 1.6)
		net_teleport("dev", _player.global_position)
		await get_tree().create_timer(0.4).timeout
		_session.equip(_session.tools()[0])
		for k in 8:
			var r := await cave.interact({"type": "cave", "what": "ore", "id": int(ore["id"]), "ore": ore["ore"], "pos": node.global_position})
			if cave.mined.has(int(ore["id"])) or (r.has("ok") and not bool(r["ok"])):
				break
			await get_tree().create_timer(0.1).timeout
		check.call(cave.mined.has(int(ore["id"])), "minério quebrou com a picareta")
		check.call(_session.count("coal") + _session.count("iron_ore") > bag_before, "minério no bolso")
	# Tocha na parede e de volta.
	var torches := _session.count("torch")
	_session.equip("torch")
	await get_tree().create_timer(0.2).timeout
	await cave.place_torch()
	await get_tree().create_timer(0.3).timeout
	check.call(cave.torches.size() == 1 and _session.count("torch") == torches - 1, "tocha acesa na caverna")
	check.call(cave._player_light.visible, "luz da tocha na mão")
	if cave.torches.size() == 1:
		await cave._take_torch(int(cave.torches[0]["id"]))
		check.call(cave.torches.is_empty() and _session.count("torch") == torches, "tocha de volta ao bolso")
	# Fornalha antiga.
	_player.teleport(cave.cw.furnace_point + cave.cw.global_basis.x.normalized() * 1.6)
	net_teleport("dev", _player.global_position)
	await get_tree().create_timer(0.4).timeout
	var bars := _session.count("iron_bar")
	var r2 := await api_request("POST", "/furnace/smelt", {"recipe": "iron_bar", "times": 1, "cave": cave.cave_id})
	check.call(r2["ok"], "fornalha antiga derrete ferro (%s)" % str(r2.get("message", "")))
	# Chefe: invencível, ataques, dormir e vencer.
	await dev_cave_god(true)
	await dev_cave_boss(false)
	await get_tree().create_timer(5.0).timeout
	check.call(str(cave.boss["phase"]) == "awake" and cave._warnings.size() + int(cave.boss["hits"]) >= 0, "golem acorda com o jogador na sala")
	check.call(int(cave.boss["hits"]) == 0, "invencível: nenhum acerto")
	await dev_cave_boss(true)
	await get_tree().create_timer(0.4).timeout
	var coins := _session.coins
	var res := await cave._wake_boss()
	check.call(res.get("ok", false) and bool(res["data"].get("won", false)) and _session.coins > coins, "vencer o golem dormindo paga (%d → %d)" % [coins, _session.coins])
	check.call(_session.count("golem_heart") >= 1, "coração de cristal no bolso")
	# Sair pela boca.
	await cave.exit()
	await get_tree().create_timer(0.8).timeout
	check.call(not cave.active and not _player.cave_mode and _terrain.visible, "de volta ao globo")
	check.call(_player.global_position.length() < world.radius + 30.0, "no chão do planeta")
	await get_tree().create_timer(0.3).timeout
	check.call(_net.state == "conectado", "tempo real continua conectado")
	print("Goblo: cave-test %s (%d falhas)" % ["ok" if fails.is_empty() else "FALHOU", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)
