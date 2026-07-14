class_name CardUI
extends PanelContainer

signal clicked(card_ui: CardUI)
signal drag_started(card_data: CardData)
signal drag_ended
signal swipe_pending(card_ui: CardUI, offset: Vector2)
signal swipe_committed(card_ui: CardUI, offset: Vector2, global_pos: Vector2)
signal selection_canceled(card_ui: CardUI)
signal impact_occurred

@onready var value_label: Label = $MarginContainer/VBoxContainer/ValueLabel

var card_data: CardData
var base_color: Color = Color.WHITE

const CARD_TIER_FONT = preload("res://assets/fonts/04B_03__.TTF")
const CARD_FACES_TEXTURE = preload("res://assets/Cards/cards.png")
const CARD_FRAME_SIZE = 24
const CARD_COLOR_ATTACK = Color("#cc3d3d")
const CARD_COLOR_MOVE = Color("#202020")
# 7e et 8e dalles de cards.png : flèches "bonus" (fond transparent) à surimprimer sur une
# carte mouvement quand elle devient éligible au déplacement libre (combo 3/4).
const BONUS_ARROWS_ORTHO_FRAME := 6
const BONUS_ARROWS_DIAGONAL_FRAME := 7
var card_visual: TextureRect
var bonus_arrows_overlay: TextureRect
var _free_direction_bonus_active: bool = false
var push_icon: TextureRect
var _touch_start_pos: Vector2
var _is_touching: bool = false
var _is_swiping: bool = false
var _start_pos_local: Vector2
var _is_selected: bool = false
var _has_moved_significantly: bool = false
var is_destroying: bool = false

@onready var _combo_badge: Label = $ComboBadgeHolder/ComboBadge

var is_playable: bool = true
var is_reaction_candidate: bool = false
var _target_scale: Vector2 = Vector2.ONE
var _target_modulate: Color = Color.WHITE
var _current_base_scale: Vector2 = Vector2.ONE
var _kick_tween: Tween

func setup(data: CardData) -> void:
	card_data = data
	if is_node_ready():
		update_visuals()

func _ready() -> void:
	# Set pivot to center for nice scaling
	resized.connect(func(): pivot_offset = size / 2)
	pivot_offset = size / 2
	
	set_process(true)
	
	# Force un ratio carré pour correspondre au sous-bock
	# Réduction de la taille (220 -> 140) pour que 5 cartes rentrent sur mobile
	custom_minimum_size = Vector2(120, 120)
	
	# Important : Ne pas clipper le contenu (le texte du tier peut légèrement déborder)
	clip_contents = false

	# Sécurité : On s'assure que le parent (le wrapper dans GameUI) ne coupe pas non plus
	if get_parent() is Control:
		get_parent().clip_contents = false

	# Setup Visuals (TextureRect)
	card_visual = TextureRect.new()
	card_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# On l'ajoute en premier pour qu'il soit en fond
	add_child(card_visual)

	# Overlay des flèches bonus (au-dessus du fond, en dessous du chiffre de tier)
	bonus_arrows_overlay = TextureRect.new()
	bonus_arrows_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bonus_arrows_overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bonus_arrows_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bonus_arrows_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bonus_arrows_overlay.modulate.a = 0.0
	add_child(bonus_arrows_overlay)

	# Setup Font & Layout for Value
	if value_label:
		value_label.add_theme_font_override("font", CARD_TIER_FONT)
		value_label.add_theme_font_size_override("font_size", 46)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# On sort le label de son conteneur actuel pour le centrer librement sur la carte
		if value_label.get_parent():
			value_label.get_parent().remove_child(value_label)
		add_child(value_label)
		value_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	
	# Setup Push Icon (for attack hover)
	# On utilise un Node2D pour le sortir du layout automatique du PanelContainer
	var kick_holder = Node2D.new()
	add_child(kick_holder)
	
	push_icon = TextureRect.new()
	push_icon.texture = load("res://assets/UI/kick.png")
	push_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	push_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	push_icon.size = Vector2(90, 90) # Taille fixe de l'icône
	push_icon.position = Vector2(15, -90) # Position centrée au-dessus de la carte
	push_icon.pivot_offset = Vector2(45, 0) # L'axe de rotation est en haut au milieu (le "genou")
	push_icon.mouse_filter = MOUSE_FILTER_IGNORE
	push_icon.hide()
	kick_holder.add_child(push_icon)
	
	# On rend le fond du PanelContainer transparent pour ne voir que le visuel de la carte
	self_modulate = Color(1, 1, 1, 0)

	if card_data:
		update_visuals()

func _process(delta: float) -> void:
	if is_destroying: return

	# On lisse le changement d'échelle de base (Sélection, Drag...)
	_current_base_scale = _current_base_scale.lerp(_target_scale, delta * 15.0)
	scale = _current_base_scale

	# Sur "modulate" (pas juste card_visual) pour que le chiffre de tier grise en même temps que l'art
	modulate = modulate.lerp(_target_modulate, delta * 15.0)

func update_visuals() -> void:
	if not card_data: return

	if card_data.suit == "Joker":
		value_label.text = ""
	else:
		value_label.text = str(card_data.tier)
		var text_color = CARD_COLOR_MOVE
		if card_data.type == CardData.CardType.ATTACK:
			text_color = CARD_COLOR_ATTACK
		value_label.add_theme_color_override("font_color", text_color)

	card_visual.texture = _build_card_face_texture()

	if bonus_arrows_overlay and card_data.suit != "Joker":
		var bonus_frame = BONUS_ARROWS_DIAGONAL_FRAME if card_data.pattern == CardData.MovePattern.ORTHOGONAL else BONUS_ARROWS_ORTHO_FRAME
		bonus_arrows_overlay.texture = _build_atlas_frame(bonus_frame)

# Les 8 dalles de res://assets/Cards/cards.png (24x24 chacune), dans l'ordre : + noire, + rouge,
# x noire, x rouge, joker, flèches bonus ortho, flèches bonus diagonales.
func _build_card_face_texture() -> AtlasTexture:
	var frame_index := 4 # Joker
	if card_data.suit != "Joker":
		var is_diagonal = card_data.pattern == CardData.MovePattern.DIAGONAL
		var is_red = card_data.type == CardData.CardType.ATTACK
		if not is_diagonal and not is_red: frame_index = 0
		elif not is_diagonal and is_red: frame_index = 1
		elif is_diagonal and not is_red: frame_index = 2
		else: frame_index = 3

	return _build_atlas_frame(frame_index)

func _build_atlas_frame(frame_index: int) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = CARD_FACES_TEXTURE
	atlas.region = Rect2(frame_index * CARD_FRAME_SIZE, 0, CARD_FRAME_SIZE, CARD_FRAME_SIZE)
	return atlas

# Affiché en surimpression quand une carte mouvement devient éligible au déplacement libre
# (combo 3/4) : fade in + petit bump, pour compléter les 4 flèches manquantes sur la carte.
func set_free_direction_bonus(enabled: bool) -> void:
	if _free_direction_bonus_active == enabled: return
	_free_direction_bonus_active = enabled
	if not bonus_arrows_overlay: return

	var tween = create_tween()
	if enabled:
		bonus_arrows_overlay.pivot_offset = bonus_arrows_overlay.size / 2.0
		bonus_arrows_overlay.scale = Vector2(0.8, 0.8)
		tween.set_parallel(true)
		tween.tween_property(bonus_arrows_overlay, "modulate:a", 1.0, 0.15)
		tween.tween_property(bonus_arrows_overlay, "scale", Vector2(1.15, 1.15), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(bonus_arrows_overlay, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(bonus_arrows_overlay, "modulate:a", 0.0, 0.1)

func set_playable(playable: bool) -> void:
	is_playable = playable
	if _combo_badge:
		_combo_badge.visible = _combo_badge.visible and is_playable
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
			# On ne peut sélectionner (pour voir les cases) qu'une carte jouable.
			# On peut quand même la "toucher" et la drag-drop pour une autre action (ex: défausse).
			if is_playable:
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

func set_combo_eligible(eligible: bool) -> void:
	if _combo_badge:
		_combo_badge.visible = eligible and is_playable

func _get_suit_icon(suit: String) -> String:
	match suit:
		"Spades": return "+"
		"Clubs": return "X"
		"Hearts": return "+"
		"Diamonds": return "X"
		"Joker": return ""
	return ""

func set_discard_hover_state(state: bool) -> void:
	if is_destroying: return
	# Inclinaison statique (plus de tremblement continu) pour signaler la défausse
	rotation_degrees = 8.0 if state else 0.0

func set_push_hover_state(is_hovering: bool) -> void:
	if is_destroying: return
	
	if push_icon:
		if is_hovering and not push_icon.visible:
			push_icon.show()
			
			# Démarrer l'animation de coup de pied
			if _kick_tween and _kick_tween.is_valid():
				_kick_tween.kill()
				
			push_icon.rotation_degrees = 0
			_kick_tween = create_tween().set_loops()
			# 1. Armement (genou plié vers l'arrière)
			_kick_tween.tween_property(push_icon, "rotation_degrees", 40.0, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			# 2. Frappe (extension brusque vers l'avant)
			_kick_tween.tween_property(push_icon, "rotation_degrees", -25.0, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			# 3. Maintien de la pose après l'impact
			_kick_tween.tween_interval(0.1)
			# 4. Retour à la position neutre
			_kick_tween.tween_property(push_icon, "rotation_degrees", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			# 5. Pause avant le prochain coup
			_kick_tween.tween_interval(0.2)
			
		elif not is_hovering and push_icon.visible:
			push_icon.hide()
			if _kick_tween and _kick_tween.is_valid():
				_kick_tween.kill()

func animate_destruction() -> void:
	is_destroying = true
	
	var tween = create_tween()
	tween.tween_property(self , "scale", Vector2.ZERO, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)

func animate_slap(target_global_pos: Vector2) -> void:
	is_destroying = true
	z_index = 20 # Au-dessus de tout pour l'impact
	
	# Détacher du layout pour bouger librement vers la cible
	top_level = true
	
	# Teleport to target (centered)
	var centered_target = target_global_pos - (size / 2.0)
	global_position = centered_target
	
	# Initial State: Invisible and Big
	scale = Vector2(2.0, 2.0)
	modulate.a = 0.0
	
	var tween = create_tween()
	
	# 1. Slam Down (Fade In + Scale Down)
	tween.set_parallel(true)
	tween.tween_property(self , "modulate:a", 1.0, 0.1)
	tween.tween_property(self , "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	
	# 2. Impact Trigger & Effects
	tween.chain().tween_callback(func():
		impact_occurred.emit()
		rotation_degrees = randf_range(-3.0, 3.0)
	)
	
	# 3. Squash
	tween.set_parallel(true)
	tween.tween_property(self , "scale", Vector2(1.2, 0.8), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 4. Return to normal
	tween.chain().tween_property(self , "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	# 5. Fade out and destroy
	tween.chain().tween_interval(1.0)
	tween.chain().tween_property(self , "modulate:a", 0.0, 0.2)
	tween.finished.connect(queue_free)