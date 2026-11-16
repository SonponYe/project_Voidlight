extends Node2D
## Minimal authoritative network arena. Proves connect -> spawn -> move-sync
## -> server-validated-hit-detection end to end over a real WebSocket
## connection between separate processes. No cover, no powers, no HUD yet
## — those layer onto this once the core netcode loop is solid.
##
## Must already be the running scene (instantiated and in the tree) BEFORE
## Network.host()/join() is called, so the MultiplayerSpawner exists in
## time to receive the server's spawn replication.

const NET_PLAYER_SCENE := "res://scenes/net/net_player.tscn"

## Server-only hard cap matching the design doc's "up to 5 players per
## match" FFA figure — rejecting connections past this is a follow-up once
## there's an actual lobby to show "match full" in; left as a constant
## here so it's one obvious place to wire that into later.
const MAX_PLAYERS := 5

@export var arena_bounds := Rect2(Vector2.ZERO, Vector2(960, 640))

@onready var players_root: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

var _spawn_points := [
	Vector2(80, 80), Vector2(880, 80), Vector2(80, 560), Vector2(880, 560), Vector2(480, 320),
]


func _ready() -> void:
	spawner.spawn_path = players_root.get_path()
	spawner.spawn_function = _spawn_player

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_on_became_server()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Called once the server's own host() has actually attached a peer. Covers
## both orderings (arena ready before host(), or host() before this arena
## is instantiated) since net_arena.gd can be dropped in after hosting too.
func _on_became_server() -> void:
	_spawn_for_peer(1)
	for id in multiplayer.get_peers():
		_spawn_for_peer(id)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_for_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var node := players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()


func _spawn_for_peer(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	spawner.spawn(id)


func _spawn_player(id: int) -> Node:
	var scene: PackedScene = load(NET_PLAYER_SCENE)
	var player := scene.instantiate() as NetPlayer
	player.name = str(id)
	player.owner_peer_id = id
	player.position = _spawn_point(id)
	player.configure_replication()
	return player


func _spawn_point(id: int) -> Vector2:
	return _spawn_points[id % _spawn_points.size()]
