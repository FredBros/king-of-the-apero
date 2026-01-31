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
var _touch_start_pos: Vector2
var _is_touching: bool = false
var _is_swiping: bool = false
var _start_pos_local: Vector2
var _tween: Tween
var _is_selected: bool = false
var _has_moved_significantly: bool = false
var is_destroying: bool = false
var _shake_tween: Tween
var _idle_tween: Tween

func setup(data: CardData) -> void:
	card_data = data
	if is_node_ready():
		_update_visuals()

func _ready() -> void:
	# Set pivot to center for nice scaling
	resized.connect(func(): pivot_offset = size / 2)
	pivot_offset = size / 2
	
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
	else:
		value_label.text = str(card_data.value)
	
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

	# --- 3. Animation Idle (Frétillement) ---
	_start_idle_anim(tier)

func _start_idle_anim(tier: int) -> void:
	if _idle_tween: _idle_tween.kill()
	_idle_tween = create_tween().set_loops()
	
	var shake_angle = 0.0
	var duration = 1.0
	
	match tier:
		1:
			shake_angle = 1.0
			duration = 2.0
		2:
			shake_angle = 2.0
			duration = 1.0
		3:
			shake_angle = 3.0
			duration = 0.5
		4:
			shake_angle = 5.0
			duration = 0.2
	
	# Petit mouvement de rotation aléatoire/organique
	_idle_tween.tween_property(self , "rotation_degrees", shake_angle, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(self , "rotation_degrees", -shake_angle, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			clicked.emit(self ) # Sélectionne la carte (affiche les cases valides)
			_touch_start_pos = event.global_position
			_start_pos_local = position
			_is_touching = true
			_is_swiping = false
			_has_moved_significantly = false
			
			# Visual feedback on press
			z_index = 10
			_animate_scale(Vector2(1.2, 1.2))
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
				
				# Reset Z-Index and Scale based on selection state
				if _is_selected:
					z_index = 1
					_animate_scale(Vector2(1.2, 1.2))
				else:
					z_index = 0
					_animate_scale(Vector2(1.0, 1.0))
			
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
	if selected:
		# Highlight by making it brighter
		card_visual.modulate = Color(1.5, 1.5, 1.5)
		_animate_scale(Vector2(1.2, 1.2))
		z_index = 1
	else:
		card_visual.modulate = Color.WHITE
		_animate_scale(Vector2(1.0, 1.0))
		z_index = 0

func _animate_scale(target: Vector2) -> void:
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self , "scale", target, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_reaction_candidate(is_candidate: bool) -> void:
	if is_candidate:
		# Zoom et mise en avant
		self.scale = Vector2(1.4, 1.4)
		self.z_index = 10 # Passer au premier plan
		card_visual.modulate = Color(1.5, 1.5, 1.5) # Plus brillant
		# On pourrait ajouter un shader de contour ici plus tard
	else:
		# Retour à la normale (ou grisé si on veut montrer qu'elles sont invalides)
		self.scale = Vector2(1.0, 1.0)
		self.z_index = 0
		card_visual.modulate = Color(0.5, 0.5, 0.5) # On grise les cartes non valides

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
		if not _shake_tween or not _shake_tween.is_valid():
			_start_shake()
	else:
		if _shake_tween:
			_shake_tween.kill()
			_shake_tween = null
			rotation_degrees = 0

func _start_shake() -> void:
	if _shake_tween: _shake_tween.kill()
	_shake_tween = create_tween().set_loops()
	_shake_tween.tween_property(self , "rotation_degrees", 5.0, 0.05)
	_shake_tween.tween_property(self , "rotation_degrees", -5.0, 0.05)

func animate_destruction() -> void:
	is_destroying = true
	# Ensure shake continues or starts
	if not _shake_tween or not _shake_tween.is_valid():
		_start_shake()
	
	var tween = create_tween()
	tween.tween_property(self , "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)