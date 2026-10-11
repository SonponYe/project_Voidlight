extends Area2D
## Health pickup: restores 1 HP and despawns.

@export var heal_amount := 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("heal"):
		body.heal(heal_amount)
		# Freeing self (a CollisionObject2D) from inside this physics signal
		# directly is blocked by the engine — defer it.
		call_deferred("queue_free")
