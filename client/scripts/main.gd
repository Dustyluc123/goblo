extends Node3D
## Ponto de entrada: baixa o mundo do servidor, monta o globo e solta o personagem.
##
## Argumentos opcionais (depois de "--" na linha de comando):
##   --server=URL        servidor do mundo (também: GOBLO_SERVER_URL ou goblo/server_url)
##   --smoke-test        anda alguns segundos, imprime onde o personagem está e fecha
##   --screenshot=ARQ    salva um PNG da tela e fecha (combine com --zoom e --walk)
##   --zoom=0..1         zoom inicial da câmera
##   --walk=SEGUNDOS     anda para a frente antes do teste/screenshot
##   --dir=DIREÇÃO       forward (padrão), back, left ou right
##   --run               segura Shift enquanto anda (corre)
##   --moving            tira o screenshot ainda andando (para ver a animação)
##   --spawn=LAT,LON     onde o personagem nasce (padrão: São Paulo)
##   --tour              passeio automático (anda, afasta, gira, volta) e fecha; use com
##                       --write-movie do Godot para gravar o GIF do README

const DEFAULT_SERVER := "http://127.0.0.1:8080"
const RETRY_SECONDS := 3.0

## Altura das células de terra em relação ao oceano (o "degrau").
@export var land_height := 0.8
@export var spawn_lat := -23.55
@export var spawn_lon := -46.63

var world: WorldData
var _args := {}
var _http: HTTPRequest
var _server_url := ""

@onready var _globe: MeshInstance3D = $Globe
@onready var _globe_shape: CollisionShape3D = $GlobeBody/CollisionShape3D
@onready var _highlight: MeshInstance3D = $Highlight
@onready var _player: Player = $Player
@onready var _camera: CameraRig = $Camera
@onready var _sun: DirectionalLight3D = $Sun
@onready var _hud: Hud = $HUD


func _ready() -> void:
	InputSetup.ensure()
	_args = _parse_args()
	_server_url = _resolve_server_url()
	_camera.sun = _sun
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

	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.request_completed.connect(_on_world_downloaded)
	add_child(_http)
	_request_world()


func _request_world() -> void:
	_hud.show_status("Baixando o mundo de %s…" % _server_url)
	var err := _http.request(_server_url + "/world")
	if err != OK:
		_fail("Não consegui fazer a requisição (erro %d)." % err)


func _on_world_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("Sem resposta do servidor em %s (resultado %d, HTTP %d).\nEle está rodando? cd server && go run ./cmd/server" % [_server_url, result, code])
		return
	var started := Time.get_ticks_msec()
	world = WorldData.from_json(body.get_string_from_utf8())
	if world == null:
		_fail("O servidor mandou um mundo em formato inesperado.")
		return
	_camera.planet_radius = world.radius
	var mesh := GlobeBuilder.build(world, land_height)
	_globe.mesh = mesh
	_globe_shape.shape = mesh.create_trimesh_shape()
	print("Goblo: mundo com %d células (frequência %d) montado em %d ms" % [
		world.cell_count(), world.frequency, Time.get_ticks_msec() - started])

	var spawn := world.find_cell(WorldData.lat_lon_to_vec(spawn_lat, spawn_lon))
	spawn = world.nearest_land(spawn)
	_player.spawn(world, spawn, world.radius + land_height)
	_camera.snap_behind_target()
	_hud.hide_status()
	_run_automation()


func _fail(message: String) -> void:
	push_warning(message)
	if _args.has("smoke-test") or _args.has("screenshot"):
		printerr("Goblo: " + message)
		get_tree().quit(1)
		return
	_hud.show_status(message + "\nTentando de novo em %d s…" % int(RETRY_SECONDS))
	await get_tree().create_timer(RETRY_SECONDS).timeout
	_request_world()


func _on_cell_changed(id: int) -> void:
	_hud.show_cell(world, id)
	_highlight.mesh = GlobeBuilder.highlight(world, id, land_height)


func _process(_delta: float) -> void:
	if _highlight.mesh:
		var mat := _highlight.mesh.surface_get_material(0) as StandardMaterial3D
		mat.albedo_color.a = 0.25 + 0.12 * sin(Time.get_ticks_msec() / 300.0)


# --- Automação para testes e screenshots ---------------------------------------------------

func _run_automation() -> void:
	if _args.has("tour"):
		await _tour()
		return
	if not (_args.has("smoke-test") or _args.has("screenshot")):
		return
	var start_cell := _player.cell_id
	var walk := float(_args.get("walk", 3.0 if _args.has("smoke-test") else 0.0))
	await get_tree().create_timer(0.5).timeout
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
		var expected := world.radius + land_height
		print("Goblo: smoke-test célula %d → %d, %s (%s), raio do personagem %.2f (superfície %.2f), no chão: %s, animação %.2f" % [
			start_cell, id, world.country_name(id), WorldData.format_lat_lon(world.lats[id], world.lons[id]),
			r, expected, _player.is_on_floor(), _player.anim_blend])
		var ok := world.is_land(id) and absf(r - expected) < 0.5 and _player.is_on_floor()
		print("Goblo: smoke-test %s" % ("OK" if ok else "FALHOU"))
		get_tree().quit(0 if ok else 1)
		return

	if not _args.has("moving"):
		await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var path := str(_args["screenshot"])
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Goblo: screenshot salvo em %s (erro %d)" % [path, err])
	get_tree().quit(0 if err == OK else 1)


func _tour() -> void:
	_camera.set_zoom_now(0.12)
	_camera.spin_speed = 0.45
	await get_tree().create_timer(0.5).timeout
	Input.action_press("move_forward")
	await get_tree().create_timer(2.5).timeout
	Input.action_press("move_right")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_right")
	Input.action_release("move_forward")
	await _zoom_to(1.0, 3.0)
	await get_tree().create_timer(3.0).timeout
	await _zoom_to(0.15, 3.0)
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
