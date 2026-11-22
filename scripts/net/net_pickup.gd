extends Node2D
class_name NetPickup
## Something lying on the arena floor. Three kinds:
##   "ammo"    rounds in a crate (or dropped by a player); walk over it
##   "health"  a medical station; stand beside it for a few seconds to heal
##   "gen"     the Gen a dead player left behind; take it with a key (see net_player.gd)
## Created and run by NetPickups (net_pickups.gd) on the host; every peer just
## draws it. A station's progress and cooldown are replicated so everyone sees
## the ring fill.

const RADIUS := 26.0  # how close you have to be to touch an ammo crate
const GEN_COLORS := {
	"shield": Color(0.4, 0.9, 1.0), "camouflage": Color(0.5, 0.85, 0.45), "poltergeist": Color(0.8, 0.4, 1.0),
	"blackout": Color(0.55, 0.6, 0.95), "bomb_voyage": Color(1.0, 0.55, 0.2), "decoy": Color(1.0, 0.85, 0.35),
}

var kind := "ammo"
var amount := 0  # rounds, for "ammo"
var gen_key := ""  # for "gen"

# --- host only ---
var ttl := INF  # seconds until it disappears (dropped things don't last forever)
var site := -1  # index of the map spot it respawns at, or -1 for a one-off drop
var ignore_id := 0  # who dropped it: can't pick it straight back up...
var ignore_until := 0.0  # ...until this time (seconds on the host's clock)
var user_id := 0  # the player a station is currently healing

# --- replicated by the host ---
var charge := 0.0  # 0..1, how far through healing the person standing there is
var cooldown_left := 0.0  # a station recharges after use

var _clock := 0.0


func configure_replication() -> void:
	var sync := get_node("MultiplayerSynchronizer") as MultiplayerSynchronizer
	var config := SceneReplicationConfig.new()
	for prop in ["charge", "cooldown_left"]:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	sync.replication_config = config
	sync.replication_interval = 0.1


func _ready() -> void:
	add_to_group("net_pickup")  # drawn above the map picture and under the characters, by tree order


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	match kind:
		"ammo":
			_draw_ammo()
		"health":
			_draw_station()
		"gen":
			_draw_gen()


func _draw_ammo() -> void:
	draw_circle(Vector2(2, 3), 15.0, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-12, -8, 24, 16), Color(0.30, 0.34, 0.2))
	draw_rect(Rect2(-12, -8, 24, 16), Color(0.14, 0.16, 0.1), false, 2.0)
	for i in 4:  # a row of brass rounds
		draw_rect(Rect2(-8 + i * 5, -4, 3, 8), Color(0.88, 0.7, 0.28))
	var text := "+%d" % amount
	draw_string(ThemeDB.fallback_font, Vector2(-12, -13), text, HORIZONTAL_ALIGNMENT_CENTER, 24.0, 12, Color(1, 0.92, 0.6))


func _draw_station() -> void:
	var is_ready := cooldown_left <= 0.0
	var tint := Color(0.35, 0.85, 0.5) if is_ready else Color(0.45, 0.47, 0.5)
	draw_circle(Vector2(2, 3), 24.0, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, 22.0, Color(0.1, 0.12, 0.12, 0.92))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, tint, 2.5)
	draw_rect(Rect2(-4, -12, 8, 24), Color(0.92, 0.95, 0.92) if is_ready else Color(0.55, 0.57, 0.6))  # a cross
	draw_rect(Rect2(-12, -4, 24, 8), Color(0.92, 0.95, 0.92) if is_ready else Color(0.55, 0.57, 0.6))
	if charge > 0.0:
		draw_arc(Vector2.ZERO, 29.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 40, Color(0.5, 1.0, 0.65), 4.0)
	elif is_ready:
		draw_arc(Vector2.ZERO, 29.0, 0.0, TAU, 32, Color(0.35, 0.85, 0.5, 0.18 + 0.12 * sin(_clock * 2.5)), 2.0)


func _draw_gen() -> void:
	var color: Color = GEN_COLORS.get(gen_key, Color.WHITE)
	var pulse := 0.5 + 0.5 * sin(_clock * 3.0)
	draw_circle(Vector2.ZERO, 22.0 + 4.0 * pulse, Color(color, 0.12 + 0.1 * pulse))
	draw_circle(Vector2.ZERO, 11.0, Color(0.06, 0.06, 0.08, 0.95))
	draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 24, color, 3.0)
	draw_circle(Vector2.ZERO, 4.5, color)
	draw_string(ThemeDB.fallback_font, Vector2(-60, -22), Gens.label(gen_key), HORIZONTAL_ALIGNMENT_CENTER, 120.0, 13, Color(color, 0.95))
