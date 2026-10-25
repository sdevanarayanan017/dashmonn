extends Node3D

@export var track_item_scene: PackedScene = preload("res://track_item.tscn")
@export var chaser_scene: PackedScene = preload("res://enemy.tscn")
var falling_tree_script = preload("res://falling_tree.gd")

# --- Gameplay Stats ---
var coins_collected: int = 0
var score: int = 0
var distance_traveled: float = 0.0
var game_active: bool = false   # Starts false — game only begins after Start Run is pressed
var game_started: bool = false  # Whether the player has left the main menu
var high_score: int = 0         # Persisted across runs

const SAVE_PATH: String = "user://dashmon_highscore.dat"

# --- Procedural Road Track ---
const SEGMENT_LENGTH: float = 40.0
const NUM_SEGMENTS: int = 8
var next_spawn_z: float = 0.0
var active_segments: Array[Node3D] = []
var segments_since_last_falling_tree: int = 0

# --- 3D Materials for Scenery ---
var road_material: StandardMaterial3D
var wall_material: StandardMaterial3D
var grass_material: StandardMaterial3D
var house_wall_mat: StandardMaterial3D
var house_roof_mat: StandardMaterial3D
var tree_wood_mat: StandardMaterial3D
var tree_leaf_mat: StandardMaterial3D

# --- Node References ---
@onready var player: CharacterBody3D = $Player
@onready var chaser: Area3D = $Chaser
@onready var score_label: Label = $CanvasLayer/UI/TopLeft/ScoreLabel
@onready var coins_label: Label = $CanvasLayer/UI/TopLeft/CoinsLabel
@onready var speed_label: Label = $CanvasLayer/UI/TopLeft/SpeedLabel
@onready var token_progress_bar: ProgressBar = $CanvasLayer/UI/TopLeft/TokenBar
@onready var token_status_label: Label = $CanvasLayer/UI/TopLeft/TokenStatus
@onready var popup_container: Control = $CanvasLayer/UI/Popups
@onready var chaser_warning_label: Label = $CanvasLayer/UI/ChaserWarning
@onready var main_menu_panel: Control = $CanvasLayer/MainMenuPanel
@onready var game_over_panel: Control = $CanvasLayer/GameOverPanel
@onready var game_over_score_label: Label = $CanvasLayer/GameOverPanel/VBox/Body/FinalScoreLabel
@onready var game_over_dist_label: Label = $CanvasLayer/GameOverPanel/VBox/Body/FinalDistLabel

var grapple_label: Label
var grapple_bar: ProgressBar

func _ready() -> void:
	_load_highscore()
	init_materials()
	_setup_grapple_ui()
	game_over_panel.visible = false
	main_menu_panel.visible = true

	# Spawn initial runway of village road segments ahead
	for i in range(NUM_SEGMENTS):
		spawn_road_segment()

	# Position chaser behind player at the start
	if chaser and player:
		chaser.global_position = player.global_position + Vector3(0, 0, 7.0)

	# Freeze everything until Start Run is pressed
	if player:
		player.set_physics_process(false)
		player.set_process(false)
	if chaser:
		chaser.set_physics_process(false)

func _setup_grapple_ui() -> void:
	var top_left = get_node_or_null("CanvasLayer/UI/TopLeft")
	if not top_left:
		return

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	top_left.add_child(spacer)

	grapple_label = Label.new()
	grapple_label.text = "⚡ [F / Y] GRAPPLE HOOK READY!"
	grapple_label.modulate = Color(1.0, 0.25, 0.65)
	grapple_label.add_theme_font_size_override("font_size", 18)
	top_left.add_child(grapple_label)

	grapple_bar = ProgressBar.new()
	grapple_bar.custom_minimum_size = Vector2(300, 14)
	grapple_bar.show_percentage = false
	grapple_bar.max_value = 100.0
	grapple_bar.value = 100.0

	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.12, 0.05, 0.16, 0.85)
	style_bg.set_corner_radius_all(5)
	grapple_bar.add_theme_stylebox_override("background", style_bg)

	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = Color(1.0, 0.18, 0.58, 1.0) # Vivid neon pink / magenta (Card 3)
	style_fill.set_corner_radius_all(5)
	grapple_bar.add_theme_stylebox_override("fill", style_fill)

	top_left.add_child(grapple_bar)

func init_materials() -> void:
	# Village dirt / cobblestone road
	road_material = StandardMaterial3D.new()
	road_material.albedo_color = Color(0.42, 0.32, 0.24, 1.0)
	road_material.roughness = 0.95

	# Village wooden fence borders
	wall_material = StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.26, 0.17, 0.11, 1.0)
	wall_material.roughness = 0.9

	# Village countryside grass
	grass_material = StandardMaterial3D.new()
	grass_material.albedo_color = Color(0.2, 0.42, 0.16, 1.0)
	grass_material.roughness = 1.0

	# Village house wall & roof materials
	house_wall_mat = StandardMaterial3D.new()
	house_wall_mat.albedo_color = Color(0.82, 0.76, 0.68, 1.0)
	house_wall_mat.roughness = 0.85

	house_roof_mat = StandardMaterial3D.new()
	house_roof_mat.albedo_color = Color(0.68, 0.22, 0.15, 1.0)
	house_roof_mat.roughness = 0.8

	# Village tree wood & foliage materials
	tree_wood_mat = StandardMaterial3D.new()
	tree_wood_mat.albedo_color = Color(0.32, 0.2, 0.12, 1.0)
	tree_wood_mat.roughness = 0.95

	tree_leaf_mat = StandardMaterial3D.new()
	tree_leaf_mat.albedo_color = Color(0.14, 0.48, 0.18, 1.0)
	tree_leaf_mat.roughness = 0.9

# --- Highscore Persistence ---
func _load_highscore() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			high_score = f.get_32()
			f.close()

func _save_highscore() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_32(high_score)
		f.close()

func _input(event: InputEvent) -> void:
	# Allow pressing R to retry when game over screen is visible
	if game_over_panel and game_over_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_R:
			_restart_game()

func _process(delta: float) -> void:
	if not game_active:
		return
	if not player or not is_instance_valid(player):
		return

	# Track distance score and update highscore live
	distance_traveled = -player.global_position.z
	score = int(distance_traveled * 2.0) + (coins_collected * 50)
	if score > high_score:
		high_score = score

	update_ui()

	# Check if new road segments need to be generated ahead
	if player.global_position.z - 120.0 < next_spawn_z:
		spawn_road_segment()
		recycle_old_segments()

	# Display proximity warning only when chaser is actively visible and close
	if chaser and chaser_warning_label:
		var chaser_phase = chaser.get("current_phase")
		var is_chasing: bool = (chaser_phase != null and chaser_phase == 1)  # Phase.CHASING == 1
		var dist: float = chaser.global_position.distance_to(player.global_position)
		if is_chasing and dist < 5.5 and not player.is_dashing:
			chaser_warning_label.visible = true
			chaser_warning_label.text = "⚠ CHASER! (%.1fm)" % dist
			chaser_warning_label.modulate = Color(1.0, 0.15, 0.15, 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.014))
		else:
			chaser_warning_label.visible = false

func spawn_road_segment() -> void:
	var segment := Node3D.new()
	segment.position = Vector3(0, 0, next_spawn_z)

	# 1. Main Village Road Surface (Width: 8m, Length: 40m)
	var road := CSGBox3D.new()
	road.size = Vector3(8.0, 0.1, SEGMENT_LENGTH)
	road.position = Vector3(0, -0.05, -SEGMENT_LENGTH / 2.0)
	road.material = road_material
	road.use_collision = true
	segment.add_child(road)

	# 2. Road Border Curbs / Wooden Railings
	var left_wall := CSGBox3D.new()
	left_wall.size = Vector3(0.5, 1.4, SEGMENT_LENGTH)
	left_wall.position = Vector3(-4.2, 0.7, -SEGMENT_LENGTH / 2.0)
	left_wall.material = wall_material
	left_wall.use_collision = true
	segment.add_child(left_wall)

	var right_wall := CSGBox3D.new()
	right_wall.size = Vector3(0.5, 1.4, SEGMENT_LENGTH)
	right_wall.position = Vector3(4.2, 0.7, -SEGMENT_LENGTH / 2.0)
	right_wall.material = wall_material
	right_wall.use_collision = true
	segment.add_child(right_wall)

	# 3. Outer Grass Landscape
	var grass_left := CSGBox3D.new()
	grass_left.size = Vector3(25.0, 0.1, SEGMENT_LENGTH)
	grass_left.position = Vector3(-16.7, -0.05, -SEGMENT_LENGTH / 2.0)
	grass_left.material = grass_material
	segment.add_child(grass_left)

	var grass_right := CSGBox3D.new()
	grass_right.size = Vector3(25.0, 0.1, SEGMENT_LENGTH)
	grass_right.position = Vector3(16.7, -0.05, -SEGMENT_LENGTH / 2.0)
	grass_right.material = grass_material
	segment.add_child(grass_right)

	# 4. Background Scenery: Village Houses and Trees (with surprise falling trees)
	var has_falling_tree: bool = spawn_scenery_props(segment)

	# 5. Populate Segment with Silver Coins, Booster Tokens, High Slide Arches, and Low Barriers
	if next_spawn_z < -30.0:
		populate_segment_items(segment, has_falling_tree)

	add_child(segment)
	active_segments.append(segment)
	next_spawn_z -= SEGMENT_LENGTH

func spawn_scenery_props(segment: Node3D) -> bool:
	segments_since_last_falling_tree += 1

	# Add houses on alternate sides along the segment
	var house_z := -SEGMENT_LENGTH * 0.35
	var house_side := -9.5 if randf() < 0.5 else 9.5
	create_village_house(segment, Vector3(house_side, 0, house_z))

	# Occasional surprise falling tree event:
	# Requires at least 3 clear segments (~120m) between falls, starts after 80m, and has a 25% chance
	var can_spawn_falling_tree: bool = segments_since_last_falling_tree >= 3 and next_spawn_z < -80.0
	var will_spawn_falling_tree: bool = can_spawn_falling_tree and (randf() < 0.25)
	var falling_tree_spawned: bool = false
	var chosen_falling_index: int = randi() % 3
	var falling_side_left: bool = randf() < 0.5

	if will_spawn_falling_tree:
		segments_since_last_falling_tree = 0

	# Add lush village trees on both sides along the segment
	var tree_z_offsets := [-8.0, -22.0, -34.0]
	for i in range(tree_z_offsets.size()):
		var tz = tree_z_offsets[i]
		var is_this_falling_left := false
		var is_this_falling_right := false

		if will_spawn_falling_tree and not falling_tree_spawned and i == chosen_falling_index:
			if falling_side_left:
				is_this_falling_left = true
			else:
				is_this_falling_right = true
			falling_tree_spawned = true

		create_village_tree(segment, Vector3(-4.5 if is_this_falling_left else (-7.5 - randf() * 3.0), 0, tz), is_this_falling_left)
		create_village_tree(segment, Vector3(4.5 if is_this_falling_right else (7.5 + randf() * 3.0), 0, tz + 4.0), is_this_falling_right)

	return falling_tree_spawned

func create_village_house(parent: Node3D, pos: Vector3) -> void:
	var house_node := Node3D.new()
	house_node.position = pos

	# House Body
	var body := CSGBox3D.new()
	body.size = Vector3(5.0, 3.2, 6.0)
	body.position = Vector3(0, 1.6, 0)
	body.material = house_wall_mat
	house_node.add_child(body)

	# House Roof
	var roof := CSGBox3D.new()
	roof.size = Vector3(5.6, 1.6, 6.6)
	roof.position = Vector3(0, 3.8, 0)
	roof.material = house_roof_mat
	roof.rotation_degrees = Vector3(0, 0, 15 if pos.x > 0 else -15)
	house_node.add_child(roof)

	parent.add_child(house_node)

func create_village_tree(parent: Node3D, pos: Vector3, is_falling: bool = false) -> void:
	var tree_node := Node3D.new()
	tree_node.position = pos
	tree_node.add_to_group("trees")

	# Tree Trunk (7.2m tall for falling tree so it visibly spans across all lanes of the running track)
	var trunk := CSGBox3D.new()
	trunk.name = "Trunk"
	trunk.size = Vector3(0.9, 7.2, 0.9) if is_falling else Vector3(0.7, 3.2, 0.7)
	trunk.position = Vector3(0, 3.6, 0) if is_falling else Vector3(0, 1.6, 0)
	trunk.material = tree_wood_mat
	tree_node.add_child(trunk)

	# Cross branch for fallen log hurdle aesthetic
	if is_falling:
		var branch := CSGBox3D.new()
		branch.name = "Branch"
		branch.size = Vector3(0.55, 2.8, 0.55)
		branch.position = Vector3(0.3, 4.2, 0.2)
		branch.rotation_degrees = Vector3(20, 0, 35)
		branch.material = tree_wood_mat
		tree_node.add_child(branch)

	# Tree Foliage (elevated to canopy so the trunk area across the track remains open for sliding)
	var foliage := CSGBox3D.new()
	foliage.name = "Foliage"
	foliage.size = Vector3(3.0, 2.6, 3.0) if is_falling else Vector3(3.2, 3.0, 3.2)
	foliage.position = Vector3(0, 7.2, 0) if is_falling else Vector3(0, 4.0, 0)
	foliage.material = tree_leaf_mat
	tree_node.add_child(foliage)

	var top_foliage := CSGBox3D.new()
	top_foliage.name = "TopFoliage"
	top_foliage.size = Vector3(2.0, 1.6, 2.0) if is_falling else Vector3(2.2, 1.8, 2.2)
	top_foliage.position = Vector3(0, 8.4, 0) if is_falling else Vector3(0, 5.4, 0)
	top_foliage.material = tree_leaf_mat
	tree_node.add_child(top_foliage)

	if is_falling:
		tree_node.set_script(falling_tree_script)

	parent.add_child(tree_node)

func populate_segment_items(segment: Node3D, has_falling_tree: bool = false) -> void:
	if not track_item_scene:
		return

	var lane_positions := [-2.6, 0.0, 2.6]

	# Spawn a row of circular silver coins along random lanes (early in segment)
	var coin_lane: float = lane_positions.pick_random()
	for i in range(3):
		var coin: Area3D = track_item_scene.instantiate()
		coin.set("item_type", 0) # ItemType.COIN
		coin.position = Vector3(coin_lane, 0.5, -(i * 5.0 + 6.0))
		segment.add_child(coin)

	# Booster Token placed at -18.0m only if no falling tree in that zone
	if randf() < 0.75 and not has_falling_tree:
		var token: Area3D = track_item_scene.instantiate()
		token.set("item_type", 1) # ItemType.TOKEN
		token.position = Vector3(lane_positions.pick_random(), 0.55, -18.0)
		segment.add_child(token)

	# STRICT ZERO-INTERFERENCE RULE:
	# If this segment has a Falling Tree, DO NOT spawn any High Arch or Low Barrier!
	# The falling tree is the sole obstacle for this segment.
	if has_falling_tree:
		return

	# Only in segments WITHOUT a falling tree, spawn at most ONE obstacle at -30.0m
	if randf() < 0.85:
		var obstacle: Area3D = track_item_scene.instantiate()
		# 50% chance of High Arch (requires Slide!), 50% chance of Low Barrier (requires Jump!)
		var chosen_type: int = 3 if randf() < 0.5 else 2
		obstacle.set("item_type", chosen_type)
		obstacle.position = Vector3(lane_positions.pick_random() if chosen_type == 2 else 0.0, 0.0, -30.0)
		segment.add_child(obstacle)

func recycle_old_segments() -> void:
	if active_segments.size() > 10:
		var oldest: Node3D = active_segments.pop_front()
		if oldest and is_instance_valid(oldest):
			oldest.queue_free()

func update_ui() -> void:
	if score_label:
		score_label.text = "SCORE: %d    BEST: %d" % [score, high_score]
	if coins_label:
		coins_label.text = "DIST: %dm  |  COINS: %d" % [int(distance_traveled), coins_collected]
	if speed_label and player:
		speed_label.text = "SPEED: %.1f m/s" % player.current_run_speed
	if player and token_progress_bar and token_status_label:
		var tokens: int = player.booster_tokens
		token_progress_bar.value = (float(tokens) / 3.0) * 100.0
		if player.is_dashing:
			token_status_label.text = "SUPER DASH ACTIVE!  (SMASH OBSTACLES)"
			token_status_label.modulate = Color(0.1, 0.9, 1.0)
		elif player.can_dash:
			token_status_label.text = "SUPER DASH READY!  [PRESS SPACEBAR]"
			token_status_label.modulate = Color(1.0, 0.85, 0.1)
		else:
			token_status_label.text = "BOOSTER TOKENS: %d / 3" % tokens
			token_status_label.modulate = Color(0.8, 0.9, 1.0)

	# Update Grappling Hook HUD
	if player and grapple_label and grapple_bar:
		if player.get("is_flying") == true or player.get("is_dive_kicking") == true:
			var remaining: float = maxf(0.0, player.get("flight_timer"))
			grapple_label.text = "🚀 GRAPPLE FLIGHT: %.1fs [METEOR KICK READY]" % remaining
			grapple_label.modulate = Color(0.2, 1.0, 0.85)
			grapple_bar.value = (remaining / 2.5) * 100.0
		elif player.get("can_grapple") == true:
			var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
			grapple_label.text = "⚡ [F / Y] GRAPPLE HOOK READY!"
			grapple_label.modulate = Color(1.0, 0.25, 0.65, pulse)
			grapple_bar.value = 100.0
		else:
			var cd: float = player.get("grapple_cooldown")
			var cd_pct: float = clampf((1.0 - (cd / 6.5)) * 100.0, 0.0, 100.0)
			grapple_label.text = "GRAPPLE COOLDOWN: %.1fs" % cd
			grapple_label.modulate = Color(0.65, 0.65, 0.75)
			grapple_bar.value = cd_pct

# --- Item Collection Callbacks ---
func collect_coin(world_pos: Vector3) -> void:
	coins_collected += 1
	spawn_text_popup(world_pos, "+50  SILVER COIN", Color(0.9, 0.98, 1.0))

func collect_token_ui(world_pos: Vector3) -> void:
	spawn_text_popup(world_pos, "+1  BOOSTER TOKEN", Color(0.2, 0.9, 1.0))
	if player and player.can_dash:
		spawn_text_popup(player.global_position + Vector3(0, 0.5, 0), "SUPER DASH READY!  [SPACEBAR]", Color(1.0, 0.9, 0.2))

func destroy_obstacle(world_pos: Vector3, msg: String = "SMASH! +250") -> void:
	score += 250
	spawn_text_popup(world_pos, msg, Color(1.0, 0.3, 0.3))
	shake_camera(0.25)

func smash_obstacles_in_radius(world_pos: Vector3, radius: float = 7.5) -> int:
	var count: int = 0
	var obstacles := get_tree().get_nodes_in_group("obstacles")
	for obs in obstacles:
		if not is_instance_valid(obs):
			continue
		var dist: float = world_pos.distance_to(obs.global_position)
		if dist <= radius:
			count += 1
			score += 500
			shake_camera(0.4)
			if obs.has_method("_break_tree_visuals"):
				obs._break_tree_visuals()
			elif obs.get_parent() and obs.get_parent().has_method("_break_tree_visuals"):
				obs.get_parent()._break_tree_visuals()
				obs.queue_free()
			else:
				spawn_text_popup(obs.global_position, "SMASH! +500", Color(1.0, 0.35, 0.1))
				obs.queue_free()

	# Also blast back chaser monster if caught in the shockwave!
	if chaser and is_instance_valid(chaser):
		var chaser_dist: float = world_pos.distance_to(chaser.global_position)
		if chaser_dist < radius + 4.0:
			chaser.global_position.z += 8.5
			spawn_text_popup(chaser.global_position, "CHASER BLASTED BACK! ⚡", Color(0.2, 0.9, 1.0))
			shake_camera(0.45)

	return count

func on_successful_slide(world_pos: Vector3) -> void:
	score += 150
	spawn_text_popup(world_pos, "NICE SLIDE!  +150", Color(0.2, 1.0, 0.6))

func on_super_dash_triggered() -> void:
	shake_camera(0.35)

# --- Menu Callbacks ---
func _on_play_pressed() -> void:
	# Immediately unfreeze and start the game, then fade out menu
	game_active = true
	game_started = true

	if player:
		player.set_physics_process(true)
		player.set_process(true)
	if chaser:
		chaser.set_physics_process(true)

	# Fade menu out and hide it (no await — game is already running)
	if main_menu_panel:
		var tween := create_tween()
		tween.tween_property(main_menu_panel, "modulate:a", 0.0, 0.25)
		tween.tween_callback(func(): main_menu_panel.visible = false)

func _on_main_menu_pressed() -> void:
	# Return to main menu — simply reload the scene (main menu shows on _ready)
	get_tree().reload_current_scene()

# --- Game Over ---
func trigger_game_over() -> void:
	if not game_active:
		return
	game_active = false

	# Freeze the player and chaser
	if player:
		player.set_physics_process(false)
		player.set_process(false)
	if chaser:
		chaser.set_physics_process(false)

	# Save highscore if beaten
	if score > high_score:
		high_score = score
	_save_highscore()

	shake_camera(0.55)

	# Show Game Over overlay after a brief dramatic pause
	await get_tree().create_timer(0.5).timeout
	if game_over_panel:
		game_over_panel.modulate.a = 0.0
		game_over_panel.visible = true
		if game_over_score_label:
			var is_new_best: bool = score >= high_score and score > 0
			game_over_score_label.text = "FINAL SCORE: %d%s" % [score, "   ★ NEW BEST!" if is_new_best else ""]
		if game_over_dist_label:
			game_over_dist_label.text = "DISTANCE: %d METERS    BEST: %d" % [int(distance_traveled), high_score]
		# Fade in
		var tween := create_tween()
		tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.35)

func _restart_game() -> void:
	get_tree().reload_current_scene()

# --- Visual FX ---
func spawn_text_popup(world_pos: Vector3, text_content: String, color: Color) -> void:
	if not popup_container:
		return
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var screen_pos := cam.unproject_position(world_pos + Vector3(0, 1.2, 0))
	var label := Label.new()
	label.text = text_content
	label.position = screen_pos
	label.add_theme_font_size_override("font_size", 22)
	label.modulate = color
	popup_container.add_child(label)

	var tween := create_tween()
	tween.parallel().tween_property(label, "position:y", screen_pos.y - 50.0, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)

func shake_camera(intensity: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var orig_pos: Vector3 = cam.position
	var tween := create_tween()
	for i in range(5):
		var offset := Vector3(randf_range(-intensity, intensity), randf_range(-intensity * 0.5, intensity * 0.5), 0.0)
		tween.tween_property(cam, "position", orig_pos + offset, 0.035)
	tween.tween_property(cam, "position", orig_pos, 0.04)
