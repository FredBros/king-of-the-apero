extends Control

signal step_completed(step_id: String)
signal tutorial_skipped()

@onready var panel = $ChalkPanel
@onready var text_label = $ChalkPanel/MarginContainer/VBoxContainer/RichTextLabel
@onready var media_container = $ChalkPanel/MarginContainer/VBoxContainer/MediaContainer
@onready var images_container = $ChalkPanel/MarginContainer/VBoxContainer/MediaContainer/ImagesContainer
@onready var video_player = $ChalkPanel/MarginContainer/VBoxContainer/MediaContainer/VideoPlayer
@onready var next_button_panel = $ChalkPanel/MarginContainer/VBoxContainer/HBoxContainer/NextButtonPanel
@onready var next_button = $ChalkPanel/MarginContainer/VBoxContainer/HBoxContainer/NextButtonPanel/NextButton
@onready var skip_button_panel = $ChalkPanel/MarginContainer/VBoxContainer/HBoxContainer/SkipButtonPanel
@onready var skip_button = $ChalkPanel/MarginContainer/VBoxContainer/HBoxContainer/SkipButtonPanel/SkipButton

var current_step_id: String = ""
var pauses_game: bool = false

var _highlighted_node: Control = null
var _original_z_index: int = 0
var _original_z_relative: bool = true

func _ready() -> void:
	next_button.pressed.connect(_on_next_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	video_player.finished.connect(_on_video_finished)
	
	# Animation d'apparition
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self , "modulate:a", 1.0, 0.3)
	
	_start_next_button_pulse()

func display_tooltip(step_id: String, text_key: String, target_node: Node = null, p_pauses_game: bool = false, media_textures: Array[Texture2D] = [], video_stream: VideoStream = null) -> void:
	current_step_id = step_id
	pauses_game = p_pauses_game
	
	text_label.text = "[center]" + tr(text_key) + "[/center]"
	
	# Nettoyage des images précédentes
	for child in images_container.get_children():
		child.queue_free()
		
	var has_media = false
	
	if not media_textures.is_empty():
		for tex in media_textures:
			if tex:
				var rect = TextureRect.new()
				rect.texture = tex
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				rect.custom_minimum_size = Vector2(100, 150)
				rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				images_container.add_child(rect)
		images_container.show()
		has_media = true
	else:
		images_container.hide()
		
	if video_stream:
		video_player.stream = video_stream
		video_player.show()
		video_player.play()
		has_media = true
	else:
		video_player.stop()
		video_player.hide()
		
	media_container.visible = has_media
		
	# Affichage du fond gris si le jeu est en pause OU si on met en lumière un élément UI
	if pauses_game or is_instance_valid(target_node):
		$Dimmer.show()
	else:
		$Dimmer.hide()
		
	if pauses_game:
		process_mode = Node.PROCESS_MODE_ALWAYS
		
	_position_tooltip(target_node)

func _position_tooltip(target_node: Node) -> void:
	await get_tree().process_frame # Attendre que les tailles soient calculées par Godot
	
	var target_pos = Vector2.ZERO
	var has_target = false
	
	if target_node is Control:
		target_pos = target_node.global_position + (target_node.size / 2.0)
		has_target = true
		
		# --- MISE EN LUMIÈRE (Spotlight Effect) ---
		_highlighted_node = target_node
		_original_z_index = _highlighted_node.z_index
		_original_z_relative = _highlighted_node.z_as_relative
		
		# On le fait passer par-dessus le fond gris (z_index 250)
		_highlighted_node.z_index = 251
		_highlighted_node.z_as_relative = false
		
		# On s'assure que l'infobulle reste toujours au-dessus de l'élément mis en valeur
		panel.z_index = 252
		panel.z_as_relative = false
		
	elif target_node is Node3D:
		var cam = get_viewport().get_camera_3d()
		if cam:
			target_pos = cam.unproject_position(target_node.global_position)
			has_target = true
			
	if has_target:
		var screen_size = get_viewport_rect().size
		var panel_size = panel.size
		var margin = 40.0 # Marge réduite vu qu'il n'y a plus de flèche
		var final_pos = target_pos
		
		# Placer au-dessus ou en-dessous selon la place dispo
		if target_pos.y > screen_size.y / 2.0:
			final_pos.y = target_pos.y - panel_size.y - margin
		else:
			final_pos.y = target_pos.y + margin
			
		# Contraindre horizontalement pour ne pas sortir de l'écran
		final_pos.x = clamp(target_pos.x - (panel_size.x / 2.0), 20.0, screen_size.x - panel_size.x - 20.0)
		
		panel.global_position = final_pos
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

func _start_next_button_pulse() -> void:
	await get_tree().process_frame # S'assurer que le layout est calculé
	if not is_instance_valid(next_button_panel): return
	
	next_button_panel.pivot_offset = next_button_panel.size / 2.0
	
	var tween = create_tween().set_loops()
	tween.tween_property(next_button_panel, "modulate", Color(1.1, 1.1, 1.1), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(next_button_panel, "scale", Vector2(1.05, 1.05), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	tween.tween_property(next_button_panel, "modulate", Color(1.0, 1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(next_button_panel, "scale", Vector2(1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_next_pressed() -> void:
	_close_tooltip()
	step_completed.emit(current_step_id)

func _on_skip_pressed() -> void:
	_close_tooltip()
	tutorial_skipped.emit()

func _on_video_finished() -> void:
	if video_player.stream:
		video_player.play() # Boucle la vidéo infiniment tant que le tooltip est ouvert

func _close_tooltip() -> void:
	# Restauration de l'élément mis en lumière à sa couche d'origine
	if is_instance_valid(_highlighted_node):
		_highlighted_node.z_index = _original_z_index
		_highlighted_node.z_as_relative = _original_z_relative
		_highlighted_node = null
		
	var tween = create_tween()
	tween.tween_property(self , "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)
