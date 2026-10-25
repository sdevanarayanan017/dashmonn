extends CharacterBody3D

# --- Dynamic Progressive Velocity ---
@export var base_forward_speed: float = 11.0
@export var max_forward_speed: float = 24.0
@export var speed_increase_per_100m: float = 1.0 # Increases as distance increases
var current_run_speed: float = 11.0

@export var steer_speed: float = 9.5
@export var jump_velocity: float = 9.5
@export var gravity: float = 24.0
@export var dash_speed_multiplier: float = 2.2
@export var dash_duration: float = 1.4

# --- INPUT SETUP (Keyboard + Gamepad) ---
func _setup_input_actions() -> void:
	# Move Left (A / Left stick left / Left Arrow)
	if not InputMap.has_action("move_left"):
		InputMap.add_action("move_left")
		var ev = InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_X
		ev.axis_value = -0.5
		InputMap.action_add_event("move_left", ev)
	# Move Right (D / Left stick right / Right Arrow)
	if not InputMap.has_action("move_right"):
		InputMap.add_action("move_right")
		var ev = InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_X
		ev.axis_value = 0.5
		InputMap.action_add_event("move_right", ev)
	# Jump / Double‑Jump (Space / A button)
	if not InputMap.has_action("jump"):
		InputMap.add_action("jump")
		var btn = InputEventJoypadButton.new()
		btn.button_index = JOY_BUTTON_A
		InputMap.action_add_event("jump", btn)
	# Slide (S / Down Arrow / B button)
	if not InputMap.has_action("slide"):
		InputMap.add_action("slide")
		var btn = InputEventJoypadButton.new()
		btn.button_index = JOY_BUTTON_B
		InputMap.action_add_event("slide", btn)
	# Dash (Space / X button)
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var btn = InputEventJoypadButton.new()
		btn.button_index = JOY_BUTTON_X
		InputMap.action_add_event("dash", btn)
	# Grappling Hook (F / Q / Y button / Right Shoulder RB)
	if not InputMap.has_action("grapple"):
		InputMap.add_action("grapple")
		var k_f = InputEventKey.new()
		k_f.physical_keycode = KEY_F
		InputMap.action_add_event("grapple", k_f)
		var k_q = InputEventKey.new()
		k_q.physical_keycode = KEY_Q
		InputMap.action_add_event("grapple", k_q)
		var btn_y = InputEventJoypadButton.new()
		btn_y.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("grapple", btn_y)
		var btn_rb = InputEventJoypadButton.new()
		btn_rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
		InputMap.action_add_event("grapple", btn_rb)

func _get_steer_input() -> float:
	var raw = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var deadzone = 0.2
	if abs(raw) < deadzone:
		return 0.0
	var s = (1 if raw > 0 else -1)
	var normalized = (abs(raw) - deadzone) / (1.0 - deadzone)
	return s * pow(normalized, 1.2)

# --- Booster Tokens (3 Needed for Dash Super Power) ---
var booster_tokens: int = 0
const TOKENS_NEEDED_FOR_DASH: int = 3
var can_dash: bool = false
var is_dashing: bool = false
var dash_timer: float = 0.0

# --- Sliding Ability ---
var is_sliding: bool = false
var slide_timer: float = 0.0
const SLIDE_DURATION: float = 0.85

# --- Grappling Hook & Meteor Flight Ability (Card 3 & Card 7) ---
var can_grapple: bool = true
var is_grappling: bool = false        # Initial tether pull
var is_flying: bool = false           # Soaring high above all obstacles (2.5s)
var is_dive_kicking: bool = false     # Descending dropkick plunging into ground
var is_kick_recovering: bool = false  # Brief superhero three-point ground slam impact
var flight_timer: float = 0.0
const FLIGHT_DURATION: float = 2.5
var grapple_cooldown: float = 0.0
const GRAPPLE_COOLDOWN_TIME: float = 6.5

var grapple_target_pos: Vector3 = Vector3.ZERO
var grapple_cable: MeshInstance3D
var reticle_marker: MeshInstance3D
var kick_trail: CPUParticles3D

# --- Track Boundaries ---
const TRACK_MIN_X: float = -3.8
const TRACK_MAX_X: float = 3.8

# --- 3D Humanoid Joint References ---
@onready var trail_particles: CPUParticles3D = $CPUParticles3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var hips: Node3D = $VisualRoot/Hips
@onready var torso: MeshInstance3D = $VisualRoot/Hips/Torso
@onready var head: MeshInstance3D = $VisualRoot/Hips/Head
@onready var left_arm: Node3D = $VisualRoot/Hips/LeftShoulder
@onready var right_arm: Node3D = $VisualRoot/Hips/RightShoulder
@onready var left_leg: Node3D = $VisualRoot/Hips/LeftHipJoint
@onready var right_leg: Node3D = $VisualRoot/Hips/RightHipJoint

# --- Procedural Animation Cycle & Parameters ---
var run_cycle: float = 0.0
const HIPS_BASE_Y: float = 0.95

func _ready() -> void:
	add_to_group("player")
	if trail_particles:
		trail_particles.emitting = false
	_setup_input_actions()
	_setup_grapple_visuals()

func _setup_grapple_visuals() -> void:
	# 1. 3D Glowing Grapple Cable
	grapple_cable = MeshInstance3D.new()
	grapple_cable.top_level = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.045
	cyl.height = 1.0
	grapple_cable.mesh = cyl
	var cable_mat := StandardMaterial3D.new()
	cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cable_mat.albedo_color = Color(1.0, 0.18, 0.6, 1.0) # Vivid neon pink / magenta
	grapple_cable.material_override = cable_mat
	grapple_cable.visible = false
	add_child(grapple_cable)

	# 2. Holographic Target Bullseye Reticle at anchor tree
	reticle_marker = MeshInstance3D.new()
	reticle_marker.top_level = true
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.95
	reticle_marker.mesh = torus
	var reticle_mat := StandardMaterial3D.new()
	reticle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	reticle_mat.albedo_color = Color(1.0, 0.22, 0.65, 0.95)
	reticle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	reticle_marker.material_override = reticle_mat
	reticle_marker.visible = false
	add_child(reticle_marker)

	# 3. Kicking Foot Energy Blast Trail
	kick_trail = CPUParticles3D.new()
	kick_trail.emitting = false
	kick_trail.amount = 36
	kick_trail.lifetime = 0.35
	kick_trail.gravity = Vector3(0.0, 3.0, 0.0)
	kick_trail.spread = 50.0
	kick_trail.initial_velocity_min = 2.0
	kick_trail.initial_velocity_max = 6.5
	kick_trail.scale_amount_min = 0.25
	kick_trail.scale_amount_max = 0.6
	var kick_mat := StandardMaterial3D.new()
	kick_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kick_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.85)
	kick_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(0.35, 0.35)
	qmesh.material = kick_mat
	kick_trail.mesh = qmesh
	if right_leg:
		right_leg.add_child(kick_trail)

func _physics_process(delta: float) -> void:
	# 1. Progressive Velocity Scaling with Distance
	var distance_meters: float = -global_position.z
	current_run_speed = minf(base_forward_speed + (distance_meters / 100.0) * speed_increase_per_100m, max_forward_speed)

	# 2. Update Grapple Cooldown
	if not can_grapple and not is_flying and not is_dive_kicking:
		grapple_cooldown -= delta
		if grapple_cooldown <= 0.0:
			can_grapple = true
			grapple_cooldown = 0.0

	# 3. Steer Input (A/D or Left/Right Arrow or Left Stick)
	var steer_input := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A) or Input.is_action_pressed("move_left"):
		steer_input -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D) or Input.is_action_pressed("move_right"):
		steer_input += 1.0
	if absf(_get_steer_input()) > 0.01:
		steer_input = _get_steer_input()

	# 4. Grappling Hook Activation (F / Q / Y button / RB)
	var wants_grapple = Input.is_action_just_pressed("grapple") or Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_Q)
	if wants_grapple and can_grapple and not is_flying and not is_dive_kicking and not is_kick_recovering:
		activate_grappling_hook()

	# 5. Handle Movement State Machine: Flying vs Divekick vs Kick Recovery vs Slide/Dash/Run
	var active_forward_speed: float

	if is_flying:
		# --- High Aerial Flight (Soaring above all obstacles for 5 seconds) ---
		flight_timer -= delta
		# Maintain flight altitude safely above all hurdles (y = 5.0m)
		global_position.y = lerpf(global_position.y, 5.0, 7.5 * delta)
		velocity.y = 0.0
		active_forward_speed = current_run_speed * 1.35
		velocity.x = steer_input * steer_speed * 1.15
		_update_grapple_cable()

		# When 0.45s remain, transition into the devastating Meteor Divekick!
		if flight_timer <= 0.45:
			start_meteor_divekick()

	elif is_dive_kicking:
		# --- Meteor Divekick (Descending Dropkick into the asphalt) ---
		velocity.y = -32.0 # Fierce downward plunge
		active_forward_speed = current_run_speed * 1.45
		velocity.x = steer_input * steer_speed * 0.75

		# Touchdown detection on the road
		if is_on_floor() or global_position.y <= 0.15:
			execute_meteor_kick_impact()

	elif is_kick_recovering:
		# --- Impact Touchdown Recovery ---
		velocity.y = 0.0
		active_forward_speed = current_run_speed * 0.75
		velocity.x = 0.0

	else:
		# --- Standard Runner Movement ---
		# Gravity
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			if velocity.y < 0:
				velocity.y = 0.0

		# Jump Input (W / Up Arrow / A button)
		if (Input.is_action_just_pressed("ui_up") or Input.is_key_pressed(KEY_W) or Input.is_action_just_pressed("jump")) and is_on_floor() and not is_sliding:
			velocity.y = jump_velocity

		# Slide Input (S / Down Arrow / B button)
		if (Input.is_action_just_pressed("ui_down") or Input.is_key_pressed(KEY_S) or Input.is_action_just_pressed("slide")) and is_on_floor() and not is_sliding:
			start_slide()

		# Update Slide Timer
		if is_sliding:
			slide_timer -= delta
			if slide_timer <= 0.0:
				end_slide()

		# Super Dash Activation (Spacebar / ui_accept / X button)
		if (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("dash")) and can_dash and not is_dashing:
			activate_super_dash()

		if is_dashing:
			dash_timer -= delta
			active_forward_speed = current_run_speed * dash_speed_multiplier
			if dash_timer <= 0.0:
				end_super_dash()
		elif is_sliding:
			active_forward_speed = current_run_speed * 1.15
		else:
			active_forward_speed = current_run_speed

		velocity.x = steer_input * steer_speed

	# Forward velocity runs along -Z axis
	velocity.z = -active_forward_speed
	move_and_slide()

	# Enforce Track Wall Boundary
	global_position.x = clampf(global_position.x, TRACK_MIN_X, TRACK_MAX_X)

	# 6. Procedural 3D Humanoid Animation Rig
	animate_humanoid_rig(delta, steer_input)

# --- Grappling Hook & Meteor Kick Methods ---
func activate_grappling_hook() -> void:
	grapple_target_pos = find_best_grapple_tree()
	is_grappling = true
	is_flying = true
	is_sliding = false
	if is_dashing:
		end_super_dash()
	flight_timer = FLIGHT_DURATION

	# Launch upward towards flight altitude
	velocity.y = 18.0

	# Show energy cable and bullseye reticle
	if grapple_cable:
		grapple_cable.visible = true
	if reticle_marker:
		reticle_marker.global_position = grapple_target_pos
		reticle_marker.visible = true

	var main = get_tree().current_scene
	if main:
		if main.has_method("shake_camera"):
			main.shake_camera(0.25)
		if main.has_method("spawn_text_popup"):
			main.spawn_text_popup(global_position + Vector3(0, 1.2, 0), "⚡ GRAPPLING HOOK! [FLYING]", Color(1.0, 0.22, 0.65))

	# Retract cable after initial upward pull (0.5s) leaving the player soaring
	get_tree().create_timer(0.5).timeout.connect(func():
		is_grappling = false
		if grapple_cable:
			grapple_cable.visible = false
		if reticle_marker:
			reticle_marker.visible = false
	)

func find_best_grapple_tree() -> Vector3:
	var best_pos := Vector3.ZERO
	var best_dist := 9999.0
	var player_pos: Vector3 = global_position

	# Search all trees ahead along the track
	var trees := get_tree().get_nodes_in_group("trees")
	for tree in trees:
		if not is_instance_valid(tree):
			continue
		var t_pos: Vector3 = tree.global_position
		# Target tree must be ahead along -Z (t_pos.z < player_pos.z)
		var dz: float = player_pos.z - t_pos.z
		if dz > 8.0 and dz < 55.0:
			var d: float = player_pos.distance_to(t_pos)
			if d < best_dist:
				best_dist = d
				best_pos = t_pos + Vector3(0.0, 5.2, 0.0) # Canopy anchor height

	if best_pos != Vector3.ZERO:
		return best_pos

	# Guaranteed roadside anchor ahead if no tree was matched
	var side_x := -4.6 if randf() < 0.5 else 4.6
	return Vector3(side_x, 5.5, player_pos.z - 28.0)

func _update_grapple_cable() -> void:
	if not grapple_cable:
		return
	if not is_grappling:
		grapple_cable.visible = false
		if reticle_marker:
			reticle_marker.visible = false
		return

	grapple_cable.visible = true
	var start_p: Vector3 = right_arm.global_position if right_arm else global_position + Vector3(0.3, 1.2, 0.0)
	var end_p: Vector3 = grapple_target_pos
	var diff: Vector3 = end_p - start_p
	var dist: float = diff.length()
	if dist < 0.1:
		grapple_cable.visible = false
		return

	grapple_cable.global_position = (start_p + end_p) * 0.5
	if diff.normalized().cross(Vector3.UP).length() > 0.001:
		grapple_cable.look_at(end_p, Vector3.UP)
		grapple_cable.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

	var cyl: CylinderMesh = grapple_cable.mesh as CylinderMesh
	if cyl:
		cyl.height = dist

	if reticle_marker:
		reticle_marker.global_position = end_p
		reticle_marker.rotate_z(8.0 * get_process_delta_time())

func start_meteor_divekick() -> void:
	is_flying = false
	is_dive_kicking = true
	if kick_trail:
		kick_trail.emitting = true
	if grapple_cable:
		grapple_cable.visible = false
	if reticle_marker:
		reticle_marker.visible = false

	var main = get_tree().current_scene
	if main and main.has_method("spawn_text_popup"):
		main.spawn_text_popup(global_position + Vector3(0, 1.0, 0), "🔥 METEOR DIVEKICK!", Color(1.0, 0.45, 0.1))

func execute_meteor_kick_impact() -> void:
	is_dive_kicking = false
	is_kick_recovering = true
	velocity.y = 0.0
	global_position.y = 0.0

	if kick_trail:
		kick_trail.emitting = false

	# Start grapple cooldown (8s)
	can_grapple = false
	grapple_cooldown = GRAPPLE_COOLDOWN_TIME

	var main = get_tree().current_scene

	# 1. Kinetic Hit-Stop (Micro-Freeze 0.065s) for massive action-game weight
	_trigger_hit_stop(0.065)

	# 2. Violent Camera Shake
	if main and main.has_method("shake_camera"):
		main.shake_camera(0.72)

	# 3. Expanding Fiery Ground Shockwave Ring
	_spawn_ground_shockwave(global_position)

	# 4. Shattered Crater Debris & Spark Particles
	_spawn_crater_debris(global_position)

	# 5. Annihilate ALL obstacles within 7.5m radius!
	var smashed_count: int = 0
	if main and main.has_method("smash_obstacles_in_radius"):
		smashed_count = main.smash_obstacles_in_radius(global_position, 7.5)

	# 6. Floating Score Banner
	if main and main.has_method("spawn_text_popup"):
		if smashed_count > 0:
			main.spawn_text_popup(global_position + Vector3(0, 1.2, -1.0), "💥 METEOR KICK! SMASH x%d  +%d" % [smashed_count, 500 * smashed_count], Color(1.0, 0.3, 0.1))
		else:
			main.spawn_text_popup(global_position + Vector3(0, 1.2, -1.0), "💥 THUNDER METEOR SLAM!", Color(1.0, 0.45, 0.15))

	# Hold impact landing pose for 0.24s before sprint resumes
	get_tree().create_timer(0.24).timeout.connect(func():
		is_kick_recovering = false
	)

func _trigger_hit_stop(duration: float = 0.065) -> void:
	Engine.time_scale = 0.05
	# ignore_time_scale = true ensures real-time resumption
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func _spawn_ground_shockwave(world_pos: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.top_level = true
	var torus := TorusMesh.new()
	torus.inner_radius = 0.75
	torus.outer_radius = 1.05
	ring.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.1, 0.95) # Radiant magma orange
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat

	ring.global_position = Vector3(world_pos.x, 0.06, world_pos.z)
	get_parent().add_child(ring)

	var tween := create_tween()
	tween.parallel().tween_property(ring, "scale", Vector3(8.5, 1.0, 8.5), 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.42)
	tween.tween_callback(ring.queue_free)

func _spawn_crater_debris(world_pos: Vector3) -> void:
	var debris := CPUParticles3D.new()
	debris.top_level = true
	debris.global_position = Vector3(world_pos.x, 0.1, world_pos.z)
	debris.emitting = true
	debris.one_shot = true
	debris.amount = 45
	debris.lifetime = 0.75
	debris.explosiveness = 1.0
	debris.gravity = Vector3(0.0, -22.0, 0.0)
	debris.initial_velocity_min = 6.0
	debris.initial_velocity_max = 14.0
	debris.spread = 180.0
	debris.scale_amount_min = 0.25
	debris.scale_amount_max = 0.65

	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chunk_mat.albedo_color = Color(1.0, 0.4, 0.15, 1.0)
	var box := BoxMesh.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	box.material = chunk_mat
	debris.mesh = box
	get_parent().add_child(debris)

# --- Sliding & Dash Methods ---
func start_slide() -> void:
	is_sliding = true
	slide_timer = SLIDE_DURATION
	if collision_shape:
		collision_shape.shape.height = 0.75
		collision_shape.position.y = 0.4

func end_slide() -> void:
	is_sliding = false
	if collision_shape:
		collision_shape.shape.height = 1.8
		collision_shape.position.y = 0.9

func collect_token() -> void:
	booster_tokens += 1
	if booster_tokens >= TOKENS_NEEDED_FOR_DASH:
		can_dash = true

func activate_super_dash() -> void:
	is_dashing = true
	dash_timer = dash_duration
	booster_tokens = 0
	can_dash = false
	if trail_particles:
		trail_particles.emitting = true
	var main = get_tree().current_scene
	if main and main.has_method("on_super_dash_triggered"):
		main.on_super_dash_triggered()

func end_super_dash() -> void:
	is_dashing = false
	if trail_particles:
		trail_particles.emitting = false

# --- Procedural 3D Humanoid Animation Rig ---
func animate_humanoid_rig(delta: float, steer_input: float) -> void:
	if not hips or not left_arm or not right_arm or not left_leg or not right_leg:
		return

	if is_kick_recovering:
		# --- Powerful Three-Point Superhero Landing / Kick Recovery Pose ---
		hips.position.x = lerpf(hips.position.x, 0.0, 18.0 * delta)
		hips.position.y = lerpf(hips.position.y, 0.30, 22.0 * delta)
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(32.0), 22.0 * delta)
		hips.rotation.y = lerpf(hips.rotation.y, 0.0, 20.0 * delta)
		hips.rotation.z = 0.0

		if torso:
			torso.rotation.y = lerpf(torso.rotation.y, 0.0, 20.0 * delta)
			torso.rotation.z = 0.0

		right_leg.rotation.x = lerpf(right_leg.rotation.x, deg_to_rad(-70.0), 22.0 * delta)
		right_leg.rotation.z = deg_to_rad(15.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, deg_to_rad(65.0), 22.0 * delta)
		left_leg.rotation.z = deg_to_rad(-15.0)

		right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-75.0), 22.0 * delta)
		left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(45.0), 22.0 * delta)

		if head:
			head.rotation.x = deg_to_rad(20.0)
			head.rotation.y = 0.0

	elif is_dive_kicking:
		# --- Ferocious Rider Divekick / Dropkick Pose ---
		hips.position.x = lerpf(hips.position.x, 0.0, 18.0 * delta)
		hips.position.y = lerpf(hips.position.y, 0.7, 18.0 * delta)
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(-35.0), 18.0 * delta)
		hips.rotation.y = 0.0
		hips.rotation.z = deg_to_rad(12.0)

		if torso:
			torso.rotation.y = deg_to_rad(-8.0)

		# Right leg thrust straight forward like a piercing spear!
		right_leg.rotation.x = deg_to_rad(-85.0)
		right_leg.rotation.z = deg_to_rad(-8.0)
		left_leg.rotation.x = deg_to_rad(55.0)
		left_leg.rotation.z = deg_to_rad(15.0)

		right_arm.rotation.x = deg_to_rad(65.0)
		left_arm.rotation.x = deg_to_rad(60.0)

		if head:
			head.rotation.x = deg_to_rad(40.0)
			head.rotation.y = 0.0

	elif is_flying:
		# --- High-Altitude Superhero Flight Pose ---
		hips.position.x = lerpf(hips.position.x, 0.0, 10.0 * delta)
		hips.position.y = lerpf(hips.position.y, 0.95, 12.0 * delta)
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(65.0), 12.0 * delta)
		hips.rotation.y = 0.0
		hips.rotation.z = lerpf(hips.rotation.z, -steer_input * 0.35, 12.0 * delta)

		if torso:
			torso.rotation.y = lerpf(torso.rotation.y, 0.0, 12.0 * delta)
			torso.rotation.z = -steer_input * 0.1

		right_arm.rotation.x = deg_to_rad(-85.0)
		right_arm.rotation.z = deg_to_rad(12.0)
		left_arm.rotation.x = deg_to_rad(40.0)
		left_arm.rotation.z = deg_to_rad(10.0)

		left_leg.rotation.x = deg_to_rad(35.0)
		right_leg.rotation.x = deg_to_rad(25.0)

		if head:
			head.rotation.x = deg_to_rad(-45.0)
			head.rotation.y = 0.0

	elif is_sliding:
		# --- Realistic Low Ground Slide Pose with Subtle Friction Vibration ---
		var slide_shake: float = sin(Time.get_ticks_msec() * 0.04) * 0.012
		hips.position.x = lerpf(hips.position.x, 0.0, 14.0 * delta)
		hips.position.y = lerpf(hips.position.y, 0.33 + slide_shake, 18.0 * delta)
		hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(-42.0), 18.0 * delta)
		hips.rotation.y = 0.0
		hips.rotation.z = lerpf(hips.rotation.z, -_get_steer_input() * 0.18, 14.0 * delta)

		if torso:
			torso.rotation.y = lerpf(torso.rotation.y, deg_to_rad(6.0), 14.0 * delta)

		left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(65.0), 18.0 * delta)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(65.0), 18.0 * delta)
		left_arm.rotation.z = deg_to_rad(16.0)
		right_arm.rotation.z = -deg_to_rad(16.0)

		left_leg.rotation.x = lerpf(left_leg.rotation.x, deg_to_rad(-68.0), 18.0 * delta)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, deg_to_rad(-52.0), 18.0 * delta)

		if head:
			head.rotation.x = deg_to_rad(36.0)
			head.rotation.y = 0.0

	elif is_on_floor():
		# --- Realistic Biomechanical Human Running Motion ---
		var speed_ratio: float = current_run_speed / base_forward_speed
		var cadence: float = (21.0 if is_dashing else 14.2) * (0.85 + 0.15 * speed_ratio)
		run_cycle += delta * cadence

		# 1. Dual-harmonic smooth vertical bounce (peaks when either foot pushes off ground)
		var vertical_bounce: float = (1.0 - cos(run_cycle * 2.0)) * 0.048
		hips.position.y = HIPS_BASE_Y + vertical_bounce

		# 2. Lateral hip sway & weight transfer onto the planting foot
		var weight_shift: float = sin(run_cycle) * 0.038
		hips.position.x = lerpf(hips.position.x, weight_shift, 14.0 * delta)

		# 3. Pelvic rotation (yaw) driving the legs forward
		var pelvic_twist: float = sin(run_cycle) * 0.16
		hips.rotation.y = pelvic_twist
		hips.rotation.z = lerpf(hips.rotation.z, -_get_steer_input() * 0.22 - weight_shift * 0.6, 14.0 * delta)

		# 4. Forward athletic torso lean
		var base_lean: float = 14.0 + (speed_ratio - 1.0) * 8.0
		var forward_lean: float = deg_to_rad(26.0) if is_dashing else deg_to_rad(base_lean)
		hips.rotation.x = forward_lean

		# 5. Thoracic counter-rotation (spine twists oppositely to pelvis for realistic balance)
		if torso:
			torso.rotation.y = -pelvic_twist * 0.85
			torso.rotation.x = deg_to_rad(3.0)

		# 6. Biomechanical arm swing (elbows tucked, pumping forward-inward)
		var arm_swing: float = sin(run_cycle) * 0.90
		left_arm.rotation.x = -arm_swing
		right_arm.rotation.x = arm_swing
		left_arm.rotation.y = sin(run_cycle) * 0.18
		right_arm.rotation.y = -sin(run_cycle) * 0.18
		left_arm.rotation.z = deg_to_rad(12.0) + cos(run_cycle) * 0.06
		right_arm.rotation.z = -deg_to_rad(12.0) - cos(run_cycle) * 0.06

		# 7. Asymmetrical stride dynamics & knee drive
		var leg_stride: float = sin(run_cycle) * 0.96
		left_leg.rotation.x = leg_stride
		right_leg.rotation.x = -leg_stride
		left_leg.rotation.z = deg_to_rad(3.5) + pelvic_twist * 0.25
		right_leg.rotation.z = -deg_to_rad(3.5) + pelvic_twist * 0.25

		# 8. Vestibulo-ocular head stabilization (head stays level looking down-track)
		if head:
			head.rotation.x = -forward_lean * 0.6
			head.rotation.y = -pelvic_twist * 0.65

	else:
		# --- Dynamic 3-Phase Jumping Aerodynamics (Ascent vs Apex vs Descent) ---
		var vert_vel: float = velocity.y
		var jump_pose_blend: float = clampf(vert_vel / 12.0, -1.0, 1.0)

		hips.position.x = lerpf(hips.position.x, 0.0, 10.0 * delta)
		hips.position.y = lerpf(hips.position.y, HIPS_BASE_Y + 0.15, 10.0 * delta)
		hips.rotation.y = lerpf(hips.rotation.y, 0.0, 10.0 * delta)
		hips.rotation.z = lerpf(hips.rotation.z, -steer_input * 0.18, 8.0 * delta)

		if torso:
			torso.rotation.y = lerpf(torso.rotation.y, 0.0, 10.0 * delta)

		if jump_pose_blend > 0.1:
			# Upward explosion: arms raise for upward momentum, knees tuck slightly
			hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(12.0), 10.0 * delta)
			left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(-70.0), 14.0 * delta)
			right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-70.0), 14.0 * delta)
			left_arm.rotation.z = lerpf(left_arm.rotation.z, deg_to_rad(24.0), 12.0 * delta)
			right_arm.rotation.z = lerpf(right_arm.rotation.z, -deg_to_rad(24.0), 12.0 * delta)
			left_leg.rotation.x = lerpf(left_leg.rotation.x, deg_to_rad(30.0), 12.0 * delta)
			right_leg.rotation.x = lerpf(right_leg.rotation.x, deg_to_rad(18.0), 12.0 * delta)
		else:
			# Falling / Pre-landing: arms spread slightly outward for balance, legs reach to absorb shock
			hips.rotation.x = lerpf(hips.rotation.x, deg_to_rad(-10.0), 10.0 * delta)
			left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(-25.0), 12.0 * delta)
			right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-25.0), 12.0 * delta)
			left_arm.rotation.z = lerpf(left_arm.rotation.z, deg_to_rad(35.0), 12.0 * delta)
			right_arm.rotation.z = lerpf(right_arm.rotation.z, -deg_to_rad(35.0), 12.0 * delta)
			left_leg.rotation.x = lerpf(left_leg.rotation.x, deg_to_rad(15.0), 12.0 * delta)
			right_leg.rotation.x = lerpf(right_leg.rotation.x, deg_to_rad(5.0), 12.0 * delta)

		if head:
			head.rotation.x = lerpf(head.rotation.x, deg_to_rad(12.0), 10.0 * delta)
			head.rotation.y = 0.0
