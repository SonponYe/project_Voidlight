extends Area2D
## Ammo pickup: grants Globals.AMMO_PICKUP_AMOUNT rounds and despawns.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("add_ammo"):
		body.add_ammo(Globals.AMMO_PICKUP_AMOUNT)
		# Freeing self (a CollisionObject2D) from inside this physics signal
		# directly is blocked by the engine — defer it.
		call_deferred("queue_free")
