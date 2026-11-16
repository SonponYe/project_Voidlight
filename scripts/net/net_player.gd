extends CharacterBody2D
class_name NetPlayer
## A networked player avatar. Deliberately minimal — no flashlight, powers,
## or HUD yet, those belong to player.gd's local-multiplayer feature set and
## layer on top once this core loop (connect/spawn/move/shoot/damage) is
## proven solid over a real network, not just in one process's tree.
##
## Authority model (first pass, documented tradeoff):
## - The SERVER simulates every player's movement from received input and
##   is the authoritative source of position/rotation/hp, replicated to
##   everyone via the MultiplayerSynchronizer below (default authority is
##   always peer 1 = server, so no set_multiplayer_authority() call needed).
## - The OWNING client ALSO simulates its own movement locally, immediately,
##   so input feels instant instead of waiting a round-trip — this is
##   "prediction." It does not yet reconcile/smooth against the server's
##   replicated correction when they briefly disagree (e.g. under packet
##   loss); the raw snap is visible. That smoothing is a follow-up, not
##   required for the netcode itself to be correct.
## - Hits are server-authoritative: a client's shoot press only ever SENDS
##   a request; the server alone raycasts and decides damage.

signal died(owner_peer_id: int)

@export var speed := 160.0
@export var max_hp := 5
@export var shoot_range := 400.0

## Set once at spawn time (net_arena.gd) — which peer this avatar belongs
## to. Not multiplayer authority (that's always the server); just "whose
## input do I predict locally and whose shoot requests do I accept."
var owner_peer_id: int = 1

var hp: int
var dead := false

var _input_dir := Vector2.ZERO


func _ready() -> void:
	hp = max_hp
	add_to_group("net_player")


## The MultiplayerSynchronizer needs its replication_config set BEFORE this
## node is added to the tree — the engine wires up spawn-replication as
## part of add_child() itself, ahead of this node's own _ready(), so
## building the config here (in _ready()) loses that race and corrupts the
## peer's replication state (ERR_UNCONFIGURED, then a dropped connection).
## net_arena.gd's spawn function calls this right after instantiate(),
## before the node is returned/added, which is early enough.
func configure_replication() -> void:
	var sync := get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config := SceneReplicationConfig.new()
	for prop in ["position", "rotation", "hp", "dead"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config


func _is_mine() -> bool:
	return owner_peer_id == multiplayer.get_unique_id()


func _physics_process(_delta: float) -> void:
	if dead:
		return

	if _is_mine():
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if dir != _input_dir:
			_input_dir = dir
			_send_input.rpc_id(1, dir)
		velocity = dir * speed
		move_and_slide()
		if dir.length() > 0.2:
			rotation = dir.angle()
		if Input.is_action_just_pressed("shoot"):
			_request_shoot.rpc_id(1, global_position, rotation)
		return

	# Remote avatars (including the server's own view of every client):
	# only the server actually drives movement from received input; a
	# client rendering ANOTHER player just displays whatever position the
	# synchronizer last replicated, so it does nothing here.
	if multiplayer.is_server():
		velocity = _input_dir * speed
		move_and_slide()
		if _input_dir.length() > 0.2:
			rotation = _input_dir.angle()


@rpc("any_peer", "reliable")
func _send_input(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return  # a peer can only drive the avatar it owns
	_input_dir = dir.limit_length(1.0)


@rpc("any_peer", "reliable")
func _request_shoot(from: Vector2, aim: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	if dead:
		return
	var space_state := get_world_2d().direct_space_state
	var to := from + Vector2.RIGHT.rotated(aim) * shoot_range
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	if result and result.collider is NetPlayer:
		var target: NetPlayer = result.collider
		target.apply_damage(1)


## Server-only, direct call (not an RPC) — the server already holds the
## authoritative NetPlayer instance, so it just mutates it; the
## MultiplayerSynchronizer's own replication (hp/dead, ALWAYS mode above)
## is what actually informs every client, no separate RPC needed.
func apply_damage(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if dead:
		return
	hp -= amount
	if hp <= 0:
		dead = true
		died.emit(owner_peer_id)
