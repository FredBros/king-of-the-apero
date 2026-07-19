class_name ActorCarousel
extends Control

## Carrousel de sélection de personnage : scanne res://resources/Actors/,
## affiche une carte (portrait + badge, grayscale sauf survol/sélection) par
## personnage dans une rangée défilable (swipe ou flèches).

## Emis à chaque changement de ce qui doit être prévisualisé (survol, fin de
## survol -> retour à la sélection courante ou à rien).
signal preview_changed(data: WrestlerData)
## Emis quand un personnage est cliqué/sélectionné.
signal confirmed(data: WrestlerData)

const ACTORS_DIR := "res://resources/Actors/"
const GRAYSCALE_SHADER := preload("res://shaders/grayscale.gdshader")
const UI_SOUND_COMPONENT_SCENE := preload("res://scenes/Components/UISoundComponent.tscn")

const CARD_SIZE := Vector2(150, 190)
const PORTRAIT_HEIGHT := 130.0
const BADGE_HEIGHT := 40.0
const CARD_SEPARATION := 16.0
const PAGE_STEP := 150.0 + 16.0 # largeur carte + séparation
const TAP_THRESHOLD := 20.0 # au-delà, on considère que c'est un swipe, pas un clic

@onready var cards_scroll: ScrollContainer = %CardsScroll
@onready var cards_row: HBoxContainer = %CardsRow
@onready var left_arrow: Control = %LeftArrow
@onready var right_arrow: Control = %RightArrow

var ui_sound: UISoundComponent

var _selected_card: Dictionary = {} # { data, portrait_rect, badge_rect, panel }
var _locked: bool = false

var _is_dragging: bool = false
var _drag_start_x: float = 0.0
var _scroll_start: int = 0

func _ready() -> void:
	ui_sound = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(ui_sound)

	left_arrow.gui_input.connect(_on_arrow_gui_input.bind(true))
	right_arrow.gui_input.connect(_on_arrow_gui_input.bind(false))
	cards_scroll.gui_input.connect(_on_scroll_gui_input)

	_populate()

## Empêche toute nouvelle interaction (appelé une fois le choix validé, en attente de l'adversaire).
func lock() -> void:
	_locked = true

func _populate() -> void:
	var dir = DirAccess.open(ACTORS_DIR)
	if not dir:
		printerr("ActorCarousel: impossible d'ouvrir ", ACTORS_DIR)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	var paths: Array = []
	while file_name != "":
		if file_name.ends_with(".tres"):
			paths.append(ACTORS_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()

	for path in paths:
		var data: WrestlerData = load(path)
		if data:
			_add_card(data)

func _add_card(data: WrestlerData) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PlayerInfoPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = CARD_SIZE

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var portrait_rect := TextureRect.new()
	portrait_rect.texture = data.portrait
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.custom_minimum_size = Vector2(0, PORTRAIT_HEIGHT)
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_mat := ShaderMaterial.new()
	portrait_mat.shader = GRAYSCALE_SHADER
	portrait_mat.set_shader_parameter("gray_amount", 1.0)
	portrait_rect.material = portrait_mat
	vbox.add_child(portrait_rect)

	var badge_rect := TextureRect.new()
	badge_rect.texture = data.badge
	badge_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge_rect.custom_minimum_size = Vector2(0, BADGE_HEIGHT)
	badge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_mat := ShaderMaterial.new()
	badge_mat.shader = GRAYSCALE_SHADER
	badge_mat.set_shader_parameter("gray_amount", 1.0)
	badge_rect.material = badge_mat
	vbox.add_child(badge_rect)

	cards_row.add_child(panel)

	var card := {
		"data": data,
		"portrait_rect": portrait_rect,
		"badge_rect": badge_rect,
		"panel": panel,
		"press_pos": Vector2.ZERO,
	}
	panel.mouse_entered.connect(_on_card_hover.bind(card))
	panel.mouse_exited.connect(_on_card_unhover.bind(card))
	panel.gui_input.connect(_on_card_gui_input.bind(card))

func _on_card_hover(card: Dictionary) -> void:
	if _locked:
		return
	_set_card_color(card, true)
	preview_changed.emit(card.data)

func _on_card_unhover(card: Dictionary) -> void:
	if _locked:
		return
	if _selected_card.get("data") != card.data:
		_set_card_color(card, false)
	if _selected_card.has("data"):
		preview_changed.emit(_selected_card.data)
	else:
		preview_changed.emit(null)

## Le clic ne sélectionne qu'au relâchement, et seulement si le doigt/curseur
## n'a pas assez bougé entre-temps (sinon c'est un swipe du carrousel).
func _on_card_gui_input(event: InputEvent, card: Dictionary) -> void:
	if _locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			card.press_pos = event.position
		elif event.position.distance_to(card.press_pos) < TAP_THRESHOLD:
			_select_card(card)

func _select_card(card: Dictionary) -> void:
	if _selected_card.get("data") == card.data:
		return

	if _selected_card.has("data") and _selected_card.data != card.data:
		_set_card_color(_selected_card, false)

	_selected_card = card
	_set_card_color(card, true)
	preview_changed.emit(card.data)
	confirmed.emit(card.data)

	if card.data.sound_name:
		ui_sound.play_varied(card.data.sound_name)

func _set_card_color(card: Dictionary, colored: bool) -> void:
	var target: float = 0.0 if colored else 1.0
	for rect in [card.portrait_rect, card.badge_rect]:
		var tween = create_tween()
		tween.tween_property(rect.material, "shader_parameter/gray_amount", target, 0.2)

# --- Défilement (swipe + flèches) ---

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_dragging = true
			_drag_start_x = event.position.x
			_scroll_start = cards_scroll.scroll_horizontal
		else:
			_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		var delta = event.position.x - _drag_start_x
		cards_scroll.scroll_horizontal = _scroll_start - int(delta)

func _on_arrow_gui_input(event: InputEvent, is_left: bool) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_scroll_by(-PAGE_STEP if is_left else PAGE_STEP)

func _scroll_by(delta: float) -> void:
	var max_scroll := maxi(0, int(cards_row.get_combined_minimum_size().x - cards_scroll.size.x))
	var target := clampi(cards_scroll.scroll_horizontal + int(delta), 0, max_scroll)
	var tween := create_tween()
	tween.tween_property(cards_scroll, "scroll_horizontal", target, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
