extends Control

signal token_applied(card_ui: CardUI, is_plus: bool)

const STACK_OFFSET_Y: float = 14.0
const FRAME_HALF: Vector2 = Vector2(60.0, 60.0)
const FLIP_HALF_DURATION: float = 0.1
const DRAG_THRESHOLD: float = 10.0

# Frames dans l'animation "default" :
# 0 = face A  1 = 3/4 face A  2 = tranche  3 = 3/4 face B  4 = face B
const FRAME_PLUS:  int = 1
const FRAME_MINUS: int = 3

@onready var _template: AnimatedSprite2D = $AnimatedSprite2D

var _tokens: Array[AnimatedSprite2D] = []
var _hand_container: HBoxContainer
var is_plus: bool = true
var _is_flipping: bool = false

# Drag state
var _is_pressing: bool = false
var _press_start: Vector2
var _is_dragging: bool = false
var _drag_sprite: AnimatedSprite2D = null
var _hovered_card: CardUI = null
var _drag_apply_plus: bool = true
var _can_switch_on_card: bool = false
var _wrestler_data: WrestlerData = null

func _ready() -> void:
	_template.visible = false

func setup(count: int, hand_container: HBoxContainer, wrestler_data: WrestlerData) -> void:
	_hand_container = hand_container
	_wrestler_data = wrestler_data
	for t in _tokens:
		t.queue_free()
	_tokens.clear()
	is_plus = true
	_is_flipping = false

	for i in range(count):
		var sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = _template.sprite_frames
		sprite.animation = "default"
		sprite.frame = FRAME_PLUS
		sprite.position = Vector2(0.0, -i * STACK_OFFSET_Y)
		add_child(sprite)
		_tokens.append(sprite)

func _input(event: InputEvent) -> void:
	if _tokens.is_empty(): return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit = false
			for token in _tokens:
				if Rect2(token.global_position - FRAME_HALF, FRAME_HALF * 2.0).has_point(event.position):
					hit = true
					break
			if hit:
				_is_pressing = true
				_press_start = event.position
				get_viewport().set_input_as_handled()
		else:
			if _is_dragging:
				_end_drag(event.position)
				get_viewport().set_input_as_handled()
			elif _is_pressing and not _is_flipping:
				_flip_top_token()
				get_viewport().set_input_as_handled()
			_is_pressing = false

	elif event is InputEventMouseMotion and _is_pressing:
		var offset = event.position - _press_start
		if not _is_dragging and offset.length() > DRAG_THRESHOLD:
			_start_drag(event.position)
		if _is_dragging:
			_update_drag(event.position)
		get_viewport().set_input_as_handled()

# --- Drag ---

func _start_drag(pos: Vector2) -> void:
	_is_dragging = true
	_drag_apply_plus = is_plus

	_drag_sprite = AnimatedSprite2D.new()
	_drag_sprite.sprite_frames = _template.sprite_frames
	_drag_sprite.animation = "default"
	_drag_sprite.frame = FRAME_PLUS if _drag_apply_plus else FRAME_MINUS
	_drag_sprite.top_level = true
	_drag_sprite.global_position = pos
	_drag_sprite.z_index = 100
	add_child(_drag_sprite)

	if not _tokens.is_empty():
		_tokens.back().modulate.a = 0.4

func _update_drag(pos: Vector2) -> void:
	if _drag_sprite:
		_drag_sprite.global_position = pos

	var card_under = _get_card_under_pos(pos)
	if card_under != _hovered_card:
		_set_hovered_card(card_under)
		_can_switch_on_card = false  # reset au changement de carte

	if _hovered_card:
		var rect = _hovered_card.get_global_rect()
		var rel_y = (pos.y - rect.position.y) / rect.size.y

		# La zone du milieu (1/3 central) déverrouille le switching
		if rel_y >= 0.33 and rel_y <= 0.67:
			_can_switch_on_card = true

		if _can_switch_on_card:
			var new_plus: bool
			if rel_y < 0.33:
				new_plus = true
			elif rel_y > 0.67:
				new_plus = false
			else:
				new_plus = _drag_apply_plus  # zone mid : on garde la valeur courante

			if new_plus != _drag_apply_plus:
				_drag_apply_plus = new_plus
				if _drag_sprite:
					_drag_sprite.frame = FRAME_PLUS if _drag_apply_plus else FRAME_MINUS

func _end_drag(pos: Vector2) -> void:
	_is_dragging = false

	var card_under = _get_card_under_pos(pos)
	if card_under:
		var delta = 1 if _drag_apply_plus else -1
		var min_tier = 0 if (_wrestler_data and _wrestler_data.allow_tier_zero) else 1
		var max_tier = 5 if (_wrestler_data and _wrestler_data.allow_tier_five) else 4
		var new_tier = clampi(card_under.card_data.tier + delta, min_tier, max_tier)
		if new_tier != card_under.card_data.tier:
			card_under.card_data.tier = new_tier
			card_under.update_visuals()
			print("token %+d appliqué — %s passe au tier %d" % [delta, card_under.card_data.title, new_tier])
			token_applied.emit(card_under, _drag_apply_plus)
			_consume_top_token()
	elif not _tokens.is_empty():
		_tokens.back().modulate.a = 1.0

	_set_hovered_card(null)

	if _drag_sprite:
		_drag_sprite.queue_free()
		_drag_sprite = null

func _consume_top_token() -> void:
	if _tokens.is_empty(): return
	var top = _tokens.pop_back()
	var tween = create_tween()
	tween.tween_property(top, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(top.queue_free)
	if not _tokens.is_empty():
		_tokens.back().modulate.a = 1.0

# --- Utilitaires ---

func _get_card_under_pos(pos: Vector2) -> CardUI:
	if not _hand_container: return null
	for wrapper in _hand_container.get_children():
		var child = wrapper.get_child(0) if wrapper.get_child_count() > 0 else null
		if child is CardUI and not child.is_destroying:
			if child.get_global_rect().has_point(pos):
				return child
	return null

func _set_hovered_card(card_ui: CardUI) -> void:
	if _hovered_card and is_instance_valid(_hovered_card):
		var prev_wrapper = _hovered_card.get_parent()
		if is_instance_valid(prev_wrapper):
			prev_wrapper.scale = Vector2.ONE
			prev_wrapper.pivot_offset = Vector2.ZERO

	_hovered_card = card_ui

	if _hovered_card:
		var wrapper = _hovered_card.get_parent()
		if is_instance_valid(wrapper):
			wrapper.pivot_offset = wrapper.size / 2.0
			wrapper.scale = Vector2(1.1, 1.1)
		Input.vibrate_handheld(50)

# --- Flip ---

func _flip_top_token() -> void:
	_is_flipping = true
	is_plus = not is_plus
	var top = _tokens.back()
	var target_frame := FRAME_PLUS if is_plus else FRAME_MINUS

	var tween = create_tween()
	tween.tween_property(top, "scale:y", 0.0, FLIP_HALF_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		top.frame = target_frame
		var t2 = create_tween()
		t2.tween_property(top, "scale:y", 1.0, FLIP_HALF_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t2.tween_callback(func(): _is_flipping = false)
	)
