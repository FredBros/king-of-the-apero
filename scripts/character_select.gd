extends Control

@onready var carousel: ActorCarousel = %Carousel
@onready var actor_tooltip: ActorTooltip = %InfoPanel
@onready var ok_button: Button = %OkButton
@onready var status_label: Label = %StatusLabel

var _selected_data: WrestlerData = null
var _has_confirmed: bool = false

func _ready() -> void:
	ok_button.text = tr("CHARSELECT_BTN_OK")
	ok_button.disabled = true
	ok_button.pressed.connect(_on_ok_pressed)
	status_label.text = ""

	carousel.preview_changed.connect(actor_tooltip.display)
	carousel.confirmed.connect(_on_character_confirmed)
	actor_tooltip.display(null)

	NetworkManager.game_message_received.connect(_on_network_message)

func _on_character_confirmed(data: WrestlerData) -> void:
	_selected_data = data
	ok_button.disabled = false

func _on_ok_pressed() -> void:
	if _has_confirmed or not _selected_data:
		return
	_has_confirmed = true
	ok_button.disabled = true
	carousel.lock()

	var path: String = _selected_data.resource_path
	NetworkManager.character_selections[NetworkManager.self_user_id] = path
	NetworkManager.send_message({"type": "SELECT_CHARACTER", "path": path})

	_try_transition()

func _on_network_message(data: Dictionary) -> void:
	if data.get("type") != "SELECT_CHARACTER":
		return
	var sender_id: String = data.get("_sender_id", "")
	if sender_id.is_empty():
		return
	NetworkManager.character_selections[sender_id] = data.get("path", "")
	_try_transition()

func _try_transition() -> void:
	if not _has_confirmed:
		return
	if NetworkManager.character_selections.size() < 2:
		status_label.text = tr("CHARSELECT_STATUS_WAITING")
		return
	NetworkManager.transition_to_arena()
