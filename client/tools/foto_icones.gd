extends SceneTree
## Fotos dos ícones de tintas, cantil e bebidas (fase 4.1), lado a lado num PNG.
##
##   tools/sem_foco.sh -s tools/foto_icones.gd -- --foto=/tmp/icones.png

const IDS := ["paint_red", "paint_yellow", "paint_white", "paint_purple", "paint_blue", "paint_pink",
	"canteen", "canteen_half", "canteen_full", "berry_juice", "herb_tea", "herb_soup", "coconut"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://icones.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--foto="):
			out = a.trim_prefix("--foto=")
	var path := ProjectSettings.globalize_path("res://").path_join("../server/data/game/items.json")
	var items := {}
	for it: Dictionary in (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)["items"]:
		if IDS.has(it["id"]):
			items[it["id"]] = it
	var icons := ItemIcons.new()
	get_root().add_child(icons)
	icons.setup(items)
	var done := {}
	icons.icon_ready.connect(func(id: String) -> void: done[id] = true)
	var waited := 0
	while done.size() < items.size() and waited < 600:
		await process_frame
		waited += 1
	var sheet := Image.create(ItemIcons.SIZE * IDS.size(), ItemIcons.SIZE, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("fff6e4"))
	for i in IDS.size():
		var img := icons.icon(IDS[i]).get_image()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() == ItemIcons.SIZE:
			sheet.blend_rect(img, Rect2i(0, 0, ItemIcons.SIZE, ItemIcons.SIZE), Vector2i(i * ItemIcons.SIZE, 0))
	sheet.save_png(out)
	print("ícones: %d de %d prontos, salvo em %s" % [done.size(), items.size(), out])
	quit()
