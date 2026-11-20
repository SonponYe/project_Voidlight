class_name Story
extends RefCounted
## The game's words. Everything player-facing that carries story or mood is
## read from assets/story/story.json so it can be written and changed without
## touching code. A key that is missing or empty falls back to the wording
## passed in, so the game reads the same until something is written.
##
## Picks are made on the host and sent to everyone, so all players see the same
## line (see net_arena.gd) — calling pick() on every peer would show each
## player a different one.

const PATH := "res://assets/story/story.json"

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(PATH):
		return
	var resource = load(PATH)
	if resource is JSON and resource.data is Dictionary:
		_data = resource.data


## A random line from list `key`, or `fallback` if the list is missing/empty.
## `vars` fills placeholders such as {name}.
static func pick(key: String, fallback := "", vars := {}) -> String:
	_ensure()
	var text := fallback
	var lines = _data.get(key)
	if lines is Array and not lines.is_empty():
		var chosen := str(lines.pick_random()).strip_edges()
		if chosen != "":
			text = chosen
	for name in vars:
		text = text.replace("{%s}" % name, str(vars[name]))
	return text


## The lore line for one Gen ("" if none is written).
static func gen_line(gen: String) -> String:
	_ensure()
	var gens = _data.get("gens")
	if gens is Dictionary and gens.has(gen):
		return str(gens[gen]).strip_edges()
	return ""
