@tool
class_name ChalkPanel
extends PanelContainer

@export var background_color: Color = Color("#181425")
@export var padding: int = 10

func _ready() -> void:
	# On supprime le stylebox par défaut pour laisser _draw gérer le fond
	# Cela évite d'avoir un fond gris par défaut de Godot
	var style = StyleBoxEmpty.new()
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	add_theme_stylebox_override("panel", style)
	
	queue_redraw()

func _draw() -> void:
	# Dessin du fond uni (Sans Shader)
	draw_rect(Rect2(Vector2.ZERO, size), background_color, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()