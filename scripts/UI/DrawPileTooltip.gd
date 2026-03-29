extends PanelContainer

@onready var label: Label = $MarginContainer/Label

func _ready() -> void:
	# Démarrage invisible et sans échelle
	scale = Vector2.ZERO

func show_tooltip(text: String) -> void:
	label.text = text
	
	# On attend une frame pour que le label redimensionne le conteneur
	await get_tree().process_frame

	# On définit le pivot au centre du rectangle une fois sa taille finale connue
	pivot_offset = size / 2.0

	var tween = create_tween().set_parallel()
	tween.tween_property(self , "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self , "modulate:a", 1.0, 0.1).from(0.0)

func hide_tooltip() -> void:
	var tween = create_tween().set_parallel()
	tween.tween_property(self , "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self , "modulate:a", 0.0, 0.2)
	tween.finished.connect(queue_free)