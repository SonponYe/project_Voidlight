extends Area2D
## Generic timed powerup pickup. One script covers every powerup type —
## set `effect`, `duration`, and `strength` per instance in the Inspector.
## Each effect gets both a distinct color AND a distinct silhouette (not
## just a recolored diamond) so what a pickup does is readable at a glance
## even before real icon art replaces these placeholders.
##
## strength's meaning depends on effect:
##   SPEED_BOOST   -> move speed multiplier (e.g. 1.6 = 60% faster)
##   INVINCIBILITY -> ignored
##   LIGHT_BOOST   -> flashlight range multiplier (e.g. 1.5 = 50% further)
##   STEALTH       -> ignored

enum Effect { SPEED_BOOST, INVINCIBILITY, LIGHT_BOOST, STEALTH }

const EFFECT_NAMES := {
	Effect.SPEED_BOOST: "speed",
	Effect.INVINCIBILITY: "invincible",
	Effect.LIGHT_BOOST: "light_boost",
	Effect.STEALTH: "stealth",
}

const PLACEHOLDER_COLORS := {
	Effect.SPEED_BOOST: Color(0.3, 0.9, 1.0, 1.0),
	Effect.INVINCIBILITY: Color(1.0, 0.85, 0.2, 1.0),
	Effect.LIGHT_BOOST: Color(1.0, 0.75, 0.2, 1.0),
	Effect.STEALTH: Color(0.55, 0.25, 0.85, 1.0),
}

# Lightning bolt / shield / 8-point sunburst / 4-point "sneak" star — chosen
# so the silhouette alone hints at the effect, not just the color. A plain
# var, not const: GDScript won't constant-fold PackedVector2Array(Array).
var PLACEHOLDER_SHAPES := {
	Effect.SPEED_BOOST: PackedVector2Array([
		Vector2(2, -12), Vector2(6, -2), Vector2(1, -2), Vector2(5, 3),
		Vector2(-2, 12), Vector2(-5, 1), Vector2(-1, 1), Vector2(-4, -12),
	]),
	Effect.INVINCIBILITY: PackedVector2Array([
		Vector2(-9, -10), Vector2(9, -10), Vector2(9, -2), Vector2(0, 13), Vector2(-9, -2),
	]),
	Effect.LIGHT_BOOST: PackedVector2Array([
		Vector2(12.0, 0.0), Vector2(4.6, 1.9), Vector2(8.5, 8.5), Vector2(1.9, 4.6),
		Vector2(0.0, 12.0), Vector2(-1.9, 4.6), Vector2(-8.5, 8.5), Vector2(-4.6, 1.9),
		Vector2(-12.0, 0.0), Vector2(-4.6, -1.9), Vector2(-8.5, -8.5), Vector2(-1.9, -4.6),
		Vector2(0.0, -12.0), Vector2(1.9, -4.6), Vector2(8.5, -8.5), Vector2(4.6, -1.9),
	]),
	Effect.STEALTH: PackedVector2Array([
		Vector2(9.2, 9.2), Vector2(0.0, 4.0), Vector2(-9.2, 9.2), Vector2(-4.0, 0.0),
		Vector2(-9.2, -9.2), Vector2(-0.0, -4.0), Vector2(9.2, -9.2), Vector2(4.0, -0.0),
	]),
}

@export var effect: Effect = Effect.SPEED_BOOST
@export var duration := 8.0
@export var strength := 1.6

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	visual.color = PLACEHOLDER_COLORS[effect]
	visual.polygon = PLACEHOLDER_SHAPES[effect]


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("apply_powerup"):
		body.apply_powerup(EFFECT_NAMES[effect], duration, strength)
		# Freeing self (a CollisionObject2D) from inside this physics signal
		# directly is blocked by the engine — defer it.
		call_deferred("queue_free")
