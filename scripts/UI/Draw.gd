extends Control

const ROTATION_MARGIN = 5 # px, pour éviter que les cartes tournées ne débordent du conteneur
const CARD_BACK_TEXTURE = preload("res://assets/Cards/card_back.png")
const CARD_SIZE = Vector2(120, 120) # Taille augmentée pour plus de visibilité
const TOOLTIP_SCENE = preload("res://scenes/UI/DrawPileTooltip.tscn")

var current_card_count: int = 0
var tooltip_instance: Control = null

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_show_tooltip()
		else:
			_hide_tooltip()

func _on_mouse_entered() -> void:
	_show_tooltip()

func _on_mouse_exited() -> void:
	_hide_tooltip()

func _show_tooltip() -> void:
	if tooltip_instance and is_instance_valid(tooltip_instance):
		return # Déjà affichée

	if current_card_count <= 0:
		return # Ne rien afficher si la pioche est vide

	tooltip_instance = TOOLTIP_SCENE.instantiate()
	add_child(tooltip_instance)

	# Positionner à droite de la pioche avec une petite marge
	tooltip_instance.position.x = size.x + 10
	
	var text = tr("TOOLTIP_CARDS_LEFT") % current_card_count
	tooltip_instance.show_tooltip(text)

func _hide_tooltip() -> void:
	if tooltip_instance and is_instance_valid(tooltip_instance):
		tooltip_instance.hide_tooltip()
		tooltip_instance = null # On efface la référence

func update_deck_visuals(card_count: int) -> void:
	current_card_count = card_count
	
	# Nettoyer l'affichage précédent
	for child in get_children():
		child.queue_free()
		
	if card_count <= 0:
		return
		
	var available_height = size.y - CARD_SIZE.y - (ROTATION_MARGIN * 2)
	var spacing = 0.0
	
	if card_count > 1:
		# L'espacement grandit quand le nombre de cartes diminue,
		# remplissant ainsi toujours l'espace vertical disponible.
		spacing = available_height / float(card_count - 1)

	# Créer les cartes de bas (index 0) en haut (card_count - 1)
	for i in range(card_count):
		var card_rect = TextureRect.new()
		card_rect.texture = CARD_BACK_TEXTURE
		card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_rect.size = CARD_SIZE
		
		# Centrer horizontalement avec un léger chaos
		var x_pos = (size.x - CARD_SIZE.x) / 2.0 + randf_range(-4.0, 4.0)
		
		# Positionnement vertical (la 1ère carte est tout en bas)
		var y_pos = ROTATION_MARGIN + available_height - (i * spacing)
		
		card_rect.position = Vector2(x_pos, y_pos)
		
		# Rotation organique
		card_rect.pivot_offset = CARD_SIZE / 2.0
		card_rect.rotation_degrees = randf_range(-5.0, 5.0)
		
		add_child(card_rect)
