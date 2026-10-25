extends Area3D

enum ItemType { COIN, TOKEN, LOW_BARRIER, HIGH_ARCH, FALLEN_LOG }
@export var item_type: ItemType = ItemType.COIN

@onready var sprite: Sprite3D = $Sprite3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var silver_coin_tex = preload("res://silver_coin.png")
var booster_token_tex = preload("res://booster_token.png")
var obstacle_icon_tex = preload("res://icon.svg")

func _ready() -> void:
	if item_type in [ItemType.LOW_BARRIER, ItemType.HIGH_ARCH, ItemType.FALLEN_LOG]:
		add_to_group("obstacles")
	body_entered.connect(_on_body_entered)
	setup_visuals()

func setup_visuals() -> void:
	if not sprite or not collision_shape:
		return

	match item_type:
		ItemType.COIN:
			# Circular silver coin
			sprite.texture = silver_coin_tex
			sprite.pixel_size = 0.0065
			sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
			collision_shape.shape.size = Vector3(1.0, 1.0, 0.8)
			collision_shape.position.y = 0.5
			sprite.position.y = 0.5
			scale = Vector3(1.0, 1.0, 1.0)
		ItemType.TOKEN:
			# Cyan lightning booster token
			sprite.texture = booster_token_tex
			sprite.pixel_size = 0.0085
			sprite.modulate = Color(0.2, 0.95, 1.0, 1.0)
			collision_shape.shape.size = Vector3(1.2, 1.2, 0.8)
			collision_shape.position.y = 0.55
			sprite.position.y = 0.55
			scale = Vector3(1.1, 1.1, 1.1)
		ItemType.LOW_BARRIER:
			# Low barrier on ground (must jump over or dash through)
			sprite.texture = obstacle_icon_tex
			sprite.pixel_size = 0.009
			sprite.modulate = Color(0.9, 0.25, 0.25, 1.0)
			collision_shape.shape.size = Vector3(1.5, 0.85, 0.8)
			collision_shape.position.y = 0.42
			sprite.position.y = 0.42
		ItemType.HIGH_ARCH:
			# High arch / hanging beam (must slide underneath or dash through)
			sprite.texture = obstacle_icon_tex
			sprite.pixel_size = 0.012
			sprite.modulate = Color(0.95, 0.65, 0.15, 1.0) # Amber archway
			collision_shape.shape.size = Vector3(2.2, 1.2, 0.8)
			collision_shape.position.y = 1.45 # Elevated off ground!
			sprite.position.y = 1.45
		ItemType.FALLEN_LOG:
			# Surprise fallen log spanning across lane (slide under or dash through)
			sprite.texture = obstacle_icon_tex
			sprite.pixel_size = 0.012
			sprite.modulate = Color(0.55, 0.35, 0.2, 1.0)
			collision_shape.shape.size = Vector3(2.6, 1.1, 1.0)
			collision_shape.position.y = 1.35
			sprite.position.y = 1.35

func _process(delta: float) -> void:
	if item_type == ItemType.COIN or item_type == ItemType.TOKEN:
		rotate_y(3.5 * delta)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
		
	var main = get_tree().current_scene
	match item_type:
		ItemType.COIN:
			if main and main.has_method("collect_coin"):
				main.collect_coin(global_position)
			queue_free()
		ItemType.TOKEN:
			if body.has_method("collect_token"):
				body.collect_token()
			if main and main.has_method("collect_token_ui"):
				main.collect_token_ui(global_position)
			queue_free()
		ItemType.LOW_BARRIER:
			if body.is_dashing:
				if main and main.has_method("destroy_obstacle"):
					main.destroy_obstacle(global_position, "SMASH! +250")
				queue_free()
			else:
				# If player didn't jump over it or dash through it
				get_tree().call_deferred("reload_current_scene")
		ItemType.HIGH_ARCH:
			if body.is_dashing:
				if main and main.has_method("destroy_obstacle"):
					main.destroy_obstacle(global_position, "ARCH SMASH! +300")
				queue_free()
			elif body.get("is_sliding") == true:
				# Player successfully slid underneath the elevated archway!
				if main and main.has_method("on_successful_slide"):
					main.on_successful_slide(global_position)
				# Archway remains or can be passed freely
			else:
				# Stood upright and hit the high arch
				get_tree().call_deferred("reload_current_scene")
		ItemType.FALLEN_LOG:
			if body.is_dashing:
				if main and main.has_method("destroy_obstacle"):
					main.destroy_obstacle(global_position, "TREE SMASH! +300")
				queue_free()
			elif body.get("is_sliding") == true:
				if main and main.has_method("on_successful_slide"):
					main.on_successful_slide(global_position)
			else:
				get_tree().call_deferred("reload_current_scene")
