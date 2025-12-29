class_name CardUI
extends PanelContainer

signal clicked(card_ui: CardUI)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var type_label: Label = $MarginContainer/VBoxContainer/TypeLabel
@onready var value_label: Label = $MarginContainer/VBoxContainer/ValueLabel

var card_data: CardData
var base_color: Color = Color.WHITE

func setup(data: CardData) -> void:
	card_data = data
	title_label.text = data.title
	value_label.text = str(data.value)
	
	# Simple visual feedback based on type
	match data.type:
		CardData.CardType.MOVE:
			type_label.text = "MOVE"
			base_color = Color(0.4, 0.6, 1.0) # Blueish
		CardData.CardType.ATTACK:
			type_label.text = "ATTACK"
			base_color = Color(1.0, 0.4, 0.4) # Reddish
		CardData.CardType.THROW:
			type_label.text = "THROW"
			base_color = Color(1.0, 0.8, 0.2) # Yellowish
	
	self.modulate = base_color

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(self)

func set_selected(selected: bool) -> void:
	if selected:
		# Highlight by making it brighter
		self.modulate = base_color.lightened(0.4)
		self.scale = Vector2(1.1, 1.1) # Pop effect
	else:
		self.modulate = base_color
		self.scale = Vector2(1.0, 1.0)