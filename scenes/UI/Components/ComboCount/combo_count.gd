extends Node2D

var _combo_label: Label
var _number_label: Label
var _tween: Tween

const COLORS = [
	Color(1.0, 1.0, 1.0),        # position 1 (caché)
	Color(1.0, 0.92, 0.23),       # position 2 — jaune
	Color(1.0, 0.55, 0.1),        # position 3 — orange
	Color(1.0, 0.22, 0.22),       # position 4 — rouge
]

func _ready() -> void:
	_combo_label = Label.new()
	_combo_label.text = "COMBO"
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 18)
	_combo_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.85))
	_combo_label.add_theme_constant_override("shadow_offset_x", 1)
	_combo_label.add_theme_constant_override("shadow_offset_y", 1)
	_combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_combo_label.position = Vector2(-50, -60)
	_combo_label.size = Vector2(100, 28)
	add_child(_combo_label)

	_number_label = Label.new()
	_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number_label.add_theme_font_size_override("font_size", 64)
	_number_label.add_theme_constant_override("shadow_offset_x", 3)
	_number_label.add_theme_constant_override("shadow_offset_y", 3)
	_number_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_number_label.position = Vector2(-60, -30)
	_number_label.size = Vector2(120, 80)
	add_child(_number_label)

	visible = false

	var gm = get_tree().root.find_child("GameManager", true, false)
	if gm and gm.has_signal("combo_changed"):
		gm.combo_changed.connect(set_combo)
	if gm and gm.has_signal("turn_started"):
		gm.turn_started.connect(func(_name): _hide_immediately())

func set_combo(combo_pos: int) -> void:
	if combo_pos <= 1:
		_hide_animated()
		return

	var color = COLORS[mini(combo_pos, COLORS.size() - 1)]
	_number_label.text = "x" + str(combo_pos)
	_number_label.add_theme_color_override("font_color", color)
	_combo_label.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.4))

	if not visible:
		visible = true
		scale = Vector2.ZERO
		modulate.a = 0.0

	_play_punch()

func _play_punch() -> void:
	if _tween and _tween.is_running():
		_tween.kill()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.0)
	_tween.tween_property(self, "rotation", deg_to_rad(-10.0), 0.0)
	_tween.tween_property(self, "modulate:a", 1.0, 0.08)
	var bounce = _tween.tween_property(self, "scale", Vector2.ONE, 0.3)
	bounce.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.0)
	var settle = _tween.tween_property(self, "rotation", 0.0, 0.3)
	settle.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _hide_immediately() -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	visible = false

func _hide_animated() -> void:
	if not visible:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.15)
	_tween.tween_callback(func(): visible = false)
