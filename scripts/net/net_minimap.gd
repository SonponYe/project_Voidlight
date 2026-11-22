extends Control
class_name NetMinimap
## Corner map of the arena. The layout is always shown (players always know
## the map); other players are NOT — you only ever see yourself, your
## teammates, an enemy you're haunting with Poltergeist, and your own bombs.
## Spectators (eliminated players) see everyone, like everywhere else.

const BACKGROUND := Color(0.04, 0.04, 0.05, 0.80)
const WALL := Color(0.60, 0.60, 0.64)
const COVER := Color(0.72, 0.62, 0.42)
const WRECK := Color(0.50, 0.32, 0.22)
const HAUNT := Color(0.80, 0.40, 1.0)

var _map: NetMap
var _me: NetPlayer
var _players: Array = []
var _bombs: Array = []
var _pickups: Array = []


func update_view(map: NetMap, me: NetPlayer, players: Array, bombs: Array, pickups: Array) -> void:
	_map = map
	_me = me
	_players = players
	_bombs = bombs
	_pickups = pickups
	queue_redraw()


func _scale() -> float:
	return minf(size.x / _map.bounds.size.x, size.y / _map.bounds.size.y)


func _to_mini(world: Vector2) -> Vector2:
	var s := _scale()
	return (size - _map.bounds.size * s) * 0.5 + world * s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _map == null or _map.bounds.size == Vector2.ZERO:
		return
	var s := _scale()
	for block in _map.blocks:
		var rect: Rect2 = block["rect"]
		var color := WALL
		if block["kind"] == "c":
			color = COVER
		elif block["kind"] == "v":
			color = WRECK
		draw_rect(Rect2(_to_mini(rect.position), rect.size * s), color)
	for center in _map.barrels:
		draw_circle(_to_mini(center), maxf(1.2, 24.0 * s), WRECK)

	# Medical stations, ammo and dropped Gens: the map is known, so they always show.
	for node in _pickups:
		if not node is NetPickup:
			continue
		var at := _to_mini(node.position)
		match node.kind:
			"health":
				var tint := Color(0.4, 0.95, 0.55) if node.cooldown_left <= 0.0 else Color(0.5, 0.55, 0.52)
				draw_rect(Rect2(at - Vector2(1.2, 3.2), Vector2(2.4, 6.4)), tint)
				draw_rect(Rect2(at - Vector2(3.2, 1.2), Vector2(6.4, 2.4)), tint)
			"ammo":
				draw_rect(Rect2(at - Vector2(2, 1.5), Vector2(4, 3)), Color(0.95, 0.82, 0.35))
			"gen":
				var tint: Color = NetPickup.GEN_COLORS.get(node.gen_key, Color.WHITE)
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -3.5), at + Vector2(3.5, 0), at + Vector2(0, 3.5), at + Vector2(-3.5, 0)]), tint)

	var spectating := _me == null or _me.dead
	for node in _bombs:
		if node is NetBomb and _me != null and node.owner_peer_id == _me.owner_peer_id:
			var at := _to_mini(node.position)
			draw_rect(Rect2(at - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 0.55, 0.15))
	for node in _players:
		if not node is NetPlayer or node == _me or node.dead:
			continue
		var ally: bool = _me != null and _me.team != 0 and node.team == _me.team
		var haunted: bool = _me != null and _me.poltergeist_target == node.owner_peer_id
		if spectating or ally or haunted:
			var color: Color = HAUNT if haunted else node.visual.color
			draw_circle(_to_mini(node.position), 3.5, Color(0, 0, 0, 0.8))
			draw_circle(_to_mini(node.position), 2.5, color)
	if _me != null and not _me.dead:
		var here := _to_mini(_me.position)
		draw_circle(here, 5.0, Color(0, 0, 0, 0.85))
		draw_circle(here, 3.6, Color.WHITE)
		draw_line(here, here + Vector2.from_angle(_me.rotation) * 9.0, Color.WHITE, 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 1.5)
