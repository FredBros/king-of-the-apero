class_name ComboBadge
extends Node2D

## Badge combo (panel + étoiles teintées) affiché en surimpression sur une
## carte jouable, ou en ligne dans la description d'un personnage
## (CharacterSelect / tooltip in-game).
##
## Rendu 100% procédural (Image basse résolution + scale entier, sans
## antialiasing) pour rester cohérent avec le reste du pixel art du jeu :
## aucune balise vectorielle (StyleBox) n'est utilisée.

const STAR_TEXTURE := preload("res://assets/UI/Icons/combo_star.png")
const COUNT_FONT := preload("res://assets/fonts/04B_03__.TTF")

const MOVE_COLOR := Color("#202020")
const PANEL_BG_COLOR := Color("#fdfdfd")

const PIXEL_SCALE := 3.0   # 1 pixel source = 3 pixels écran (facteur entier, pas d'antialiasing)
const STAR_GAP_SRC := 2.0  # espace entre étoiles, en pixels source
const BORDER_SRC := 3.0    # épaisseur du contour du panel, en pixels source
const PADDING_SRC := 1.0   # marge interne entre le contour et les étoiles, en pixels source
const MAX_STARS_SHOWN := 3 # au-delà, on affiche une étoile + le chiffre ("★4")

var is_on_card: bool = true
var star_color: Color = MOVE_COLOR

var _panel_sprite: Sprite2D
var _star_sprites: Array[Sprite2D] = []
var _count_label: Label
var _current_position: int = -1

func _ready() -> void:
	_panel_sprite = Sprite2D.new()
	_panel_sprite.centered = false
	_panel_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_panel_sprite)

	_count_label = Label.new()
	_count_label.add_theme_font_override("font", COUNT_FONT)
	_count_label.add_theme_font_size_override("font_size", 24)
	_count_label.visible = false
	add_child(_count_label)

	visible = false

## star_color : couleur des étoiles ET du contour du panel (noir pour les cartes
##              mouvement, wrestler.color pour les cartes attaque).
## combo_position : position dans le combo (0 = init, pas de badge). 1-3 étoiles ;
##                   au-delà, une étoile + le chiffre.
## p_is_on_card : true = badge sur une carte (pop/depop animé, masqué à 0) ;
##                false = ligne de description (toujours visible, y compris à 0).
func setup(p_star_color: Color, combo_position: int, p_is_on_card: bool = true) -> void:
	is_on_card = p_is_on_card
	star_color = p_star_color
	_build_content(maxi(combo_position, 0))

	if is_on_card:
		_apply_card_visibility(combo_position)
	else:
		_current_position = combo_position
		scale = Vector2.ONE
		show()

func _build_content(combo_position: int) -> void:
	var use_count_label = combo_position > MAX_STARS_SHOWN
	var star_count = 1 if use_count_label else combo_position

	while _star_sprites.size() < star_count:
		var star = Sprite2D.new()
		star.texture = STAR_TEXTURE
		star.centered = false
		star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		star.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
		add_child(star)
		_star_sprites.append(star)
	for i in range(_star_sprites.size()):
		_star_sprites[i].visible = i < star_count
		_star_sprites[i].modulate = star_color

	_count_label.visible = use_count_label
	if use_count_label:
		_count_label.text = str(combo_position)
		_count_label.add_theme_color_override("font_color", star_color)
		_count_label.reset_size()

	_layout(star_count, use_count_label)

func _layout(star_count: int, use_count_label: bool) -> void:
	var star_size_src = STAR_TEXTURE.get_width()
	var inset_src = BORDER_SRC + PADDING_SRC

	# Largeur du contenu (étoiles + éventuel label), en pixels écran.
	var stars_width = star_count * star_size_src * PIXEL_SCALE + maxi(star_count - 1, 0) * STAR_GAP_SRC * PIXEL_SCALE
	var label_width = 0.0
	if use_count_label:
		label_width = STAR_GAP_SRC * PIXEL_SCALE + _count_label.size.x
	var content_width = stars_width + label_width

	var star_h_screen = star_size_src * PIXEL_SCALE
	var panel_height_src = star_size_src + 2.0 * inset_src
	var panel_height_screen = panel_height_src * PIXEL_SCALE
	var panel_width_screen = content_width + 2.0 * inset_src * PIXEL_SCALE
	# On garde une largeur de panel multiple du pixel source pour un contour toujours net.
	var panel_width_src = ceilf(panel_width_screen / PIXEL_SCALE)
	panel_width_screen = panel_width_src * PIXEL_SCALE

	# Origine du nœud = bas-centre du panel (voir CardUI.tscn pour le placement à cheval sur la carte).
	var content_start_x = -content_width / 2.0
	var content_top_y = -panel_height_screen + inset_src * PIXEL_SCALE

	var x = content_start_x
	for i in range(star_count):
		_star_sprites[i].position = Vector2(x, content_top_y)
		x += star_h_screen + STAR_GAP_SRC * PIXEL_SCALE

	if use_count_label:
		# x pointe déjà juste après la dernière étoile + un gap (dernière itération de la boucle).
		_count_label.position = Vector2(x, content_top_y + (star_h_screen - _count_label.size.y) / 2.0)

	_rebuild_panel_texture(int(panel_width_src), int(panel_height_src))
	_panel_sprite.scale = Vector2(PIXEL_SCALE, PIXEL_SCALE)
	_panel_sprite.position = Vector2(-panel_width_screen / 2.0, -panel_height_screen)

func _rebuild_panel_texture(width_src: int, height_src: int) -> void:
	width_src = maxi(width_src, 1)
	height_src = maxi(height_src, 1)
	var img = Image.create(width_src, height_src, false, Image.FORMAT_RGBA8)
	img.fill(star_color)
	var border = int(BORDER_SRC)
	if width_src > 2 * border and height_src > 2 * border:
		img.fill_rect(Rect2i(border, border, width_src - 2 * border, height_src - 2 * border), PANEL_BG_COLOR)
	_panel_sprite.texture = ImageTexture.create_from_image(img)

## Pop-in quand le badge apparaît/disparaît sur une carte ; petit bump si le
## nombre d'étoiles change alors que le badge est déjà affiché.
func _apply_card_visibility(combo_position: int) -> void:
	var should_show = combo_position > 0
	var position_changed = combo_position != _current_position
	_current_position = combo_position

	if should_show == visible:
		if should_show and position_changed:
			_bump()
		return

	if should_show:
		show()
		scale = Vector2.ZERO
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(hide)

func _bump() -> void:
	scale = Vector2.ONE
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
