extends Enemy
class_name Crawler
## Faster than the Walker in HUNT state (introduced Level 2).
## Low to the ground, harder to see in tight corridors.

const HUNT_SPEED_MULTIPLIER := 1.8


func _ready() -> void:
	hunt_speed *= HUNT_SPEED_MULTIPLIER
	super._ready()
