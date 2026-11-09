extends Control
## Local 2-player PvP arena. No shared camera — each player gets their own
## split-screen half (two SubViewports sharing one World2D, each with its
## own Camera2D locked to one player), so neither sees more of the arena
## than they'd see alone. Last player with HP left wins.

@onready var p1_viewport: SubViewport = $VBox/P1Container/P1Viewport
@onready var p2_viewport: SubViewport = $VBox/P2Container/P2Viewport
@onready var p2_camera: Camera2D = $VBox/P2Container/P2Viewport/P2Camera
@onready var player1: CharacterBody2D = $VBox/P1Container/P1Viewport/Player1
@onready var player2: CharacterBody2D = $VBox/P1Container/P1Viewport/Player2
@onready var nav_region: NavigationRegion2D = $VBox/P1Container/P1Viewport/NavRegion

@onready var p1_hp_bar: ProgressBar = $P1HUD/HPBar
@onready var p1_ammo_label: Label = $P1HUD/AmmoLabel
@onready var p2_hp_bar: ProgressBar = $P2HUD/HPBar
@onready var p2_ammo_label: Label = $P2HUD/AmmoLabel

@onready var results: Control = $ResultsOverlay
@onready var results_label: Label = $ResultsOverlay/VBox/ResultLabel

@export var arena_bounds := Rect2(Vector2.ZERO, Vector2(1280, 896))

var _match_over := false


func _ready() -> void:
	# Split-screen: player 2's half renders the exact same live World2D as
	# player 1's (same players/walls/bullets, not a duplicate), just through
	# its own camera — this is what makes it one shared arena instead of two
	# disconnected copies.
	p2_viewport.world_2d = p1_viewport.world_2d
	_bake_navigation()

	p1_hp_bar.max_value = player1.hp
	p1_hp_bar.value = player1.hp
	p1_ammo_label.text = "Ammo: %d" % player1.ammo
	p2_hp_bar.max_value = player2.hp
	p2_hp_bar.value = player2.hp
	p2_ammo_label.text = "Ammo: %d" % player2.ammo

	player1.hp_changed.connect(func(hp): p1_hp_bar.value = hp)
	player1.ammo_changed.connect(func(a): p1_ammo_label.text = "Ammo: %d" % a)
	player2.hp_changed.connect(func(hp): p2_hp_bar.value = hp)
	player2.ammo_changed.connect(func(a): p2_ammo_label.text = "Ammo: %d" % a)

	player1.died.connect(_on_player_died.bind(1))
	player2.died.connect(_on_player_died.bind(2))

	results.hide()


func _process(_delta: float) -> void:
	if is_instance_valid(player2):
		p2_camera.global_position = player2.global_position


func _bake_navigation() -> void:
	var poly := NavigationPolygon.new()
	poly.add_outline(PackedVector2Array([
		arena_bounds.position,
		Vector2(arena_bounds.end.x, arena_bounds.position.y),
		arena_bounds.end,
		Vector2(arena_bounds.position.x, arena_bounds.end.y),
	]))
	poly.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	poly.parsed_collision_mask = 1
	poly.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	poly.source_geometry_group_name = "walls"
	nav_region.navigation_polygon = poly
	nav_region.bake_navigation_polygon(false)


func _on_player_died(loser_index: int) -> void:
	if _match_over:
		return
	_match_over = true
	get_tree().paused = false
	var winner := 2 if loser_index == 1 else 1
	results_label.text = "PLAYER %d WINS" % winner
	results.show()


func _on_rematch_pressed() -> void:
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
