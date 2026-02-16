@tool
extends Control

@export var border_color: Color = Color.WHITE
@export var border_width: float = 2.0

@export_group("Dynamic Inset")
@export var min_inset: float = 3.0
@export var max_inset: float = 20.0
@export var inset_ratio: float = 0.05 # 5% de la plus petite dimension

func _ready() -> void:
	# Le cadre est purement visuel, il ne doit pas bloquer les clics
	mouse_filter = MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	# Si le parent est un PanelContainer avec du padding, ce node (BorderLayer) est à l'intérieur.
	# On veut dessiner la bordure autour du PARENT complet.
	var rect = Rect2(Vector2.ZERO, size)
	var p = get_parent()
	if p is PanelContainer:
		# On dessine depuis l'origine du parent (-position) avec la taille du parent
		rect = Rect2(-position, p.size)

	var w = rect.size.x
	var h = rect.size.y
	var origin = rect.position
	
	# Calcul de l'inset dynamique proportionnel à la taille
	var smallest_side = min(w, h)
	var current_inset = clamp(smallest_side * inset_ratio, min_inset, max_inset)
	
	# Style "Coins Croisés" (Crossed Corners)
	# Les lignes sont décalées vers l'intérieur (current_inset) mais font toute la longueur/hauteur
	
	# Haut & Bas
	draw_line(origin + Vector2(0, current_inset), origin + Vector2(w, current_inset), border_color, border_width)
	draw_line(origin + Vector2(0, h - current_inset), origin + Vector2(w, h - current_inset), border_color, border_width)
	# Gauche & Droite
	draw_line(origin + Vector2(current_inset, 0), origin + Vector2(current_inset, h), border_color, border_width)
	draw_line(origin + Vector2(w - current_inset, 0), origin + Vector2(w - current_inset, h), border_color, border_width)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()