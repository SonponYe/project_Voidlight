extends Node2D
## The online match arena. Server-authoritative: the host spawns every
## player, tracks eliminations, decides the winner, and tells everyone.
## Clients just report "my arena is loaded" and then render what the
## server replicates. No cover, no Gens, no darkness yet — those layer on
## once this plain deathmatch loop is solid online.
##
## Entered via Network.start_match() from the lobby, so the connection and
## roster already exist by the time _ready() runs here.

const NET_PLAYER_SCENE := "res://scenes/net/net_player.tscn"

## How long the host waits for every client to load the arena before
## starting without the stragglers. A spawn sent to a peer whose arena
## isn't loaded is lost, not queued, so late peers can only spectate.
const READY_TIMEOUT_SEC := 8.0

@onready var players_root: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: CanvasLayer = $NetHUD
@onready var camera: Camera2D = $Camera

## Floor-cell centers of the Maze layout: the four corners, then the middle.
var _spawn_points := [
	Vector2(96, 96), Vector2(1440, 96), Vector2(96, 928), Vector2(1440, 928), Vector2(800, 480),
]
var _match_started := false
var _match_over := false
## A match that started with a single player is a sandbox, never "won".
var _is_contest := false
var _participants: Array[int] = []


func _ready() -> void:
	spawner.spawn_path = players_root.get_path()
	spawner.spawn_function = _spawn_player
	hud.return_pressed.connect(_on_return_pressed)
	hud.leave_pressed.connect(_on_leave_pressed)
	Network.disconnected_from_server.connect(_on_lost_server)

	if Network.is_host():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		hud.set_status("Waiting for players to load...")
		_await_ready_peers()
	else:
		hud.set_status("Loading...")
		Network.report_arena_ready()


func _exit_tree() -> void:
	if Network.disconnected_from_server.is_connected(_on_lost_server):
		Network.disconnected_from_server.disconnect(_on_lost_server)


func _process(_delta: float) -> void:
	var me := _local_player()
	_update_vision(me)
	if me:
		camera.global_position = me.global_position
	_update_hud(me)


# ---------------------------------------------------------------------------
# Vision (every peer, about its own view)
# ---------------------------------------------------------------------------

## The map is always visible; other players are not. You see an enemy only
## when they're close, or ahead of you inside your view cone, with nothing
## solid in between — or when they just gave themselves away by firing.
## Spectators (dead) see everyone. This is client-side culling: the server
## still replicates every position, so it's a presentation rule for now,
## not an anti-cheat one.
func _update_vision(me: NetPlayer) -> void:
	for p in players_root.get_children():
		if not p is NetPlayer or p == me:
			continue
		p.visible = me == null or me.dead or _can_see(me, p)


func _can_see(me: NetPlayer, other: NetPlayer) -> bool:
	if other.reveal_timer > 0.0:
		return true
	var offset := other.global_position - me.global_position
	var dist := offset.length()
	if dist > NetPlayer.VIEW_RANGE:
		return false
	if dist > NetPlayer.VISION_RADIUS \
			and absf(angle_difference(me.rotation, offset.angle())) > NetPlayer.VIEW_HALF_ANGLE:
		return false
	var query := PhysicsRayQueryParameters2D.create(me.global_position, other.global_position, 1)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# ---------------------------------------------------------------------------
# Match start (host)
# ---------------------------------------------------------------------------

func _await_ready_peers() -> void:
	var deadline := Time.get_ticks_msec() + int(READY_TIMEOUT_SEC * 1000.0)
	while not _all_clients_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	_begin_match()


func _all_clients_ready() -> bool:
	for id in Network.players:
		if id != 1 and not Network.ready_peers.has(id):
			return false
	return true


func _begin_match() -> void:
	if _match_started:
		return
	_match_started = true
	_spawn_for_peer(1)
	for id in Network.players:
		if id != 1 and Network.ready_peers.has(id):
			_spawn_for_peer(id)
	_is_contest = _participants.size() >= 2
	_set_status.rpc("Fight!")
	_check_win()


func _spawn_for_peer(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var data := {"id": id, "spawn": _participants.size() % _spawn_points.size()}
	var node := spawner.spawn(data) as NetPlayer
	node.died.connect(_on_player_died)
	_participants.append(id)


## Runs on every peer with the same data, so the spawn slot travels with it
## rather than being derived from server-only state.
func _spawn_player(data: Dictionary) -> Node:
	var scene: PackedScene = load(NET_PLAYER_SCENE)
	var player := scene.instantiate() as NetPlayer
	player.name = str(data["id"])
	player.owner_peer_id = data["id"]
	player.position = _spawn_points[data["spawn"]]
	player.configure_replication()
	return player


# ---------------------------------------------------------------------------
# Eliminations / win (host)
# ---------------------------------------------------------------------------

func _on_player_died(id: int) -> void:
	_announce.rpc("%s was eliminated" % Network.player_name(id))
	_check_win()


func _on_peer_disconnected(id: int) -> void:
	var node := players_root.get_node_or_null(str(id))
	if node:
		node.queue_free()
	if _match_started:
		_announce.rpc("%s left the match" % Network.player_name(id))
	_participants.erase(id)
	_check_win()


func _alive_ids() -> Array[int]:
	var alive: Array[int] = []
	for id in _participants:
		var node := players_root.get_node_or_null(str(id)) as NetPlayer
		if node and not node.dead and not node.is_queued_for_deletion():
			alive.append(id)
	return alive


func _check_win() -> void:
	if not _match_started or _match_over or not _is_contest:
		return
	var alive := _alive_ids()
	if alive.size() > 1:
		return
	_match_over = true
	var text := "Nobody survived."
	if alive.size() == 1:
		text = "%s wins!" % Network.player_name(alive[0])
	_show_results.rpc(text)


# ---------------------------------------------------------------------------
# Broadcasts (host -> everyone, including itself)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _set_status(text: String) -> void:
	hud.set_status(text)


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	hud.announce(text)


@rpc("authority", "call_local", "reliable")
func _show_results(text: String) -> void:
	_match_over = true
	hud.show_results(text, Network.is_host())


# ---------------------------------------------------------------------------
# HUD / leaving
# ---------------------------------------------------------------------------

func _local_player() -> NetPlayer:
	if not multiplayer.has_multiplayer_peer():
		return null
	return players_root.get_node_or_null(str(multiplayer.get_unique_id())) as NetPlayer


func _update_hud(me: NetPlayer) -> void:
	var alive := 0
	var total := 0
	for child in players_root.get_children():
		if child is NetPlayer:
			total += 1
			if not child.dead:
				alive += 1
	hud.set_alive(alive, total)
	if me:
		hud.set_hp(me.hp, me.max_hp)
		if me.dead and not _match_over:
			hud.set_status("You were eliminated — spectating")


func _on_lost_server() -> void:
	hud.show_results("Lost connection to the host.", false)


## Host only. Despawn the players BEFORE switching scenes: if the arena is
## simply freed, its despawn packets reach clients after they've already
## torn down their own arena, and every one logs an ERR_UNAUTHORIZED.
func _on_return_pressed() -> void:
	for child in players_root.get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Network.return_to_lobby()


func _on_leave_pressed() -> void:
	Network.leave()
	get_tree().change_scene_to_file(Network.LOBBY_SCENE)
