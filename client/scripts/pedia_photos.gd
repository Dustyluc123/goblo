class_name PediaPhotos
extends RefCounted
## Fotos da câmera fotográfica: ficam só neste computador, em user://fotos/ (PNG da tela
## inteira e uma miniatura "_mini.png"). A Goblopédia mostra a primeira foto de cada coisa;
## o índice fica em user://fotos/goblopedia.cfg (por perfil, para os testes não se
## misturarem com o jogador do autor).

const DIR := "user://fotos"
const MINI_WIDTH := 360


static func _index_path(profile: String) -> String:
	return "%s/goblopedia_%s.cfg" % [DIR, profile]


## Salva a foto e a miniatura. Devolve o caminho da foto ("" se não deu).
static func save(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var t := Time.get_datetime_dict_from_system()
	var base := "%s/foto_%04d%02d%02d_%02d%02d%02d_%03d" % [DIR, t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"], Time.get_ticks_msec() % 1000]
	if img.save_png(base + ".png") != OK:
		return ""
	var mini := img.duplicate() as Image
	var h := int(float(img.get_height()) * MINI_WIDTH / maxf(1.0, img.get_width()))
	mini.resize(MINI_WIDTH, maxi(h, 1), Image.INTERPOLATE_BILINEAR)
	mini.save_png(base + "_mini.png")
	return base + ".png"


## Guarda a foto como a primeira daquela coisa (se ainda não houver uma).
static func set_first(profile: String, entry: String, path: String) -> void:
	if path.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.load(_index_path(profile))
	if cfg.has_section_key("first", entry):
		return
	cfg.set_value("first", entry, path)
	DirAccess.make_dir_recursive_absolute(DIR)
	cfg.save(_index_path(profile))


## Miniatura da primeira foto de uma coisa (null se não há foto neste computador).
static func first_thumbnail(profile: String, entry: String) -> Texture2D:
	var cfg := ConfigFile.new()
	if cfg.load(_index_path(profile)) != OK:
		return null
	var path := str(cfg.get_value("first", entry, ""))
	if path.is_empty():
		return null
	var mini := path.trim_suffix(".png") + "_mini.png"
	var img := Image.load_from_file(mini if FileAccess.file_exists(mini) else path)
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


## Apaga o índice (modo dev: zerar a Goblopédia). As fotos continuam na pasta.
static func clear(profile: String) -> void:
	DirAccess.remove_absolute(_index_path(profile))
