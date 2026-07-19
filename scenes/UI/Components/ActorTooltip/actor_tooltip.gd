class_name ActorTooltip
extends PanelContainer

## Panneau de présentation d'un personnage (portrait, nom, intro, listes de
## combo, passif/ulti/points forts/faibles). Utilisé dans CharacterSelect et
## réutilisable tel quel pour un futur tooltip in-game (clic sur portrait).

const COMBO_BADGE_SCENE := preload("res://scenes/Components/ComboBadge.tscn")

# Icônes de section (blanches à la source, teintées en noir pour l'instant).
const ICON_TINT := Color("#202020")
const PASSIVE_ICON := preload("res://assets/UI/Icons/passif_icon.tres")
const ULTI_ICON := preload("res://assets/UI/Icons/ulti_icon.tres")
const STRENGTHS_ICON := preload("res://assets/UI/Icons/strengths_icon.tres")
const WEAKNESSES_ICON := preload("res://assets/UI/Icons/weaknesses_icon.tres")
const ICON_SCALE_DESC := 3.0 # icônes sources 12x12 -> 36x36 écran (facteur entier, net)

# Position "init" (0 étoile) des listes de combo : icône de base à la place du panel vide.
const FIST_ICON := preload("res://assets/UI/Icons/fist_icon.tres")  # attaque, teint wrestler.color
const BOOT_ICON := preload("res://assets/UI/Icons/boot_icon.tres")  # mouvement, jamais teintée

const COMBO_BADGE_HOLDER_SIZE := Vector2(90, 44)

@onready var info_sprite: TextureRect = %InfoSprite
@onready var info_name: Label = %InfoName
@onready var description_box: VBoxContainer = %DescriptionBox

## data == null : vide le panneau (rien de sélectionné/survolé).
func display(data: WrestlerData) -> void:
	_clear_description_box()
	if not data:
		info_sprite.texture = null
		info_name.text = ""
		return
	info_sprite.texture = data.sprite
	info_name.text = data.display_name

	if not data.intro_key.is_empty():
		description_box.add_child(_make_text_row(tr(data.intro_key)))

	_add_combo_section(data.combo_attack_keys, data.color, true)
	_add_combo_section(data.combo_move_keys, ComboBadge.MOVE_COLOR, false)

	_add_icon_row(PASSIVE_ICON, data.passive_key)
	_add_icon_row(ULTI_ICON, data.ulti_key)
	_add_icon_row(STRENGTHS_ICON, data.strengths_key)
	_add_icon_row(WEAKNESSES_ICON, data.weaknesses_key)

func _clear_description_box() -> void:
	for child in description_box.get_children():
		child.queue_free()

func _make_text_row(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label

## Une ligne par position de combo (index = nombre d'étoiles, 0 = init).
## Position 0 : pas de panel vide, on affiche l'icône poing (attaque, teintée
## wrestler.color) ou botte (mouvement, jamais teintée) à la place.
func _add_combo_section(keys: Array, star_color: Color, is_attack: bool) -> void:
	for i in range(keys.size()):
		var key: String = keys[i]
		if key.is_empty():
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var badge_holder := Control.new()
		badge_holder.custom_minimum_size = COMBO_BADGE_HOLDER_SIZE

		var badge: ComboBadge = null
		if i == 0:
			var base_icon := FIST_ICON if is_attack else BOOT_ICON
			var icon_rect := TextureRect.new()
			icon_rect.texture = base_icon
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var icon_size = Vector2(base_icon.get_width(), base_icon.get_height()) * ICON_SCALE_DESC
			icon_rect.custom_minimum_size = icon_size
			icon_rect.position = (COMBO_BADGE_HOLDER_SIZE - icon_size) / 2.0
			if is_attack:
				icon_rect.modulate = star_color
			# La botte reste blanche/contour noir, jamais teintée (demande explicite).
			badge_holder.add_child(icon_rect)
		else:
			badge = COMBO_BADGE_SCENE.instantiate()
			badge_holder.add_child(badge)
			badge.position = Vector2(COMBO_BADGE_HOLDER_SIZE.x / 2.0, COMBO_BADGE_HOLDER_SIZE.y)
		row.add_child(badge_holder)

		var label := _make_text_row(tr(key))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		description_box.add_child(row)
		# setup() après add_child : _ready() (qui construit panel/label internes) doit avoir tourné.
		if badge:
			badge.setup(star_color, i, false)

func _add_icon_row(icon: Texture2D, key: String) -> void:
	if key.is_empty():
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.custom_minimum_size = Vector2(icon.get_width(), icon.get_height()) * ICON_SCALE_DESC
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_rect.modulate = ICON_TINT
	row.add_child(icon_rect)

	var label := _make_text_row(tr(key))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	description_box.add_child(row)
