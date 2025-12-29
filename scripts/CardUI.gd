class_name CardUI
extends PanelContainer

signal clicked(card_ui: CardUI)
signal discard_requested(card_ui: CardUI)

@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleLabel
@onready var discard_button: Button = $MarginContainer/VBoxContainer/Header/DiscardButton
@onready var type_label: Label = $MarginContainer/VBoxContainer/TypeLabel
@onready var value_label: Label = $MarginContainer/VBoxContainer/ValueLabel

var card_data: CardData
var base_color: Color = Color.WHITE

func setup(data: CardData) -> void:
	card_data = data
	title_label.text = data.title
	
	if data.suit == "Joker":
		value_label.text = "★"
	else:
		value_label.text = str(data.value)
	
	# Simple visual feedback based on type
	if data.suit in ["Hearts", "Diamonds"]:
		type_label.text = "ATTACK"
		base_color = Color(0.9, 0.3, 0.3) # Red
	elif data.suit == "Joker":
		type_label.text = "JOKER"
		base_color = Color(0.6, 0.3, 0.8) # Purple
	else:
		type_label.text = "MOVE"
		base_color = Color(0.2, 0.2, 0.2) # Black/Grey
	
	self.modulate = base_color

func _ready() -> void:
	if discard_button:
		discard_button.pressed.connect(func(): discard_requested.emit(self))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(self)

func set_selected(selected: bool) -> void:
	if selected:
		# Highlight by making it brighter
		self.modulate = base_color.lightened(0.4)
		self.scale = Vector2(1.1, 1.1) # Pop effect
		discard_button.show()
	else:
		self.modulate = base_color
		self.scale = Vector2(1.0, 1.0)
		discard_button.hide()