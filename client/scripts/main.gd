extends Node3D
## Ponto de entrada: baixa o mundo do servidor (com cache local), monta o globo e solta o
## personagem.
##
## Argumentos opcionais (depois de "--" na linha de comando):
##   --server=URL        servidor do mundo (também: GOBLO_SERVER_URL ou goblo/server_url)
##   --quality=Q         low, medium ou high (padrão: o salvo, ou medium)
##   --spawn=LAT,LON     onde o personagem nasce (padrão: São Paulo)
##   --zoom=0..1         zoom inicial da câmera
##   --utc=HORA          fixa o horário UTC (ex.: 15.5) para testes e screenshots
##   --no-cache          ignora o mundo guardado em cache
##   --smoke-test        anda alguns segundos, imprime onde o personagem está e fecha
##   --jump              (com --smoke-test) pula e mede a altura do pulo
##   --screenshot=ARQ    salva um PNG da tela e fecha (combine com --zoom e --walk)
##   --walk=SEGUNDOS     anda antes do teste/screenshot
##   --dir=DIREÇÃO       forward (padrão), back, left ou right
##   --run               segura Shift enquanto anda (corre)
##   --moving            tira o screenshot ainda andando (para ver a animação)
##   --route=LAT,LON     piloto automático até a coordenada; imprime o tempo e fecha
##   --perf-test=SEG     anda pela região medindo fps; imprime média e 1% piores e fecha
##   --tour              passeio automático (anda, afasta, gira, volta) e fecha

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
	Quality.emitter.changed.connect(_apply_quality)
	_apply_quality()

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
	elif not _cached_version.is_empty() and FileAccess.file_exists(CACHE_FILE):
		data = FileAccess.get_file_as_bytes(CACHE_FILE)
		load_stats["source"] = "cache (servidor fora do ar)"
		push_warning("Servidor fora do ar; usando o mundo em cache.")
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

	var spawn := world.nearest_land(world.find_cell(WorldData.lat_lon_to_vec(spawn_lat, spawn_lon)))
	t0 = Time.get_ticks_msec()
	_terrain.update_collision(world.centers[spawn] * world.radius)
	load_stats["collision_ms"] = Time.get_ticks_msec() - t0
	_player.spawn(world, spawn)
	_camera.snap_behind_target()
	t0 = Time.get_ticks_msec()
	_vegetation.setup(world)
	_vegetation.load_now(_player.global_position)
	load_stats["vegetation_ms"] = Time.get_ticks_msec() - t0
	_hud.hide_status()
	print("Goblo: mundo %d células (n = %d, raio %.0f) — %s, download %d ms, leitura %d ms, malhas %d ms, colisão %d ms, vegetação %d ms (%d objetos, qualidade %s)" % [
		world.cell_count(), world.frequency, world.radius, load_stats["source"],
		load_stats["download_ms"], load_stats["parse_ms"], load_stats["mesh_ms"], load_stats["collision_ms"],
		load_stats["vegetation_ms"], _vegetation.instance_count, Quality.current_name()])
	_run_automation()


func _fail(message: String) -> void:
	push_warning(message)
	if _is_automation():
		printerr("Goblo: " + message)
		get_tree().quit(1)
		return
	_hud.show_status(message + "\nTentando de novo em %d s…" % int(RETRY_SECONDS))
	await get_tree().create_timer(RETRY_SECONDS).timeout
	_request_world()


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


func _process(delta: float) -> void:
	if world == null or not _player.visible:
		return
	_collision_timer -= delta
	if _collision_timer <= 0.0:
		_collision_timer = 0.25
		_terrain.update_collision(_player.global_position)
	_vegetation.update_focus(_player.global_position, _camera.far_amount, delta)
	_day_night.update(delta, _player.global_position.normalized(), _camera.far_amount)
	_clouds.update(delta, _camera.far_amount, maxf(_day_night.local_day, _camera.far_amount))
	_hud.show_time(_day_night.local_hours(world.lons[_player.cell_id]), _day_night.speed)
	if _highlight.mesh:
		var mat := _highlight.mesh.surface_get_material(0) as StandardMaterial3D
		mat.albedo_color.a = 0.45 + 0.15 * sin(Time.get_ticks_msec() / 300.0)
		_highlight.visible = _camera.far_amount < 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F3:
				_day_night.faster()
				_hud.flash("Tempo ×%d" % int(_day_night.speed))
			KEY_F4:
				_day_night.real_time()
				_hud.flash("Horário real")
			KEY_F6:
				Quality.cycle()
				_hud.flash("Qualidade: %s" % Quality.label())


## Aplica a qualidade atual: antisserrilhado e sombras (a vegetação se recarrega sozinha).
func _apply_quality() -> void:
	var q := Quality.current()
	get_viewport().msaa_3d = q["msaa"]
	_day_night.set_shadows_wanted(q["shadows"])
	_sun.directional_shadow_max_distance = maxf(1.0, q["shadow_distance"])


# --- Automação para testes e screenshots ---------------------------------------------------

func _is_automation() -> bool:
	for k in ["smoke-test", "screenshot", "route", "perf-test", "tour"]:
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
	await RenderingServer.frame_post_draw
	var path := str(_args["screenshot"])
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Goblo: screenshot salvo em %s (erro %d)" % [path, err])
	get_tree().quit(0 if err == OK else 1)


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
	await get_tree().create_timer(3.0).timeout
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
	print("Goblo: desempenho (%s, qualidade %s): média %.1f fps, 1%% piores %.1f fps, pior quadro %.1f ms, %d draw calls, %.0f mil triângulos, %s" % [
		world.biome_label(_player.cell_id), Quality.current_name(), n / total, 1.0 / worst_avg, times[n - 1] * 1000.0,
		int(draw_calls / n), primitives / n / 1000.0, Engine.get_version_info()["string"]])
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
