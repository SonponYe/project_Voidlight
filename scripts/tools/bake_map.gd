extends Node
## Developer tool: renders every online arena's picture once and saves it where
## NetMap looks for it. Run it WINDOWED (it needs a real renderer) whenever an
## arena in scripts/net/arena_catalog.gd is added or changed:
##   godot --path . res://scripts/tools/bake_map.tscn
## It takes a few seconds per arena, writes assets/maps/baked_<fingerprint>.webp
## for each one that doesn't have a picture yet, and quits.
## Commit the .webp files and their .import files.

func _ready() -> void:
	await get_tree().process_frame
	for id in ArenaCatalog.ids():
		Network.map_id = id
		var arena: Node = load("res://scenes/net/net_arena.tscn").instantiate()
		get_tree().root.add_child(arena)
		var map: NetMap = arena.get_node("Map")
		if map.bake_viewport == null:
			print("BAKE: %s already has its picture at %s — delete it to re-bake." % [id, map.baked_path()])
		else:
			# The painting happens on the first rendered frames; wait them out.
			for i in 4:
				await RenderingServer.frame_post_draw
			var image := map.bake_viewport.get_texture().get_image()
			var path := map.baked_path()
			var err := image.save_webp(ProjectSettings.globalize_path(path), true, 0.92)
			print("BAKE: %s -> %s (%d x %d), error=%d" % [id, path, image.get_width(), image.get_height(), err])
		arena.queue_free()
		await get_tree().process_frame
	get_tree().quit()
