class_name Gens
extends RefCounted
## The online Gen roster — the single source of truth the lobby, the HUD,
## and the server-side activation logic in net_player.gd all read from.
## Deliberately separate from Globals.POWER_DEFS: the local Versus mode
## keeps its original mechanics untouched, these are the redesigned ones.

const DEFS := {
	"shield": {
		"label": "Shield", "duration": 30.0, "cooldown": 25.0, "shield_hp": 4, "available": true,
		"blurb": "A 360° shield that soaks 4 hits, for up to 30s.",
	},
	"camouflage": {
		"label": "Camouflage", "duration": 60.0, "cooldown": 20.0, "available": true,
		"blurb": "Look like a crate for up to 60s. Move and scout freely, but you can't shoot until you drop it.",
	},
	"poltergeist": {
		"label": "Poltergeist", "duration": 20.0, "cooldown": 25.0, "available": true,
		"blurb": "Haunt the nearest enemy: you always see where they are for 20s.",
	},
	"blackout": {
		"label": "Blackout", "duration": 30.0, "cooldown": 40.0, "available": true,
		"blurb": "Everyone else goes blind for 30s. You get night vision.",
	},
	"bomb_voyage": {
		"label": "Bomb Voyage", "duration": 0.0, "cooldown": 1.0, "max_bombs": 5, "available": true,
		"blurb": "Up to 5 bombs. Tap: proximity. Hold: manual. Only you see them.",
	},
	"decoy": {
		"label": "Decoy", "duration": 0.0, "cooldown": 18.0, "available": false,
		"blurb": "A clone that hunts one enemy. (Online version coming.)",
	},
}
const DEFAULT := "shield"


static func is_valid(key: String) -> bool:
	return DEFS.has(key) and DEFS[key]["available"]


static func label(key: String) -> String:
	return DEFS[key]["label"] if DEFS.has(key) else key


static func def(key: String) -> Dictionary:
	return DEFS.get(key, DEFS[DEFAULT])
