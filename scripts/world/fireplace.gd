extends Area2D
## Walk into it to ignite: consumes one of Globals.lighter_charges and lights
## a large omnidirectional radius — bigger than the player's own torch —
## for burn_duration seconds, then goes dark again, same as it was before.
## The player's own flashlight toggle and movement are completely
## independent of this; lighting one doesn't lock you in place or touch
## your torch, it's just a second, temporary, much bigger light source.

@export var burn_duration := 15.0
@export var light_radius := 420.0
@export var ember_radius := 50.0

const _TEX_SIZE := 256
const _TEX_RANGE := 240.0

@onready var glow: PointLight2D = $FirelightGlow
@onready var ember_glow: PointLight2D = $EmberGlow
@onready var flame_audio: AudioStreamPlayer2D = $FlameAudio

var _lit := false
var _burn_timer := 0.0


func _ready() -> void:
	add_to_group("landmarks")
	body_entered.connect(_on_body_entered)
	glow.texture = _build_radial_texture(1.0, 0.7, 0.35)
	glow.texture_scale = light_radius / _TEX_RANGE
	glow.enabled = false
	# Always on, small and dim — so an unlit fireplace is still spottable
	# from a short distance instead of being invisible until you're on top
	# of it, the same way the player's own ambient glow works.
	ember_glow.texture = _build_radial_texture(1.0, 0.45, 0.2)
	ember_glow.texture_scale = ember_radius / _TEX_RANGE
	ember_glow.enabled = true


func _physics_process(delta: float) -> void:
	if not _lit:
		return
	_burn_timer -= delta
	if _burn_timer <= 0.0:
		_extinguish()


func _on_body_entered(body: Node) -> void:
	if _lit or not body.is_in_group("player"):
		return
	if Globals.lighter_charges <= 0:
		return
	Globals.lighter_charges -= 1
	_ignite()


func _ignite() -> void:
	_lit = true
	_burn_timer = burn_duration
	glow.enabled = true
	if flame_audio and flame_audio.stream:
		flame_audio.play()


func _extinguish() -> void:
	_lit = false
	glow.enabled = false
	if flame_audio:
		flame_audio.stop()


## Soft circular falloff, no angle restriction (unlike the player's cone) —
## built once per fireplace the same way the player builds its own cookies.
func _build_radial_texture(r: float, g: float, b: float) -> ImageTexture:
	var img := Image.create(_TEX_SIZE, _TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := _TEX_SIZE / 2.0
	for y in _TEX_SIZE:
		for x in _TEX_SIZE:
			var dist := Vector2(x - c, y - c).length()
			var a := 0.0
			if dist <= _TEX_RANGE:
				a = 1.0 - smoothstep(_TEX_RANGE * 0.5, _TEX_RANGE, dist)
			img.set_pixel(x, y, Color(r, g, b, a))
	return ImageTexture.create_from_image(img)
