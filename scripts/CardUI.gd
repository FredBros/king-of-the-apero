class_name CardUI
extends PanelContainer

signal clicked(card_ui: CardUI)
signal drag_started(card_data: CardData)
signal drag_ended
signal swipe_pending(card_ui: CardUI, offset: Vector2)
signal swipe_committed(card_ui: CardUI, offset: Vector2, global_pos: Vector2)
signal selection_canceled(card_ui: CardUI)

@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var type_label: Label = $MarginContainer/VBoxContainer/TypeLabel
@onready var value_label: Label = $MarginContainer/VBoxContainer/ValueLabel

var card_data: CardData
var base_color: Color = Color.WHITE

const CARD_FONT = preload("res://assets/fonts/Bangers-Regular.ttf")
const AURA_SHADER = preload("res://shaders/aura_sous_bock.gdshader")
var card_visual: TextureRect
var aura_rect: ColorRect
var aura_holder: Node2D
var push_icon: TextureRect
var _touch_start_pos: Vector2
var _is_touching: bool = false
var _is_swiping: bool = false
var _start_pos_local: Vector2
var _is_selected: bool = false
var _has_moved_significantly: bool = false
var is_destroying: bool = false

var is_playable: bool = true
var is_reaction_candidate: bool = false
var current_tier: int = 1
var _target_scale: Vector2 = Vector2.ONE
var _target_modulate: Color = Color.WHITE
var _current_base_scale: Vector2 = Vector2.ONE
var _discard_shake_intensity: float = 0.0

func setup(data: CardData) -> void:
	card_data = data
	if is_node_ready():
		_update_visuals()

func _ready() -> void:
	# Set pivot to center for nice scaling
	resized.connect(func(): pivot_offset = size / 2)
	pivot_offset = size / 2
	
	set_process(true)
	
	# Force un ratio carré pour correspondre au sous-bock
	# Réduction de la taille (220 -> 140) pour que 5 cartes rentrent sur mobile
	custom_minimum_size = Vector2(120, 120)
	
	# Important : Ne pas clipper le contenu pour voir l'aura qui dépasse
	clip_contents = false
	
	# Sécurité : On s'assure que le parent (le wrapper dans GameUI) ne coupe pas non plus
	if get_parent() is Control:
		get_parent().clip_contents = false
	
	# --- Setup Aura (Arrière-plan) ---
	# On utilise un Node2D pour que le PanelContainer ne redimensionne pas l'aura
	aura_holder = Node2D.new()
	add_child(aura_holder)
	
	aura_rect = ColorRect.new()
	aura_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Ne pas bloquer les clics
	
	# Setup Material & Noise
	var aura_mat = ShaderMaterial.new()
	aura_mat.shader = AURA_SHADER
	
	var noise = FastNoiseLite.new()
	noise.frequency = 0.02 # Bruit assez large pour faire "fumée"
	var noise_tex = NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.noise = noise
	noise_tex.seamless = true
	aura_mat.set_shader_parameter("noise_tex", noise_tex)
	
	aura_rect.material = aura_mat
	aura_holder.add_child(aura_rect)
	
	# Setup Visuals (TextureRect)
	card_visual = TextureRect.new()
	card_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# On l'ajoute en premier pour qu'il soit en fond
	add_child(card_visual)
	
	# Setup Font & Layout for Value
	if value_label:
		value_label.add_theme_font_override("font", CARD_FONT)
		value_label.add_theme_font_size_override("font_size", 40)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# On sort le label de son conteneur actuel pour le centrer librement sur la carte
		if value_label.get_parent():
			value_label.get_parent().remove_child(value_label)
		add_child(value_label)
		value_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	# Setup Push Icon (for attack hover)
	push_icon = TextureRect.new()
	push_icon.texture = load("res://assets/UI/kick.png")
	push_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	push_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	push_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	push_icon.mouse_filter = MOUSE_FILTER_IGNORE
	push_icon.hide()
	add_child(push_icon)
	
	# On cache les anciens labels inutiles pour le nouveau design
	if title_label: title_label.hide()
	if type_label: type_label.hide()
	
	# On rend le fond du PanelContainer transparent pour ne voir que le coaster
	self_modulate = Color(1, 1, 1, 0)
	
	# Mise à jour de la géométrie de l'aura quand la carte change de taille
	resized.connect(_update_aura_geometry)
	_update_aura_geometry()
	
	if card_data:
		_update_visuals()

func _process(delta: float) -> void:
	if is_destroying: return
	
	# --- 1. Gestion de l'Échelle (Smooth Lerp) ---
	# On lisse le changement d'échelle de base (Sélection, Drag...)
	_current_base_scale = _current_base_scale.lerp(_target_scale, delta * 15.0)
	
	if card_visual:
		card_visual.modulate = card_visual.modulate.lerp(_target_modulate, delta * 15.0)
	
	# --- 2. Vibration (Vibes.md) ---
	# On ne vibre pas si on est en train de draguer la carte (pour la lisibilité)
	var apply_vibe = not _is_touching
	
	var power = 1.0
	match current_tier:
		1: power = 1.0
		2: power = 4.0
		3: power = 7.0
		4: power = 10.0
	
	# Intensité globale
	var intensity = power * 0.5
	
	# Jitter de Rotation (Chaos contrôlé)
	# On ajoute l'intensité du "Discard Shake" si nécessaire
	var total_rot_intensity = intensity + _discard_shake_intensity
	var rot_jitter = 0.0
	if apply_vibe or _discard_shake_intensity > 0.0:
		rot_jitter = deg_to_rad(randf_range(-total_rot_intensity * 0.5, total_rot_intensity * 0.5))
	
	rotation = rot_jitter
	
	# Jitter d'Échelle (Effet "Pulsation / Envie de sauter")
	var s_jitter = 1.0
	if apply_vibe:
		s_jitter = 1.0 + (randf_range(0.0, intensity) * 0.005)
	
	scale = _current_base_scale * s_jitter

func _update_aura_geometry() -> void:
	if not aura_rect: return
	var margin = 30
	# On positionne manuellement car le Node2D échappe au layout du Container
	aura_rect.size = size + Vector2(margin * 2, margin * 2)
	aura_rect.position = - Vector2(margin, margin)

func _update_visuals() -> void:
	if not card_data: return
	
	if card_data.suit == "Joker":
		value_label.text = "★"
		# Use a dark color for the Joker's star for better visibility
		value_label.add_theme_color_override("font_color", Color.from_string("#262b44", Color.WHITE))
	else:
		value_label.text = str(card_data.value)
		# Set font color based on card type (red/black)
		if card_data.type == CardData.CardType.ATTACK: # Red cards
			value_label.add_theme_color_override("font_color", Color.from_string("#a22633", Color.WHITE))
		else: # Black cards
			value_label.add_theme_color_override("font_color", Color.from_string("#262b44", Color.WHITE))
	
	# --- 1. Chargement de la Texture (Skin) ---
	var color_str = "black"
	if card_data.type == CardData.CardType.ATTACK: color_str = "red"
	
	var pattern_str = "ortho"
	if card_data.pattern == CardData.MovePattern.DIAGONAL: pattern_str = "diag"
	
	var tier = ceil(card_data.value / 3.0) # 1 à 4
	var filename = "coaster_%s_%s_%d.png" % [color_str, pattern_str, tier]
	
	if card_data.suit == "Joker":
		filename = "coaster_joker.png"
		tier = 4 # Joker est considéré Tier Max pour les effets
	current_tier = int(tier)
	
	var texture_path = "res://assets/Cards/" + filename
	if ResourceLoader.exists(texture_path):
		card_visual.texture = load(texture_path)
	else:
		printerr("Texture manquante: ", texture_path)

	# --- 2. Configuration de l'Aura (Shader) ---
	var halo_color = Color.WHITE
	var pulse_speed = 1.0
	var intensity = 1.0
	
	match int(tier):
		1:
			halo_color = Color("#ffffff") # Blanc
			pulse_speed = 0.5
			intensity = 0.5 # Réduit pour plus de transparence
		2:
			halo_color = Color("#63c74d") # Vert
			pulse_speed = 2.0
			intensity = 1.0 # Réduit
		3:
			halo_color = Color("#0099db") # Bleu
			pulse_speed = 4.0
			intensity = 1.5 # Réduit
		4:
			if card_data.suit == "Joker":
				halo_color = Color("#68386c") # Violet
			else:
				halo_color = Color("#fee761") # Jaune
			pulse_speed = 8.0
			intensity = 2.5 # Réduit
	
	if aura_rect.material:
		aura_rect.material.set_shader_parameter("aura_color", halo_color)
		aura_rect.material.set_shader_parameter("speed", pulse_speed * 0.5) # Ajustement vitesse shader
		aura_rect.material.set_shader_parameter("intensity", intensity)

func set_playable(playable: bool) -> void:
	is_playable = playable
	_update_visual_state()

func _update_visual_state() -> void:
	if is_reaction_candidate:
		_target_modulate = Color(1.5, 1.5, 1.5)
		_target_scale = Vector2(1.4, 1.4)
		z_index = 10
		return

	if _is_touching:
		_target_modulate = Color(1.5, 1.5, 1.5)
		_target_scale = Vector2(1.2, 1.2)
		z_index = 10
	elif _is_selected:
		_target_modulate = Color(1.5, 1.5, 1.5)
		_target_scale = Vector2(1.2, 1.2)
		z_index = 1
	else:
		z_index = 0
		_target_scale = Vector2.ONE
		if is_playable:
			_target_modulate = Color.WHITE
		else:
			_target_modulate = Color(0.5, 0.5, 0.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			clicked.emit(self ) # Sélectionne la carte (affiche les cases valides)
			_touch_start_pos = event.global_position
			_start_pos_local = position
			_is_touching = true
			_is_swiping = false
			_has_moved_significantly = false
			_update_visual_state()
			
			# Visual feedback on press
			z_index = 10
		else:
			# Release
			if _is_swiping:
				swipe_committed.emit(self , event.global_position - _touch_start_pos, event.global_position)
				drag_ended.emit()
			elif _has_moved_significantly:
				selection_canceled.emit(self )
			
			_is_touching = false
			_is_swiping = false
			swipe_pending.emit(self , Vector2.ZERO) # Reset visuel
			
			if not is_destroying:
				# Reset Position (Snap back)
				var pos_tween = create_tween()
				pos_tween.tween_property(self , "position", _start_pos_local, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
				
				_update_visual_state()
			
	elif event is InputEventMouseMotion and _is_touching:
		var offset = event.global_position - _touch_start_pos
		
		# Follow finger
		position = _start_pos_local + offset
		
		if offset.length() > 20.0: # Seuil de détection du swipe
			if not _is_swiping:
				_has_moved_significantly = true
				_is_swiping = true
				drag_started.emit(card_data)
			swipe_pending.emit(self , offset)
		else:
			# Si on revient au centre, on annule le swipe
			if _is_swiping: swipe_pending.emit(self , Vector2.ZERO)
			_is_swiping = false

func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_visual_state()

func set_reaction_candidate(is_candidate: bool) -> void:
	is_reaction_candidate = is_candidate
	_update_visual_state()

func _get_suit_icon(suit: String) -> String:
	match suit:
		"Spades": return "♠"
		"Clubs": return "♣"
		"Hearts": return "♥"
		"Diamonds": return "♦"
		"Joker": return "★"
	return ""

func set_discard_hover_state(state: bool) -> void:
	if is_destroying: return
	
	if state:
		_discard_shake_intensity = 5.0 # Degrés de vibration supplémentaire
	else:
		_discard_shake_intensity = 0.0

func set_push_hover_state(is_hovering: bool) -> void:
	if is_destroying: return
	
	if push_icon:
		push_icon.visible = is_hovering

func animate_destruction() -> void:
	is_destroying = true
	
	var tween = create_tween()
	tween.tween_property(self , "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)