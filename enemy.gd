extends Area3D

# --- Chase Parameters ---
@export var catch_up_bonus: float = 0.6   # How much faster than the player when chasing
@export var kill_distance: float = 1.2

var player: CharacterBody3D = null

# ─────────────────────────────────────────────────────────────────────────────
# Disappear / Reappear Phase System
# ─────────────────────────────────────────────────────────────────────────────
enum Phase { WAITING, CHASING, FADING_OUT, HIDDEN, FADING_IN }
var current_phase: Phase = Phase.WAITING

const FIRST_APPEAR_DISTANCE: float = 200.0  # Only appears after 200m
const CHASE_DURATION_MIN: float = 3.5   # Visible and chasing for 3.5–6 seconds
const CHASE_DURATION_MAX: float = 6.0
const HIDDEN_DURATION_MIN: float = 10.0  # Hidden for 10–22 seconds — appears RARELY
const HIDDEN_DURATION_MAX: float = 22.0
const FADE_TIME: float = 0.5            # Fade in / out transition time

var phase_timer: float = 0.0
var fade_tween: Tween = null

# ─────────────────────────────────────────────────────────────────────────────
# 3D Rig References
# ─────────────────────────────────────────────────────────────────────────────
@onready var visual_root: Node3D = $VisualRoot
@onready var hips: Node3D = $VisualRoot/Hips
@onready var head: MeshInstance3D = $VisualRoot/Hips/Head
@onready var left_arm: Node3D = $VisualRoot/Hips/LeftShoulder
@onready var right_arm: Node3D = $VisualRoot/Hips/RightShoulder
@onready var left_leg: Node3D = $VisualRoot/Hips/LeftHipJoint
@onready var right_leg: Node3D = $VisualRoot/Hips/RightHipJoint

const HIPS_BASE_Y: float = 0.95
var run_cycle: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	body_entered.connect(_on_body_entered)

	# Make all mesh materials support alpha transparency for the fade effect
	_init_transparent_materials()

	# Start hidden — enemy only appears after FIRST_APPEAR_DISTANCE
	visual_root.visible = false
	$CollisionShape3D.disabled = true
	current_phase = Phase.WAITING

func _init_transparent_materials() -> void:
	if not visual_root:
		return
	for child in _get_all_meshes(visual_root):
		var mat: StandardMaterial3D = child.get_active_material(0)
		if mat:
			# Duplicate so we don't mutate the shared sub_resource
			var m: StandardMaterial3D = mat.duplicate()
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.set_surface_override_material(0, m)

func _get_all_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		result.append_array(_get_all_meshes(child))
	return result

# ─────────────────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not player or not is_instance_valid(player):
		return

	# Keep enemy frozen and invisible until the player has run far enough
	if current_phase == Phase.WAITING:
		var dist_run: float = -player.global_position.z
		if dist_run >= FIRST_APPEAR_DISTANCE:
			_begin_fade_in()
		else:
			# Stay parked far behind while waiting
			global_position = player.global_position + Vector3(0, 0, 60.0)
		return

	phase_timer -= delta

	match current_phase:
		Phase.CHASING:
			_do_chase(delta)
			if phase_timer <= 0.0:
				_begin_fade_out()

		Phase.FADING_OUT, Phase.FADING_IN:
			pass  # Tween handles the visual; skip chase movement

		Phase.HIDDEN:
			if phase_timer <= 0.0:
				_begin_fade_in()

	# Always animate the rig (even fading — looks cool)
	_animate_rig(delta)

# ─────────────────────────────────────────────────────────────────────────────
# Chase Movement
# ─────────────────────────────────────────────────────────────────────────────
func _do_chase(delta: float) -> void:
	# Mirror player's X lane position with a slight lag
	global_position.x = lerpf(global_position.x, player.global_position.x, 3.5 * delta)

	# Speed: slightly faster than the player so the gap closes over time.
	# During Super Dash the chaser is outrun temporarily.
	var chase_speed: float
	if player.is_dashing:
		chase_speed = player.current_run_speed * 0.52  # Dash leaves chaser far behind
	else:
		chase_speed = player.current_run_speed + catch_up_bonus

	global_position.z -= chase_speed * delta

# ─────────────────────────────────────────────────────────────────────────────
# Phase Transitions
# ─────────────────────────────────────────────────────────────────────────────
func _begin_chase_phase() -> void:
	current_phase = Phase.CHASING
	phase_timer = randf_range(CHASE_DURATION_MIN, CHASE_DURATION_MAX)
	$CollisionShape3D.disabled = false

func _begin_fade_out() -> void:
	current_phase = Phase.FADING_OUT
	$CollisionShape3D.disabled = true  # Can't be caught while fading

	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_method(_set_all_alpha, 1.0, 0.0, FADE_TIME)
	fade_tween.tween_callback(func():
		visual_root.visible = false
		current_phase = Phase.HIDDEN
		phase_timer = randf_range(HIDDEN_DURATION_MIN, HIDDEN_DURATION_MAX)
	)

func _begin_fade_in() -> void:
	current_phase = Phase.FADING_IN

	# Teleport to a position just behind the player before reappearing
	var spawn_offset: float = randf_range(7.0, 12.0)
	var lane_x: float = randf_range(-2.5, 2.5)
	global_position = player.global_position + Vector3(lane_x, 0, spawn_offset)

	visual_root.visible = true
	_set_all_alpha(0.0)

	if fade_tween:
		fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_method(_set_all_alpha, 0.0, 1.0, FADE_TIME)
	fade_tween.tween_callback(func():
		_begin_chase_phase()
	)

# ─────────────────────────────────────────────────────────────────────────────
# Fade Helper — sets alpha on every mesh material in the rig
# ─────────────────────────────────────────────────────────────────────────────
func _set_all_alpha(alpha: float) -> void:
	if not visual_root:
		return
	for mesh in _get_all_meshes(visual_root):
		var mat: StandardMaterial3D = mesh.get_surface_override_material(0)
		if mat:
			var c: Color = mat.albedo_color
			c.a = alpha
			mat.albedo_color = c

# ─────────────────────────────────────────────────────────────────────────────
# Procedural 3D Humanoid Running Animation
# Mirrors the player's style — arms & legs swing in anti-phase
# ─────────────────────────────────────────────────────────────────────────────
func _animate_rig(delta: float) -> void:
	if not hips or not left_arm or not right_arm or not left_leg or not right_leg:
		return

	var speed_ratio: float = 1.0
	if player:
		speed_ratio = player.current_run_speed / 11.0

	# Cadence scales with player speed (chaser is always running hard)
	var cadence: float = 16.0 * (0.8 + 0.2 * speed_ratio)
	if player and player.is_dashing:
		cadence = 26.0  # Frantically trying to keep up during dash!
	run_cycle += delta * cadence

	# 1. Hip bounce and pelvic twist
	var bounce: float = absf(sin(run_cycle)) * 0.13
	hips.position.y = HIPS_BASE_Y + bounce
	hips.rotation.y = sin(run_cycle) * 0.15
	hips.rotation.z = 0.0

	# 2. Aggressive forward sprint lean (enemy leans harder than player — menacing)
	var lean: float = deg_to_rad(20.0)
	if player and player.is_dashing:
		lean = deg_to_rad(32.0)
	hips.rotation.x = lean

	# 3. Arm swing (anti-phase with legs)
	var arm_swing: float = sin(run_cycle) * 1.0
	left_arm.rotation.x = -arm_swing
	right_arm.rotation.x = arm_swing
	left_arm.rotation.z = deg_to_rad(9.0) + cos(run_cycle) * 0.09
	right_arm.rotation.z = -deg_to_rad(9.0) - cos(run_cycle) * 0.09

	# 4. Leg stride
	var leg_stride: float = sin(run_cycle) * 1.08
	left_leg.rotation.x = leg_stride
	right_leg.rotation.x = -leg_stride

	# 5. Head compensation
	if head:
		head.rotation.x = -lean * 0.5
		head.rotation.y = -hips.rotation.y * 0.45

# ─────────────────────────────────────────────────────────────────────────────
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and current_phase == Phase.CHASING:
		if not body.is_dashing:
			var main = get_tree().current_scene
			if main and main.has_method("trigger_game_over"):
				main.trigger_game_over()
			else:
				get_tree().call_deferred("reload_current_scene")
