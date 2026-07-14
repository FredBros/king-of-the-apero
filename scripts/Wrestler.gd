class_name Wrestler
extends Node2D

signal died(wrestler: Wrestler)
signal health_changed(current: int, max: int)
signal action_completed
signal ejected

@export var max_health: int = 10
var current_health: int
var grid_position: Vector2i = Vector2i.ZERO
@export var wrestler_data: WrestlerData

const OUTLINE_SHADER = preload("res://shaders/character_outline.gdshader")
const OUTLINE_COLOR_DEFAULT = Color8(50, 50, 50) # #323232 de la palette

# Le sprite source est 12x12 (8x8 d'art effectif + marge de 2px de chaque côté pour les anims).
# Un "pixel de personnage" = un pixel de ce fichier source, donc SPRITE_SCALE fois plus grand
# à l'écran une fois affiché. On remonte le sprite de 2 pixels de personnage pour que les pieds
# se rapprochent du centre de la dalle et que la tête dépasse un peu de la case.
const SPRITE_SCALE := 2.0
const SPRITE_RAISE_PIXELS := 2.0
const SPRITE_Y_OFFSET := -SPRITE_RAISE_PIXELS * SPRITE_SCALE

const FLOATING_FONT = preload("res://assets/fonts/Bangers-Regular.ttf")
const SOUND_POOL_SCENE = preload("res://scenes/Components/SoundPoolComponent.tscn")
const DEFAULT_SOUND_SHOOTING_PUNCH = preload("res://assets/Sounds/Punch/Voice/shoutingpunches_male_default.wav")
const DEFAULT_SOUND_PUNCH = preload("res://assets/Sounds/Punch/Impact/punch_default.mp3")
const DEFAULT_SOUND_HURT = preload("res://assets/Sounds/Hurt/hurt_default.ogg")
const DEFAULT_SOUND_BLOCK = preload("res://assets/Sounds/block/block_default.wav")
const DEFAULT_SOUND_PUSHED = preload("res://assets/Sounds/Push/pushed_defaults.wav")
const DEFAULT_SOUND_FALL_IMPACT = preload("res://assets/Sounds/KO/Fall Impact/346694__deleted_user_2104797__body-fall_02.wav")
const DEFAULT_SOUND_DEATH_RATTLE = preload("res://assets/Sounds/KO/Death Rattle/death_rattle_default.wav")

# Reference to the grid manager to convert grid pos to world pos
var grid_manager
var is_ejected: bool = false

var is_busy: bool = false
var combat_target: Wrestler
var trigger_hurt_on_hit: bool = false
# Assurez-vous que cette variable est bien présente
var current_attack_is_push: bool = false

@onready var character_sprite: Sprite2D = $CharacterSprite

var sound_pool
var _pending_push_callback: Callable
var _pending_damage_callback: Callable

func _ready() -> void:
	_setup_outline_shader()
	if wrestler_data:
		initialize(wrestler_data)

func _process(delta: float) -> void:
	if not is_busy and not is_ejected and current_health > 0:
		_face_opponent(delta)

func _face_opponent(_delta: float) -> void:
	var opponent = _get_opponent()
	if opponent:
		_update_facing(opponent.global_position)

func _get_opponent() -> Wrestler:
	if not grid_manager: return null
	for w in grid_manager.wrestlers:
		if w != self:
			return w
	return null

# Symétrie gauche/droite du sprite en fonction de la position de l'adversaire (twins, pas de rotation 3D)
func _update_facing(target_pos: Vector2) -> void:
	if character_sprite:
		character_sprite.flip_h = target_pos.x < global_position.x

func _setup_outline_shader() -> void:
	if not character_sprite: return
	# Toujours au-dessus des tuiles et de l'indicateur de joueur actif (cf. GridManager._init_active_indicator)
	character_sprite.z_index = 1
	var mat = ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	mat.set_shader_parameter("outline_color", OUTLINE_COLOR_DEFAULT)
	character_sprite.material = mat

# Piste future : appeler ceci pour teinter le contour selon le joueur actif.
func set_outline_color(color: Color) -> void:
	if character_sprite and character_sprite.material:
		character_sprite.material.set_shader_parameter("outline_color", color)

# Initialize the wrestler from data (Stats, Sprite)
func initialize(data: WrestlerData) -> void:
	# 1. Stats
	# Setup Audio
	sound_pool = SOUND_POOL_SCENE.instantiate()
	add_child(sound_pool)

	wrestler_data = data
	max_health = data.max_health
	current_health = max_health

	# 2. Visuals : sprite 8x8 effectif (12x12 avec marge d'anim) scalé x2 pour remplir une dalle 16x16.
	if character_sprite:
		character_sprite.texture = data.sprite
		character_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
		character_sprite.position.y = SPRITE_Y_OFFSET

# Sets the initial position of the wrestler
func set_initial_position(pos: Vector2i, manager) -> void:
	grid_manager = manager
	reset_state() # On s'assure que le catcheur n'est plus "busy", "ejected" ou mort
	current_health = max_health
	health_changed.emit(current_health, max_health)

	# FIX: Teleport directly instead of walking to avoid issues and visual weirdness during restart
	grid_position = pos
	if grid_manager:
		position = grid_manager.grid_to_world(grid_position)
		# Force orientation towards center/opponent immediately
		_face_opponent(1.0)

# Moves the wrestler to a new grid position (instantly for now)
func move_to_grid_position(new_pos: Vector2i) -> void:
	_perform_move(new_pos)

func _perform_move(new_pos: Vector2i) -> void:
	# Logique de mouvement (exécutée chez tout le monde)
	is_busy = true
	if not grid_manager:
		printerr("GridManager not set for this wrestler!")
		return

	if not grid_manager.is_valid_cell(new_pos):
		printerr("Attempted to move wrestler to invalid cell: ", new_pos)
		return

	grid_position = new_pos
	# We use the grid manager to get the correct world coordinates
	var target_world_pos = grid_manager.grid_to_world(grid_position)

	var tween = create_tween()
	tween.tween_property(self , "position", target_world_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		is_busy = false
		print(name, " move action completed.")
		action_completed.emit()
	)
	_play_hop()

# Petit sautillement du sprite pendant le déplacement (le "twin" ne marche pas, il bondit de case en case)
func _play_hop() -> void:
	if not character_sprite: return
	var tween = create_tween()
	tween.tween_property(character_sprite, "position:y", SPRITE_Y_OFFSET - 6.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(character_sprite, "position:y", SPRITE_Y_OFFSET, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

# Perform an attack on a target wrestler
# La signature doit correspondre à l'appel dans GameManager (3 arguments)
func attack(target: Wrestler, will_hit: bool = false, is_push: bool = false) -> void:
	is_busy = true
	combat_target = target
	trigger_hurt_on_hit = will_hit
	current_attack_is_push = is_push

	# Son d'effort (Swing) au début de l'attaque
	_play_sound_or_default(wrestler_data.sound_shooting_punch, DEFAULT_SOUND_SHOOTING_PUNCH)

	await _play_attack_lunge(target.global_position)

	# L'impact se déclenche au pic du saut, avant le retour à la position d'origine
	if trigger_hurt_on_hit and combat_target:
		_play_sound_or_default(wrestler_data.sound_punch, DEFAULT_SOUND_PUNCH, -4.0)
		if current_attack_is_push:
			combat_target.execute_pending_push()
		combat_target.execute_pending_damage()
		# REMOVED: Damage is now handled by GameManager to prevent double-damage bug.
		# combat_target.take_damage(1, current_attack_is_push)
		trigger_hurt_on_hit = false

	await _play_attack_return()

	is_busy = false
	action_completed.emit()
	combat_target = null
	trigger_hurt_on_hit = false
	current_attack_is_push = false

var _attack_home_position: Vector2

# Saut + inclinaison vers la cible
func _play_attack_lunge(target_global_pos: Vector2) -> void:
	_attack_home_position = position
	var direction = (target_global_pos - global_position)
	if direction.length() > 0.001:
		direction = direction.normalized()
	var lunge_distance = grid_manager.cell_size * 0.4 if grid_manager else 6.0
	var lunge_offset = direction * lunge_distance
	var tilt = deg_to_rad(12.0 if direction.x >= 0.0 else -12.0)

	var tween = create_tween()
	tween.tween_property(self, "position", _attack_home_position + lunge_offset, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if character_sprite:
		tween.parallel().tween_property(character_sprite, "rotation", tilt, 0.11)
	await tween.finished

# Retour à sa position d'origine après l'attaque
func _play_attack_return() -> void:
	var tween = create_tween()
	tween.tween_property(self, "position", _attack_home_position, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if character_sprite:
		tween.parallel().tween_property(character_sprite, "rotation", 0.0, 0.22)
	await tween.finished

func play_hurt_animation(spawn_blood: bool = true) -> void:
	_play_sound_or_default(wrestler_data.sound_hurt, DEFAULT_SOUND_HURT, -2.0)
	if spawn_blood:
		_spawn_blood_effect()
	perform_hurt_sequence()

# Apply damage to the wrestler
func take_damage(amount: int, skip_anim: bool = false, immediate_visuals: bool = false) -> void:
	current_health -= amount
	print(name, " took ", amount, " damage. HP: ", current_health)

	var is_lethal = current_health <= 0
	var target_health = current_health # On capture la valeur cible pour la synchronisation

	# On prépare les effets visuels pour qu'ils soient synchronisés avec l'impact de l'attaquant
	_pending_damage_callback = func():
		health_changed.emit(target_health, max_health)
		show_floating_text("-" + str(amount) + " HP", Color.RED)
		if is_lethal:
			_spawn_blood_effect()
			is_busy = true
			print("Wrestler died. Attempting to play 'KO' pose.")
			_play_ko_pose()
			died.emit(self )
		else:
			if not skip_anim:
				_spawn_blood_effect()
				_play_sound_or_default(wrestler_data.sound_hurt, DEFAULT_SOUND_HURT, -2.0)
				perform_hurt_sequence()

	# Permet de forcer les effets sans attendre (ex: Dégâts environnementaux)
	if immediate_visuals:
		execute_pending_damage()

func execute_pending_damage() -> void:
	if _pending_damage_callback:
		_pending_damage_callback.call()
		_pending_damage_callback = Callable()

func perform_hurt_sequence() -> void:
	is_busy = true
	_play_hit_reaction()
	# Wait for Hurt animation to finish roughly
	await get_tree().create_timer(0.5).timeout
	if not is_ejected and current_health > 0:
		is_busy = false
		action_completed.emit()

func block() -> void:
	_play_sound_or_default(wrestler_data.sound_block, DEFAULT_SOUND_BLOCK)
	is_busy = true
	_play_block_hop()
	await get_tree().create_timer(0.5).timeout
	is_busy = false
	action_completed.emit()

# Direction opposée à l'adversaire, utilisée par le hop de blocage et la réaction d'impact
func _away_from_opponent_direction() -> Vector2:
	var opponent = _get_opponent()
	if not opponent:
		return Vector2.RIGHT
	var away = global_position - opponent.global_position
	if away.length() > 0.001:
		return away.normalized()
	return Vector2.RIGHT

# Saut en arrière lors d'un blocage : l'inverse du lunge d'attaque
func _play_block_hop() -> void:
	var direction = _away_from_opponent_direction()
	var distance = grid_manager.cell_size * 0.3 if grid_manager else 5.0
	var home = position

	var tween = create_tween()
	tween.tween_property(self, "position", home + direction * distance, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", home, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_play_hop()

# Recul rapide quand on encaisse un coup
func _play_hit_reaction() -> void:
	var direction = _away_from_opponent_direction()
	var distance = grid_manager.cell_size * 0.25 if grid_manager else 4.0
	var home = position

	var tween = create_tween()
	tween.tween_property(self, "position", home + direction * distance, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", home, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

# Update health from network authority (handles UI sync and animations)
func set_network_health(value: int) -> void:
	var previous_health = current_health
	current_health = value
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		if previous_health > 0:
			_play_ko_pose()
		died.emit(self )
	elif current_health < previous_health:
		perform_hurt_sequence()

# Force move the wrestler (can push out of bounds)
func push_to(new_pos: Vector2i) -> void:
	is_busy = true
	var old_pos = grid_position
	grid_position = new_pos
	var target_world_pos = grid_manager.grid_to_world(grid_position)

	# On prépare la logique visuelle mais on ne l'exécute pas tout de suite.
	# Elle sera déclenchée par l'attaquant via execute_pending_push() au moment de l'impact (on_hit_frame).
	_pending_push_callback = func():
		# Check if ejected
		if not grid_manager.is_valid_cell(grid_position):
			print(name, " EJECTED!")
			is_ejected = true
			ejected.emit()

			# Force l'exécution des dégâts visuels pour l'UI (synchronisation avec l'éjection)
			execute_pending_damage()

			# Visuals: Keep on ground level for now

			var tween = create_tween()
			_play_sound_or_default(wrestler_data.sound_pushed, DEFAULT_SOUND_PUSHED)
			tween.tween_property(self , "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_callback(_play_ko_pose)

			# Recovery Sequence (4 seconds later)
			get_tree().create_timer(4.0).timeout.connect(func(): _recover_from_ejection(old_pos))
		else:
			var tween = create_tween()
			# Son de poussée (réception)
			_play_sound_or_default(wrestler_data.sound_hurt, DEFAULT_SOUND_HURT, -2.0)
			_play_sound_or_default(wrestler_data.sound_pushed, DEFAULT_SOUND_PUSHED)
			tween.tween_property(self , "position", target_world_pos, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_callback(func():
				is_busy = false
				action_completed.emit()
			)

func execute_pending_push() -> void:
	if _pending_push_callback:
		_pending_push_callback.call()
		_pending_push_callback = Callable()

func _recover_from_ejection(original_pos: Vector2i) -> void:
	is_ejected = false
	# If dead, do not recover
	if current_health <= 0: return

	var return_pos = original_pos

	# Check if original position is occupied
	var occupant = grid_manager._get_wrestler_at(return_pos)
	if occupant and occupant != self:
		# Find a valid adjacent cell (fallback)
		var offsets = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
		for offset in offsets:
			var neighbor = original_pos + offset
			if grid_manager.is_valid_cell(neighbor) and grid_manager._get_wrestler_at(neighbor) == null:
				return_pos = neighbor
				break

	grid_position = return_pos
	position = grid_manager.grid_to_world(grid_position)
	if character_sprite:
		character_sprite.rotation = 0.0
		character_sprite.position.y = SPRITE_Y_OFFSET
	is_busy = false
	action_completed.emit()

func reset_state() -> void:
	is_ejected = false
	is_busy = false
	if character_sprite:
		character_sprite.rotation = 0.0
		character_sprite.position.y = SPRITE_Y_OFFSET

# Rotate the wrestler to face a target position (keeping Y axis upright)
func look_at_target(target_pos: Vector2) -> void:
	_update_facing(target_pos)

func _play_sound(stream: AudioStream) -> void:
	if stream and sound_pool:
		sound_pool.play_varied(stream)

func _play_sound_or_default(stream: AudioStream, default_stream: AudioStream, volume_offset: float = 0.0) -> void:
	var stream_to_play = stream if stream else default_stream
	if stream_to_play and sound_pool:
		sound_pool.play_varied(stream_to_play, volume_offset)

# Rotation à 90° pour simuler le KO (pas d'animation squelettique, juste le sprite qui bascule).
# L'angle est inversé selon flip_h pour que la chute soit toujours cohérente (pas tantôt sur le
# dos, tantôt sur le ventre selon le sens dans lequel le sprite regardait au moment du KO).
func _play_ko_pose() -> void:
	if not character_sprite: return
	var angle = deg_to_rad(90.0 if character_sprite.flip_h else -90.0)
	var tween = create_tween()
	tween.tween_property(character_sprite, "rotation", angle, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(on_ko_impact)

func on_ko_impact() -> void:
	_play_sound_or_default(wrestler_data.sound_fall_impact, DEFAULT_SOUND_FALL_IMPACT)
	_play_sound_or_default(wrestler_data.sound_death_rattle, DEFAULT_SOUND_DEATH_RATTLE)
	# Ici on pourrait aussi ajouter un Screen Shake via un signal vers l'Arena

# Appelé par le GameManager lors d'une esquive réussie
func play_dodge_sound() -> void:
	_play_sound(wrestler_data.sound_dodge)

func show_floating_text(text: String, color: Color) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_override("font", FLOATING_FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	label.position = Vector2(-8, -16)
	label.scale = Vector2.ZERO
	label.pivot_offset = Vector2(8, 4)

	# Animation Pop & Float
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - 10.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.3).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)

# Effet de sang : désactivé en attendant une version 2D (Phase 2)
func _spawn_blood_effect() -> void:
	pass

func set_collision_enabled(_enabled: bool) -> void:
	pass
