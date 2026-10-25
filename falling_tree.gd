extends Node3D

var has_fallen: bool = false
var trigger_distance: float = 28.0  # Falls in clear view ahead of player

@onready var trunk: CSGBox3D = get_node_or_null("Trunk")
@onready var foliage: CSGBox3D = get_node_or_null("Foliage")
@onready var top_foliage: CSGBox3D = get_node_or_null("TopFoliage")

var obstacle_area: Area3D
var has_hit_player: bool = false

func _process(_delta: float) -> void:
	if has_fallen:
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return

	# Trigger when player approaches — tree is ahead along -Z
	var dist_z: float = global_position.z - player.global_position.z
	if dist_z < 0 and absf(dist_z) < trigger_distance:
		trigger_surprise_fall()

func trigger_surprise_fall() -> void:
	has_fallen = true

	# Screen shake for dramatic creak effect
	var main = get_tree().current_scene
	if main and main.has_method("shake_camera"):
		main.shake_camera(0.22)

	# Inward fall direction ONTO the track:
	# Left tree (x < 0) rotates clockwise towards +X (negative Z rotation)
	# Right tree (x > 0) rotates counter-clockwise towards -X (positive Z rotation)
	var target_z_rot: float = 78.0 if global_position.x > 0.0 else -78.0
	# Tilt forward towards the oncoming player (+Z direction)
	var target_x_rot: float = 18.0

	var tween := create_tween()

	# Phase 1: Realistic wood-stress creak & splintering tremors
	tween.tween_property(self, "rotation_degrees:z", -target_z_rot * 0.05, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees:z", target_z_rot * 0.04, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation_degrees:z", -target_z_rot * 0.08, 0.1) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Phase 2: Massive physics crash down — starts slow with heavy rotational inertia, accelerates exponentially
	tween.parallel().tween_property(self, "rotation_degrees:z", target_z_rot, 0.58) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "rotation_degrees:x", target_x_rot, 0.58) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "position:y", 0.45, 0.58) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# Phase 3: Realistic damped ground impact rebound & settle
	tween.tween_property(self, "rotation_degrees:z", target_z_rot * 0.92, 0.09) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation_degrees:z", target_z_rot * 1.02, 0.07) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation_degrees:z", target_z_rot, 0.06) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Impact camera shake, dust burst across the road, and activate slide trigger
	tween.tween_callback(func():
		if main and main.has_method("shake_camera"):
			main.shake_camera(0.45)
		_spawn_impact_dust()
		_activate_slide_obstacle()
	)

func _ready() -> void:
	add_to_group("trees")

func _activate_slide_obstacle() -> void:
	if obstacle_area:
		return

	var parent_node = get_parent()
	if not parent_node:
		return

	obstacle_area = Area3D.new()
	obstacle_area.name = "FallenTreeSlideObstacle"
	obstacle_area.add_to_group("obstacles")

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Spans across all 3 road lanes (width 8.0m), height 1.1m, depth 1.4m
	box.size = Vector3(8.0, 1.1, 1.4)
	col_shape.shape = box
	# Elevated at y = 1.35m:
	# Standing player (height 1.8m) enters box -> CRASH
	# Sliding player (height 0.75m) ducks cleanly underneath!
	col_shape.position = Vector3(0.0, 1.35, 0.0)
	obstacle_area.add_child(col_shape)

	# Centered on the road (x = 0) at the tree's Z location (offset slightly +Z for the forward tilt)
	obstacle_area.position = Vector3(0.0, 0.0, position.z + 1.2)
	obstacle_area.body_entered.connect(_on_obstacle_body_entered)
	parent_node.add_child(obstacle_area)

func _on_obstacle_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or has_hit_player:
		return

	var main = get_tree().current_scene
	if body.get("is_dashing") == true:
		has_hit_player = true
		if main and main.has_method("destroy_obstacle"):
			main.destroy_obstacle(obstacle_area.global_position, "TREE SMASH! +300")
		_break_tree_visuals()
		if obstacle_area and is_instance_valid(obstacle_area):
			obstacle_area.queue_free()
	elif body.get("is_sliding") == true:
		has_hit_player = true
		if main and main.has_method("on_successful_slide"):
			main.on_successful_slide(obstacle_area.global_position)
	else:
		has_hit_player = true
		get_tree().call_deferred("reload_current_scene")

func _break_tree_visuals() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _spawn_impact_dust() -> void:
	var parent_node = get_parent()
	if not parent_node:
		return

	var dust := CPUParticles3D.new()
	# Burst on the road surface where the tree trunk crashes down
	dust.position = Vector3(0.0, 0.15, position.z + 1.0)
	dust.emitting = true
	dust.one_shot = true
	dust.amount = 35
	dust.lifetime = 0.85
	dust.explosiveness = 0.95
	dust.gravity = Vector3(0.0, 1.8, 0.0)
	dust.initial_velocity_min = 3.0
	dust.initial_velocity_max = 7.0
	dust.spread = 90.0
	dust.scale_amount_min = 0.35
	dust.scale_amount_max = 0.85
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.albedo_color = Color(0.85, 0.75, 0.58, 0.75)
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.55)
	quad.material = dust_mat
	dust.mesh = quad
	parent_node.add_child(dust)

func _exit_tree() -> void:
	if obstacle_area and is_instance_valid(obstacle_area):
		obstacle_area.queue_free()
