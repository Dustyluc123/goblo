class_name PediaPhotos
extends RefCounted
## Álbum de fotos da câmera fotográfica (fase 4.5, ADR 0055). As fotos ficam só neste
## computador, numa pasta por perfil e por conta:
##   user://fotos/<perfil>/<conta>/<id>.png e <id>_mini.png
## A conta é o id do jogador mais um pedaço do hash do token: outra conta no mesmo perfil
## (banco zerado, outro servidor) começa um álbum novo e nunca vê as fotos da antiga.
## O índice (album.cfg) guarda, por foto, a data, o lugar e a página que ela registrou; e, por
## página da Goblopédia, qual foto a representa (escolhida na galeria ou a primeira). Tudo
## pelo id da foto, nunca pela posição numa lista. As miniaturas ficam em cache e saem dele
## quando a foto muda ou é apagada.

const ROOT := "user://fotos"
const MINI_WIDTH := 360

static var _thumbs := {}  # caminho da miniatura → Texture2D
static var _seq := 0


## Pasta da conta. `account` vem de Session.photo_account().
static func dir_of(account: String) -> String:
	return "%s/%s" % [ROOT, account]


static func _index_path(account: String) -> String:
	return dir_of(account) + "/album.cfg"


static func _load(account: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(_index_path(account))
	return cfg


static func _save_cfg(account: String, cfg: ConfigFile) -> void:
	DirAccess.make_dir_recursive_absolute(dir_of(account))
	cfg.save(_index_path(account))


## Id único: data e hora, milissegundos, um contador e um sorteio.
static func new_id() -> String:
	_seq += 1
	var t := Time.get_datetime_dict_from_system()
	return "foto_%04d%02d%02d_%02d%02d%02d_%d_%d_%04x" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"],
		Time.get_ticks_msec(), _seq, randi() % 0x10000]


## Salva a foto e a miniatura. `info`: {"country", "country_name", "biome", "lat", "lon"}.
## Devolve o id da foto ("" se não deu).
static func save(account: String, img: Image, info := {}) -> String:
	if account.is_empty() or img == null or img.is_empty():
		return ""
	var dir := dir_of(account)
	DirAccess.make_dir_recursive_absolute(dir)
	var id := new_id()
	while FileAccess.file_exists("%s/%s.png" % [dir, id]):
		id = new_id()
	if img.save_png("%s/%s.png" % [dir, id]) != OK:
		return ""
	var mini := img.duplicate() as Image
	var h := int(float(img.get_height()) * MINI_WIDTH / maxf(1.0, img.get_width()))
	mini.resize(MINI_WIDTH, maxi(h, 1), Image.INTERPOLATE_BILINEAR)
	mini.save_png("%s/%s_mini.png" % [dir, id])
	var cfg := _load(account)
	var rec := info.duplicate()
	_seq += 1
	rec["at"] = int(Time.get_unix_time_from_system())
	rec["t"] = Time.get_unix_time_from_system() + _seq * 1e-6  # ordem exata, mesmo no mesmo segundo
	rec["entry"] = ""
	cfg.set_value("photos", id, rec)
	_save_cfg(account, cfg)
	return id


## Marca que a foto registrou uma página. Se a página ainda não tem foto, esta a representa.
static func tag(account: String, photo: String, entry: String) -> void:
	if photo.is_empty() or entry.is_empty():
		return
	var cfg := _load(account)
	if not cfg.has_section_key("photos", photo):
		return
	var rec: Dictionary = cfg.get_value("photos", photo)
	rec["entry"] = entry
	cfg.set_value("photos", photo, rec)
	if not cfg.has_section_key("pick", entry):
		cfg.set_value("pick", entry, photo)
	_save_cfg(account, cfg)


## Todas as fotos, mais recentes primeiro: [{"id", "at", "entry", "country", "country_name", "biome", ...}].
static func list(account: String) -> Array:
	var cfg := _load(account)
	var out: Array = []
	if cfg.has_section("photos"):
		for id: String in cfg.get_section_keys("photos"):
			var rec: Dictionary = (cfg.get_value("photos", id) as Dictionary).duplicate()
			rec["id"] = id
			out.append(rec)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", a.get("at", 0))) > float(b.get("t", b.get("at", 0))))
	return out


## A foto que representa a página ("" se não há): a escolhida, se ainda existe.
static func pick_of(account: String, entry: String) -> String:
	var cfg := _load(account)
	var id := str(cfg.get_value("pick", entry, ""))
	if not id.is_empty() and cfg.has_section_key("photos", id):
		return id
	return ""


## Escolhe a foto que representa uma página (galeria).
static func set_pick(account: String, entry: String, photo: String) -> void:
	var cfg := _load(account)
	if not cfg.has_section_key("photos", photo):
		return
	cfg.set_value("pick", entry, photo)
	_save_cfg(account, cfg)


## Apaga uma foto (arquivos e índice). Se ela representava uma página, a página passa para a
## foto mais antiga que sobrou daquela página (ou fica sem foto).
static func remove(account: String, photo: String) -> void:
	var cfg := _load(account)
	if not cfg.has_section_key("photos", photo):
		return
	cfg.erase_section_key("photos", photo)
	var dir := dir_of(account)
	for suffix in [".png", "_mini.png"]:
		var path := "%s/%s%s" % [dir, photo, suffix]
		_thumbs.erase(path)
		DirAccess.remove_absolute(path)
	if cfg.has_section("pick"):
		for entry: String in cfg.get_section_keys("pick"):
			if str(cfg.get_value("pick", entry)) != photo:
				continue
			var best := ""
			var best_at := 0
			if cfg.has_section("photos"):
				for id: String in cfg.get_section_keys("photos"):
					var rec: Dictionary = cfg.get_value("photos", id)
					if str(rec.get("entry", "")) == entry and (best.is_empty() or int(rec.get("at", 0)) < best_at):
						best = id
						best_at = int(rec.get("at", 0))
			if best.is_empty():
				cfg.erase_section_key("pick", entry)
			else:
				cfg.set_value("pick", entry, best)
	_save_cfg(account, cfg)


## Miniatura de uma foto (null se o arquivo sumiu).
static func thumbnail(account: String, photo: String) -> Texture2D:
	if photo.is_empty():
		return null
	var dir := dir_of(account)
	var mini := "%s/%s_mini.png" % [dir, photo]
	var path := mini if FileAccess.file_exists(mini) else "%s/%s.png" % [dir, photo]
	if _thumbs.has(path):
		return _thumbs[path]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_thumbs[path] = tex
	return tex


## Foto inteira (para a galeria ampliada).
static func full(account: String, photo: String) -> Texture2D:
	var path := "%s/%s.png" % [dir_of(account), photo]
	if not FileAccess.file_exists(path):
		return thumbnail(account, photo)
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


## Miniatura da foto que representa a página (null se não há foto neste computador).
static func entry_thumbnail(account: String, entry: String) -> Texture2D:
	return thumbnail(account, pick_of(account, entry))


## Zera as escolhas das páginas (modo dev: zerar a Goblopédia). As fotos continuam no álbum,
## sem página.
static func clear(account: String) -> void:
	var cfg := _load(account)
	if cfg.has_section("pick"):
		cfg.erase_section("pick")
	if cfg.has_section("photos"):
		for id: String in cfg.get_section_keys("photos"):
			var rec: Dictionary = cfg.get_value("photos", id)
			rec["entry"] = ""
			cfg.set_value("photos", id, rec)
	_save_cfg(account, cfg)
