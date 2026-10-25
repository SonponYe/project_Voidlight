extends Area2D
## Generic timed powerup pickup. One script covers every powerup type —
## set `effect`, `duration`, and `strength` per instance in the Inspector.
## Placeholder diamond visual; swap for real icons per instance later.
##
## strength's meaning depends on effect:
##   SPEED_BOOST  -> move speed multiplier (e.g. 1.6 = 60% faster)
##   INVINCIBILITY -> ignored
##   LIGHT_BOOST  -> flashlight range multiplier (e.g. 1.5 = 50% further)

enum Effect { SPEED_BOOST, INVINCIBILITY, LIGHT_BOOST }

const EFFECT_NAMES := {
	Effect.SPEED_BOOST: "speed",
	Effect.INVINCIBILITY: "invincible",
	Effect.LIGHT_BOOST: "light_boost",
}

@export var effect: Effect = Effect.SPEED_BOOST
@export var duration := 8.0
@export var strength := 1.6

const PLACEHOLDER_COLORS := {
	Effect.SPEED_BOOST: Color(0.3, 0.9, 1.0, 1.0),
	Effect.INVINCIBILITY: Color(1.0, 0.85, 0.2, 1.0),
	Effect.LIGHT_BOOST: Color(1.0, 0.6, 0.9, 1.0),
}

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	visual.color = PLACEHOLDER_COLORS[effect]


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("apply_powerup"):
		body.apply_powerup(EFFECT_NAMES[effect], duration, strength)
		# Freeing self (a CollisionObject2D) from inside this physics signal
		# directly is blocked by the engine — defer it.
		call_deferred("queue_free")
