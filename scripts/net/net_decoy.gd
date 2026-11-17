extends CharacterBody2D
class_name NetDecoy
## The online Decoy Gen: a clone of the caster (same color, same name tag, so
## enemies can't tell it from a player) that hunts one enemy through the maze.
## Host-simulated only; clients just glide it to the replicated position.
## Dies to any enemy's shots, expires on its own, and is invisible to enemies
## under the same limited-vision rule as players.

const SPEED := 125.0
const CONTACT_RANGE := 26.0
const CONTACT_COOLDOWN := 0.8
const REPATH_INTERVAL := 0.4
const REPLICATION_INTERVAL := 0.05
const SMOOTH := 18.0
const TELEPORT_DIST := 300.0
const FRIEND_RING := Color(1.0, 1.0, 1.0, 0.35)

var owner_peer_id := 0
var team := 0
var target_id := 0
var display_name := ""
var color := Color.WHITE
var lifespan := 20.0

# Replicated by the host.
var hp := 3
var net_pos := Vector2.ZERO
var net_rot := 0.0

var dead := false
var reveal_timer := 0.0  # players have one; vision code treats both alike
var _path := PackedVector2Array()
var _repath := 0.0
var _hit_cooldown := 0.0

@onready var visual: Polygon2D = $Visual
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	net_pos = position
	net_rot = rotation
	visual.color = color
	name_label.text = display_name
	add_to_group("net_decoy")


## Same spawn-time rule as NetPlayer: the replication config must exist
## before the node enters the tree.
func configure_replication() -> void:
	var sync := get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config := SceneReplicationConfig.new()
	for prop in ["net_pos", "net_rot", "hp"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	sync.replication_interval = REPLICATION_INTERVAL


func is_enemy_of(player: NetPlayer) -> bool:
	return player.owner_peer_id != owner_peer_id and (team == 0 or player.team != team)


func _is_friendly() -> bool:
	return multiplayer.has_multiplayer_peer() and owner_peer_id == multiplayer.get_unique_id()


func _draw() -> void:
	if _is_friendly():
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, FRIEND_RING, 1.5)


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	name_label.rotation = -rotation
	if _is_friendly():
		queue_redraw()
	if multiplayer.is_server():
		return
	if position.distance_to(net_pos) > TELEPORT_DIST:
		position = net_pos
	else:
		position = position.lerp(net_pos, 1.0 - exp(-delta * SMOOTH))
	rotation = lerp_angle(rotation, net_rot, 1.0 - exp(-delta * SMOOTH))


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or dead:
		return
	lifespan -= delta
	if lifespan <= 0.0:
		_remove()
		return

	var arena := get_parent().get_parent()
	var target: NetPlayer = arena.player_node(target_id)
	if target == null or target.dead:
		velocity = Vector2.ZERO
	else:
		_repath -= delta
		if _repath <= 0.0:
			_repath = REPATH_INTERVAL
			_path = arena.find_path(global_position, target.global_position)
		while _path.size() > 0 and global_position.distance_to(_path[0]) < 10.0:
			_path.remove_at(0)
		var heading := Vector2.ZERO
		if _path.size() > 0:
			heading = (_path[0] - global_position).normalized()
		elif global_position.distance_to(target.global_position) > CONTACT_RANGE:
			heading = (target.global_position - global_position).normalized()
		velocity = heading * SPEED
		if heading != Vector2.ZERO:
			rotation = heading.angle()
		_hit_cooldown -= delta
		if _hit_cooldown <= 0.0 and global_position.distance_to(target.global_position) <= CONTACT_RANGE:
			_hit_cooldown = CONTACT_COOLDOWN
			target.apply_damage(1)
	move_and_slide()
	net_pos = position
	net_rot = rotation


## Host only. Called by an enemy's shot.
func apply_damage(amount: int) -> void:
	if not multiplayer.is_server() or dead:
		return
	hp -= amount
	if hp <= 0:
		_remove()


func _remove() -> void:
	dead = true
	queue_free()
