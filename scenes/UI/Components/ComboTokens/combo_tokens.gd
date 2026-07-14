extends Control

signal token_applied(card_ui: CardUI, is_plus: bool)

# res://assets/UI/Combo-token.png : 5 frames de 10x10 sur une ligne.
# 1: face +1 - 2: face -1 - 3,4,5: frames de rotation (3/4 côté +1, tranche, 3/4 côté -1).
const SPRITESHEET = preload("res://assets/UI/Combo-token.png")
const FRAME_SIZE := 10.0
const TOKEN_SCALE := 10.0 # Le pixel art 10x10 est agrandi pour rester lisible dans l'UI

const FRAME_PLUS := 0
const FRAME_MINUS := 1
const FRAMES_PLUS_TO_MINUS := [2, 3, 4]
const FRAMES_MINUS_TO_PLUS := [4, 3, 2]
const FLIP_FRAME_DURATION := 0.05

const STACK_OFFSET_Y: float = 1.0 * TOKEN_SCALE # 1px du sprite source par jeton empilé
const FRAME_HALF: Vector2 = Vector2(FRAME_SIZE, FRAME_SIZE) * TOKEN_SCALE / 2.0
const DRAG_THRESHOLD: float = 10.0

var _tokens: Array[Sprite2D] = []
var _hand_container: HBoxContainer
var is_plus: bool = true
var _is_flipping: bool = false

# Drag state
var _is_pressing: bool = false
var _press_start: Vector2
var _is_dragging: bool = false
var _drag_sprite: Sprite2D = null
var _hovered_card: CardUI = null
var _drag_apply_plus: bool = true
var _can_switch_on_card: bool = false
var _wrestler_data: WrestlerData = null
var _is_drag_flipping: bool = false
var _drag_flip_has_pending: bool = false
var _drag_flip_pending_target: bool = false

func _get_frame(index: int) -> AtlasTexture:
	var atlas = AtlasTexture.new()
	atlas.atlas = SPRITESHEET
	atlas.region = Rect2(index * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	return atlas

func _make_token_sprite(frame_index: int) -> Sprite2D:
	var sprite = Sprite2D.new()
	sprite.texture = _get_frame(frame_index)
	sprite.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
	return sprite

func setup(count: int, hand_container: HBoxContainer, wrestler_data: WrestlerData) -> void:
	_hand_container = hand_container
	_wrestler_data = wrestler_data
	for t in _tokens:
		t.queue_free()
	_tokens.clear()
	is_plus = true
	_is_flipping = false

	for i in range(count):
		var sprite = _make_token_sprite(FRAME_PLUS)
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
	_is_drag_flipping = false
	_drag_flip_has_pending = false

	_drag_sprite = _make_token_sprite(FRAME_PLUS if _drag_apply_plus else FRAME_MINUS)
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
				_request_drag_flip(new_plus)

func _end_drag(pos: Vector2) -> void:
	_is_dragging = false

	var token_consumed = false
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
			token_consumed = true

	_set_hovered_card(null)

	if token_consumed:
		if _drag_sprite:
			_drag_sprite.queue_free()
			_drag_sprite = null
	else:
		# Lâché hors d'une carte (ou carte refusée, ex: tier déjà au max/min) : le jeton
		# revient visuellement se poser en haut de la pile plutôt que de juste disparaître.
		_return_drag_sprite_to_stack()

func _return_drag_sprite_to_stack() -> void:
	if not _drag_sprite:
		return
	var sprite = _drag_sprite
	_drag_sprite = null

	if _tokens.is_empty():
		sprite.queue_free()
		return

	var target = _tokens.back()
	var tween = create_tween()
	tween.tween_property(sprite, "global_position", target.global_position, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		target.modulate.a = 1.0
		sprite.queue_free()
	)

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

# Joue la séquence de rotation sur n'importe quel sprite de jeton (pile ou fantôme de drag).
func _play_flip_frames(sprite: Sprite2D, to_plus: bool) -> void:
	var rotation_frames = FRAMES_MINUS_TO_PLUS if to_plus else FRAMES_PLUS_TO_MINUS
	var final_frame = FRAME_PLUS if to_plus else FRAME_MINUS

	for frame_index in rotation_frames:
		if not is_instance_valid(sprite): return
		sprite.texture = _get_frame(frame_index)
		await get_tree().create_timer(FLIP_FRAME_DURATION).timeout

	if is_instance_valid(sprite):
		sprite.texture = _get_frame(final_frame)

func _flip_top_token() -> void:
	_is_flipping = true
	var top = _tokens.back()
	var going_to_plus = not is_plus
	is_plus = going_to_plus
	await _play_flip_frames(top, going_to_plus)
	_is_flipping = false

# Même animation que _flip_top_token, mais pour le jeton en train d'être dragué quand on
# passe du haut au bas d'une carte (et inversement). Les demandes qui arrivent pendant qu'une
# rotation est déjà en cours sont mises en attente plutôt que perdues (l'utilisateur peut
# survoler rapidement les deux zones avant que l'animation précédente soit terminée).
func _request_drag_flip(to_plus: bool) -> void:
	if _is_drag_flipping:
		_drag_flip_has_pending = true
		_drag_flip_pending_target = to_plus
		return
	if not _drag_sprite: return

	_is_drag_flipping = true
	await _play_flip_frames(_drag_sprite, to_plus)
	_is_drag_flipping = false

	if _drag_flip_has_pending:
		_drag_flip_has_pending = false
		_request_drag_flip(_drag_flip_pending_target)
