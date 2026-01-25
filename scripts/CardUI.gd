class_name CardUI
extends PanelContainer

signal clicked(card_ui: CardUI)
signal discard_requested(card_ui: CardUI)
signal drag_started(card_data: CardData)
signal drag_ended
signal swipe_pending(card_ui: CardUI, offset: Vector2)
signal swipe_committed(card_ui: CardUI, offset: Vector2, global_pos: Vector2)
signal selection_canceled(card_ui: CardUI)

@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var discard_button: Button = $MarginContainer/VBoxContainer/Header/DiscardButton
@onready var type_label: Label = $MarginContainer/VBoxContainer/TypeLabel
@onready var value_label: Label = $MarginContainer/VBoxContainer/ValueLabel

var card_data: CardData
var base_color: Color = Color.WHITE

var _touch_start_pos: Vector2
var _is_touching: bool = false
var _is_swiping: bool = false
var _start_pos_local: Vector2
var _tween: Tween
var _is_selected: bool = false
var _has_moved_significantly: bool = false

func setup(data: CardData) -> void:
	card_data = data
	if is_node_ready():
		_update_visuals()

func _ready() -> void:
	if discard_button:
		discard_button.pressed.connect(func(): discard_requested.emit(self))
	
	# Set pivot to center for nice scaling
	resized.connect(func(): pivot_offset = size / 2)
	pivot_offset = size / 2
	
	if card_data:
		_update_visuals()

func _update_visuals() -> void:
	if not card_data: return
	
	title_label.text = card_data.title
	
	if card_data.suit == "Joker":
		value_label.text = "★"
	else:
		value_label.text = str(card_data.value)
	
	# Simple visual feedback based on type
	if card_data.suit in ["Hearts", "Diamonds"]:
		type_label.text = "ATTACK " + _get_suit_icon(card_data.suit)
		base_color = Color(0.9, 0.3, 0.3) # Red
	elif card_data.suit == "Joker":
		type_label.text = "JOKER"
		base_color = Color(0.6, 0.3, 0.8) # Purple
	else:
		type_label.text = "MOVE " + _get_suit_icon(card_data.suit)
		base_color = Color(0.2, 0.2, 0.2) # Black/Grey
	
	self.modulate = base_color

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			clicked.emit(self) # Sélectionne la carte (affiche les cases valides)
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
				swipe_committed.emit(self, event.global_position - _touch_start_pos, event.global_position)
				drag_ended.emit()
			elif _has_moved_significantly:
				selection_canceled.emit(self)
			
			_is_touching = false
			_is_swiping = false
			swipe_pending.emit(self, Vector2.ZERO) # Reset visuel
			
			# Reset Position (Snap back)
			var pos_tween = create_tween()
			pos_tween.tween_property(self, "position", _start_pos_local, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			
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
			swipe_pending.emit(self, offset)
		else:
			# Si on revient au centre, on annule le swipe
			if _is_swiping: swipe_pending.emit(self, Vector2.ZERO)
			_is_swiping = false

func set_selected(selected: bool) -> void:
	_is_selected = selected
	if selected:
		# Highlight by making it brighter
		self.modulate = base_color.lightened(0.4)
		_animate_scale(Vector2(1.2, 1.2))
		discard_button.show()
		z_index = 1
	else:
		self.modulate = base_color
		_animate_scale(Vector2(1.0, 1.0))
		discard_button.hide()
		z_index = 0

func _animate_scale(target: Vector2) -> void:
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", target, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_reaction_candidate(is_candidate: bool) -> void:
	if is_candidate:
		# Zoom et mise en avant
		self.scale = Vector2(1.4, 1.4)
		self.z_index = 10 # Passer au premier plan
		self.modulate = Color(1.5, 1.5, 1.5) # Plus brillant
		# On pourrait ajouter un shader de contour ici plus tard
	else:
		# Retour à la normale (ou grisé si on veut montrer qu'elles sont invalides)
		self.scale = Vector2(1.0, 1.0)
		self.z_index = 0
		self.modulate = base_color.darkened(0.5) # On grise les cartes non valides

func _get_suit_icon(suit: String) -> String:
	match suit:
		"Spades": return "♠"
		"Clubs": return "♣"
		"Hearts": return "♥"
		"Diamonds": return "♦"
		"Joker": return "★"
	return ""