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
##   --photo-test        câmera fotográfica: enquadra uma vaca, fotografa, confere o registro
##                       na Goblopédia (moedas só na primeira foto) e abre o álbum
##   --season-test       força cada estação (modo dev) e confere árvores, grama, chão, o
##                       nome no HUD, os dois hemisférios, os trópicos e a foto de outono
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
## Fase da estação aplicada agora (no hemisfério norte; ver Seasons).
var _season_north := -1.0
var _season_timer := 0.0
var _season_busy := false
var _tracker: CountryTracker
## Marcador da casa no globo, visível na visão afastada.
var _home_marker: Sprite3D

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
	_session.equipped_changed.connect(_on_equipped)

	_http = HTTPRequest.new()
	_http.timeout = 30.0
	_http.request_completed.connect(_on_world_downloaded)
	add_child(_http)
	_request_world()


# --- Carga do mundo -----------------------------------------------------------------------

func _request_world() -> void:
	_hud.show_status("Baixando o mundo de %s…" % _server_url)
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
	load_stats["models_ms"] = Time.get_ticks_msec() - tm
	_setup_game()

	var t1 := Time.get_ticks_msec()
	var spawn_cell: int
	var spawn_pos: Vector3
	if _args.has("spawn") or _session.lot().is_empty():
		spawn_cell = world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(spawn_lat, spawn_lon)))
		spawn_pos = world.centers[spawn_cell] * world.surface_radius(spawn_cell)
	else:
		spawn_pos = home_point()
		spawn_cell = world.find_cell(spawn_pos)
	_terrain.update_collision(spawn_pos, -1)
	_player.spawn(world, spawn_cell)
	_player.teleport(spawn_pos)
	_camera.snap_behind_target()
	await _data.load_now(spawn_pos, 60.0)
	_vegetation.load_now(_player.global_position)
	load_stats["content_ms"] = Time.get_ticks_msec() - t1
	_hud.hide_status()
	_ready_to_play = true
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
		_hud.show_status("Sem resposta do servidor (%s).\nTentando de novo…" % r["message"])
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
		var r := await _api.request("POST", "/players", {"nickname": nick, "country": country})
		if not r["ok"]:
			_fail("Não consegui criar o jogador: %s" % r["message"])
			return false
		created = r["data"]
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
	_build.game = self
	_build.session = _session
	_build.data = _data
	_build.api = _api
	_build.ui = _ui
	_build.camera = _camera
	_build.player = _player
	_ui.on_build_close = _build.exit
	_border_lines.setup(world, _data)
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
	_hud.show_status(message + "\nTentando de novo em %d s…" % int(RETRY_SECONDS))
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


## Mudou o país embaixo do personagem (posição exata, ADR 0031).
func _on_country_changed(code: String, walked: bool) -> void:
	_hud.set_country(code, _tracker.name_of(code))
	if walked:
		_hud.welcome(_tracker.name_of(code))


func _on_equipped() -> void:
	var id := _session.equipped
	if id.is_empty():
		_player.set_tool(null)
		return
	var lib := ModelLibrary.get_model(str(_session.items.get(id, {}).get("model", "")))
	_player.set_tool(lib.get("mesh"))
	_ui.toast("Na mão: %s" % _session.item_name(id), id)


func _process(delta: float) -> void:
	if world == null or not _player.visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is SpinBox
	_player.input_blocked = typing or _ui.menu_open()
	_hud.set_help_visible(not _ui.any_open())
	# A barra rápida some atrás das janelas (bolso, bancada, dev, configurações).
	_ui.hotbar.visible = not _ui.menu_open()
	_collision_timer -= delta
	if _collision_timer <= 0.0:
		_collision_timer = 0.25
		_terrain.update_collision(_player.global_position)
	_data.update_focus(_player.global_position, delta)
	_vegetation.update_focus(_player.global_position, _camera.far_amount, delta)
	_border_lines.update_view(_camera.far_amount)
	_animals.update_view(_camera.far_amount)
	_update_season(delta)
	_neighborhood.daylight = _day_night.local_day
	_neighborhood.update_lights(_player.global_position, delta)
	_day_night.update(delta, _player.global_position.normalized(), _camera.far_amount)
	_clouds.update(delta, _camera.far_amount, maxf(_day_night.local_day, _camera.far_amount))
	_hud.show_time(_day_night.local_hours(world.lons[_player.cell_id]), _day_night.speed)
	_hud.update_navigation(_camera.global_basis, _player.global_position.normalized(), _day_night.sun_dir, _player.facing)
	if _home_marker:
		var far := _camera.far_amount
		_home_marker.visible = far > 0.25
		_home_marker.modulate.a = smoothstep(0.25, 0.6, far)
	if _hud.perf_visible():
		_hud.show_perf("%d fps · %.1f ms\n%d draw calls · %d mil triângulos\n%d objetos · %d lotes · %d animais · %d pedidos\nqualidade %s" % [
			Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			_vegetation.instance_count, _data.all_lots().size(), _animals.active_count, _api.in_flight, Quality.label()])
	if _highlight.mesh:
		var mat := _highlight.mesh.surface_get_material(0) as StandardMaterial3D
		mat.albedo_color.a = 0.22 + 0.08 * sin(Time.get_ticks_msec() / 300.0)
		_highlight.visible = _camera.far_amount < 0.5 and not _build.active


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
	await _teleport(home_point())
	_ui.toast("Bem-vindo de volta para casa!")


func _teleport(pos: Vector3) -> void:
	_build.exit()
	_tracker.mark_teleport()
	_player.set_physics_process(false)
	_player.teleport(pos)
	_terrain.update_collision(pos, -1)
	_camera.snap_behind_target()
	await _data.load_now(pos, 40.0)
	_vegetation.load_now(pos)
	_player.set_physics_process(true)


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
	_ui.dev.status("Você está em %s." % world.countries.get(code, code))


func teleport_lat_lon(lat: float, lon: float) -> void:
	var cell := world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(lat, lon)))
	await _teleport_to_cell(cell)
	_ui.dev.status("Teleportado para %s." % WorldData.format_lat_lon(world.lats[cell], world.lons[cell]))


func set_noclip(on: bool) -> void:
	if on and not _session.dev:
		return
	_player.set_noclip(on)
	_ui.toast("Voando: Espaço sobe, Ctrl desce, Shift acelera" if on else "Voltou a andar")


func time_faster() -> void:
	_day_night.faster()
	_hud.flash("Tempo ×%d" % int(_day_night.speed))


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
	GlobeBuilder.land_material().set_shader_parameter("season_phase", north)
	_hud.set_season_phase(north)
	_vegetation.set_season(north)
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
		_ui.dev.status("Data forçada: %02d/%02d (%s no norte, %s no sul)." % [md[1], md[0],
			Seasons.LABELS[season].to_lower(), Seasons.LABELS[Seasons.NAMES[(Seasons.NAMES.find(season) + 2) % 4]].to_lower()])
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


func craft(recipe: String) -> void:
	var r := await _api.request("POST", "/craft", {"recipe": recipe, "times": 1})
	if not r["ok"]:
		_ui.toast(str(r["message"]))
		return
	_session.set_inventory(r["data"]["inventory"], int(r["data"]["slots_used"]))
	var made: Dictionary = r["data"]["crafted"]
	_ui.toast("+%d %s" % [int(made["count"]), _session.item_name(made["item"])], made["item"])


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
	_ui.toast("Guardei %d objeto%s no bolso." % [ids.size(), "" if ids.size() == 1 else "s"])
	await upgrade_house()


# --- Modo dev -------------------------------------------------------------------------------

func _dev(path: String, body: Dictionary, done: String) -> Dictionary:
	var r := await _api.request("POST", path, body)
	if not r["ok"]:
		_ui.dev.status("Erro: %s" % r["message"])
		_ui.toast(str(r["message"]))
		return r
	if r["data"] is Dictionary and (r["data"] as Dictionary).has("inventory"):
		_session.set_me(r["data"])
	_ui.dev.status(done)
	return r


func dev_give(item: String, count: int) -> void:
	await _dev("/dev/give", {"item": item, "count": count}, "Você ganhou %d× %s." % [count, _session.item_name(item)])


func dev_starter_kit() -> void:
	for pair in [["axe", 1], ["pickaxe", 1], ["wood", 99], ["stone", 99], ["branch", 30], ["flower_red", 10], ["flower_yellow", 10]]:
		if _session.count(pair[0]) < int(pair[1]) or pair[0] != "axe" and pair[0] != "pickaxe":
			await _dev("/dev/give", {"item": pair[0], "count": pair[1]}, "Kit inicial entregue.")


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
		_ui.dev.status("%d vizinhos falsos criados aqui perto." % int(r["data"]["created"]))
		_data.refresh_all()


func dev_set_country(code: String) -> void:
	var r := await _dev("/dev/country", {"country": code}, "Agora você mora em %s." % world.countries.get(code, code))
	if r["ok"]:
		_data.refresh_all()
		await go_home()


func dev_reset(what: String) -> void:
	var r := await _dev("/dev/reset", {"what": what}, "Pronto: %s resetado." % what)
	if not r["ok"]:
		return
	if what == "player":
		_session.clear_token()
		get_tree().reload_current_scene()
		return
	_data.refresh_all()


# --- Automação para testes e screenshots ---------------------------------------------------

func _is_automation() -> bool:
	for k in ["smoke-test", "screenshot", "route", "perf-test", "tour", "play-test", "camera-test", "profile-scene", "border-test", "animal-test", "photo-test", "season-test"]:
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
	if _args.has("profile-scene"):
		await _profile_scene()
		return
	if not (_args.has("smoke-test") or _args.has("screenshot")):
		return
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
	if _args.has("ui"):
		await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var path := str(_args["screenshot"])
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Goblo: screenshot salvo em %s (erro %d, %d objetos transparentes na frente da câmera)" % [path, err, _occlusion.faded_count()])
	get_tree().quit(0 if err == OK else 1)


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
		"vender 2 madeiras: %d → %d moedas" % [coins_before, _session.coins])
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


func _set_layer_visible(layer: String, on: bool) -> void:
	for c in _vegetation.get_children():
		if c.has_meta("layer") and c.get_meta("layer") == layer:
			(c as Node3D).visible = on


## Animais: existem perto de campos e florestas, ficam no trajeto comum, reagem ao carinho
## e à frutinha, o tímido foge de quem corre e nenhuma animação de ataque é usada.
func _animal_test() -> void:
	var fails := 0
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: animal-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails += 1
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
		# Sem reação, o animal fica exatamente no trajeto comum (todo mundo vê igual).
		var worst := 0.0
		var now := _data.server_time()
		for id: int in _animals._active:
			var e: Dictionary = _animals._active[id]
			var pose := AnimalPath.at(e["animal"], now)
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
		await _interaction.interact()
		await get_tree().create_timer(0.3).timeout
		var hold: String = cow["anim"]
		check.call(hold in ["Idle_2", "Jump_toIdle", "Jump_ToIdle"], "carinho: o animal reage (%s)" % hold)
		await dev_give("berries", 3)
		_interaction._timer = 0.0
		await get_tree().create_timer(2.0).timeout
		var berries := _session.count("berries")
		await _interaction.interact()
		await get_tree().create_timer(0.3).timeout
		check.call(_animals.is_friend(cid) and str(cow["anim"]) == "Eating", "frutinha: come e vira amigo (%s)" % cow["anim"])
		check.call(_session.count("berries") == berries, "animal do modo dev não gasta frutinha do servidor")
	if not deer.is_empty():
		# Corre na direção do cervo: ele foge galopando e depois volta ao trajeto.
		var did := int(deer["animal"]["id"])
		_player.autopilot = true
		_player.auto_run = true
		var fled := false
		for i in 120:
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
	print("Goblo: animal-test %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Câmera fotográfica e Goblopédia, do modo foto ao álbum.
func _photo_test() -> void:
	var fails := 0
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: photo-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails += 1
	await _dev("/dev/pedia", {"action": "reset"}, "")
	await dev_give("camera", 1)
	_session.equip("camera")
	await teleport_exact(-34.6, -60.5)
	await get_tree().create_timer(0.8).timeout
	var fwd := -_player.global_basis.z
	check.call(_animals.spawn_debug("cow", _player.global_position + fwd * 6.0), "vaca na frente (modo dev)")
	await get_tree().create_timer(0.8).timeout
	var cow: Node3D = null
	for id: int in _animals._active:
		if id < 0:
			cow = _animals._active[id]["node"]
	_photo.enter()
	check.call(_photo.active and _camera.photo_mode, "botão direito com a câmera na mão entra no modo foto")
	# Mira na vaca (o mouse giraria a câmera até ela).
	if cow:
		var up := _player.global_position.normalized()
		var to := cow.global_position - _player.global_position
		_camera._heading = (to - up * to.dot(up)).normalized()
		_camera.photo_pitch = -2.0
	await get_tree().create_timer(0.5).timeout
	var subjects := _photo.find_subjects()
	var entries: Array = subjects.map(func(x: Dictionary) -> String: return str(x["entry"]))
	check.call("cow" in entries, "vaca enquadrada: %s" % str(entries))
	var coins := _session.coins
	var reg := await _photo.take_photo()
	var first: Dictionary = reg[0] if not reg.is_empty() else {}
	check.call(first.get("entry", "") == "cow" and bool(first.get("first", false)) and _session.coins == coins + int(first.get("reward", 0)) and int(first.get("reward", 0)) > 0,
		"primeira foto da vaca registra e paga (%d → %d moedas)" % [coins, _session.coins])
	var reg2 := await _photo.take_photo()
	check.call(not reg2.is_empty() and not bool(reg2[0]["first"]) and int(reg2[0]["reward"]) == 0, "segunda foto não paga de novo")
	# Mirando para o outro lado, nada enquadrado.
	_camera._turn(PI)
	await get_tree().create_timer(0.4).timeout
	check.call(_photo.find_subjects().filter(func(x: Dictionary) -> bool: return x["entry"] == "cow").is_empty(), "de costas para a vaca, ela não conta")
	_photo.exit()
	check.call(not _camera.photo_mode, "botão direito ou Esc sai do modo foto")
	_ui.pedia.toggle()
	await get_tree().create_timer(1.0).timeout
	var cow_page: Array = _ui.pedia._entries.filter(func(e: Dictionary) -> bool: return e["id"] == "cow")
	check.call(not cow_page.is_empty() and bool(cow_page[0]["discovered"]) and int(cow_page[0]["sightings"]) == 2 and str(cow_page[0]["country"]) == "ARG",
		"Goblopédia: vaca descoberta na Argentina, 2 fotos (%s)" % str(cow_page))
	check.call(_ui.pedia._entries.size() >= 15, "álbum com %d páginas" % _ui.pedia._entries.size())
	_ui.close_windows()
	print("Goblo: photo-test %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	get_tree().quit(1 if fails > 0 else 0)


## Estações: no norte e no sul, árvores trocam de modelo pela estação, o HUD mostra o
## nome, os trópicos não mudam e a árvore de outono entra na Goblopédia.
func _season_test() -> void:
	var fails := 0
	var check := func(ok: bool, what: String) -> void:
		print("Goblo: season-test %s %s" % ["ok   " if ok else "FALHOU", what])
		if not ok:
			fails += 1
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
		var to := p - _player.global_position
		var pu := _player.global_position.normalized()
		_camera._heading = (to - pu * to.dot(pu)).normalized()
		_camera.photo_pitch = 8.0
		await get_tree().create_timer(0.5).timeout
		var reg := await _photo.take_photo()
		_photo.exit()
		var got: Array = reg.map(func(r: Dictionary) -> String: return str(r["entry"]))
		check.call("tree_autumn" in got, "foto de árvore de outono na Goblopédia: %s" % str(got))
	else:
		check.call(false, "achar uma árvore de outono perto")
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
	print("Goblo: season-test %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	get_tree().quit(1 if fails > 0 else 0)


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
	# Anda para o oeste até mudar de país.
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
	print("Goblo: border-test %s" % ("tudo certo" if fails == 0 else "%d falhas" % fails))
	get_tree().quit(1 if fails > 0 else 0)


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
		url = str(ProjectSettings.get_setting("goblo/server_url", DEFAULT_SERVER))
	return url.trim_suffix("/")
