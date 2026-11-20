extends Node
## Developer tool: renders the online map's picture once and saves it where
## NetMap looks for it. Run it WINDOWED (it needs a real renderer) whenever the
## layout in net_arena.tscn changes:
##   godot --path . res://scripts/tools/bake_map.tscn
## It takes a few seconds, writes assets/maps/baked_<fingerprint>.webp and quits.
## Commit the .webp and its .import file.

func _ready() -> void:
	await get_tree().process_frame
	var arena: Node = load("res://scenes/net/net_arena.tscn").instantiate()
	get_tree().root.add_child(arena)
	var map: NetMap = arena.get_node("Map")
	if map.bake_viewport == null:
		print("BAKE: a picture for this layout already exists at %s — delete it to re-bake." % map.baked_path())
		get_tree().quit()
		return
	# The painting happens on the first rendered frames; wait them out.
	for i in 4:
		await RenderingServer.frame_post_draw
	var image := map.bake_viewport.get_texture().get_image()
	var path := map.baked_path()
	var err := image.save_webp(ProjectSettings.globalize_path(path), true, 0.92)
	print("BAKE: wrote %s (%d x %d), error=%d" % [path, image.get_width(), image.get_height(), err])
	get_tree().quit()
