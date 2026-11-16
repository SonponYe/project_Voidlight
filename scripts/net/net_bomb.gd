extends Node2D
class_name NetBomb
## A placed Bomb Voyage bomb. Static once dropped, so it needs no
## synchronizer — the spawn data carries everything. The server decides
## when it goes off (net_arena.gd); this node is just the marker.

const PROXIMITY_COLOR := Color(1.0, 0.5, 0.2)
const MANUAL_COLOR := Color(0.3, 0.6, 1.0)

var owner_peer_id := 0
var team := 0
var manual := false


func is_enemy(player: NetPlayer) -> bool:
	return player.owner_peer_id != owner_peer_id and (team == 0 or player.team != team)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 9.0, Color(0.15, 0.15, 0.15))
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, MANUAL_COLOR if manual else PROXIMITY_COLOR, 2.0)
