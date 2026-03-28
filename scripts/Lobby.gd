extends Control

# Assign these in the inspector after creating the scene
@export var host_button: Button
@export var join_button: Button
@export var ip_input: LineEdit
@export var status_label: Label
@export var paste_button: Button
@export var back_button: Button
var start_game_timer: Timer

# Port par défaut (doit correspondre à celui dans NetworkManager)
const DEFAULT_PORT = 443
const DEFAULT_IP = "kotapero.xyz"

@onready var share_container: VBoxContainer = %ShareContainer
@onready var qr_http_request: HTTPRequest = %HTTPRequest
@onready var qr_texture_rect: TextureRect = %QRCodeRect
@onready var copy_link_button: Button = %CopyLinkButton
@onready var whatsapp_button: Button = %WhatsAppButton
@onready var sms_button: Button = %SMSButton
@onready var discord_button: Button = %DiscordButton

var current_invite_link: String = ""
# Hébergement direct sur le VPS pour un contrôle total (Instant Play).
const INVITE_BASE_URL = "https://kotapero.xyz/"

const UI_SOUND_COMPONENT_SCENE = preload("res://scenes/Components/UISoundComponent.tscn")
const CHALK_TIC_SOUND = preload("res://assets/Sounds/UI/chalk_tic.wav")

var ui_sound: UISoundComponent

func _ready() -> void:
	ui_sound = UI_SOUND_COMPONENT_SCENE.instantiate()
	add_child(ui_sound)

	# Timer to check for game start conditions periodically
	# Init at the top to ensure it's ready before any signal callback
	start_game_timer = Timer.new()
	start_game_timer.wait_time = 1.0
	start_game_timer.timeout.connect(_check_start_game)
	add_child(start_game_timer)

	if host_button: host_button.pressed.connect(_on_host_pressed)
	if join_button: join_button.pressed.connect(_on_join_pressed)
	if paste_button: paste_button.pressed.connect(_on_paste_pressed)
	if back_button: back_button.pressed.connect(_on_back_pressed)

	# UI Setup for Host/Join
	if host_button: host_button.text = tr("LOBBY_CREATE_MATCH")
	if join_button: join_button.text = tr("LOBBY_JOIN_MATCH")
	if back_button: back_button.text = tr("BTN_BACK")

	# Désactiver le bouton tant que Nakama n'est pas prêt
	if not NakamaManager.socket_connected:
		if join_button: join_button.disabled = true
		if status_label: status_label.text = tr("LOBBY_STATUS_CONNECTING")
		NakamaManager.nakama_ready.connect(_on_nakama_ready)

	# Placeholder for Match ID
	if ip_input:
		ip_input.placeholder_text = tr("LOBBY_PLACEHOLDER_MATCH_ID")
	if paste_button:
		paste_button.tooltip_text = tr("LOBBY_TOOLTIP_PASTE")

	# Connect to NetworkManager signals
	# Note: NetworkManager is an Autoload, so we can access it globally
	NetworkManager.connection_successful.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_fail)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.match_hosted.connect(_on_match_hosted)
	NetworkManager.game_starting.connect(_on_game_starting)
	
	# Check for auto-join parameters (URL or Command Line)
	_check_for_auto_join()
	
	# Setup Signals for Share UI
	qr_http_request.request_completed.connect(_on_qr_request_completed)
	copy_link_button.pressed.connect(_on_copy_link_pressed)
	whatsapp_button.pressed.connect(_on_whatsapp_pressed)
	sms_button.pressed.connect(_on_sms_pressed)
	discord_button.pressed.connect(_on_discord_pressed)
	
	copy_link_button.text = tr("LOBBY_BTN_COPY")
	whatsapp_button.text = tr("LOBBY_BTN_WHATSAPP")
	sms_button.text = tr("LOBBY_BTN_SMS")
	discord_button.text = tr("LOBBY_BTN_DISCORD")

	# Setup "Juicy" feedback for all buttons
	_setup_button_feedback(host_button)
	_setup_button_feedback(join_button)
	_setup_button_feedback(paste_button)
	_setup_button_feedback(back_button)
	_setup_button_feedback(copy_link_button)
	_setup_button_feedback(whatsapp_button)
	_setup_button_feedback(sms_button)
	_setup_button_feedback(discord_button)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Home.tscn")

func _on_host_pressed() -> void:
	if status_label: status_label.text = tr("LOBBY_STATUS_CREATING")
	NetworkManager.host_game()
	_disable_buttons()

func _on_join_pressed() -> void:
	if not ip_input: return

	var match_id = _clean_match_id(ip_input.text)

	if match_id.is_empty():
		if status_label: status_label.text = tr("LOBBY_STATUS_NO_MATCH_ID")
		return

	if status_label: status_label.text = tr("LOBBY_STATUS_JOINING")

	NetworkManager.is_host = false
	# On rejoint directement l'ID
	NetworkManager.join_game(match_id)
	_disable_buttons()

func _on_paste_pressed() -> void:
	if ip_input:
		var clipboard_text = DisplayServer.clipboard_get()
		ip_input.text = _clean_match_id(clipboard_text)

func _clean_match_id(text: String) -> String:
	var clean_text = text.strip_edges()
	
	# Extraction depuis une URL complète (ex: https://...?match_id=XYZ&v=1)
	if "match_id=" in clean_text:
		var parts = clean_text.split("match_id=")
		if parts.size() > 1:
			clean_text = parts[1]
	
	# Nettoyage des paramètres URL suivants (ex: &v=1)
	if "&" in clean_text:
		clean_text = clean_text.split("&")[0]
		
	return clean_text

func _on_nakama_ready() -> void:
	if join_button: join_button.disabled = false
	if status_label: status_label.text = tr("LOBBY_STATUS_READY")

func _on_connection_success() -> void:
	if status_label: status_label.text = tr("LOBBY_STATUS_CONNECTED_WAITING")
	
	# Si on est le client qui rejoint, on cache aussi l'interface de connexion
	if not NetworkManager.is_host:
		if host_button and host_button.get_parent(): host_button.get_parent().hide()
		if join_button and join_button.get_parent(): join_button.get_parent().hide()
		
		# FIX: On cache le conteneur parent (IPInputContainer) pour tout masquer proprement
		if paste_button and paste_button.get_parent(): paste_button.get_parent().hide()

	# Check immediately if we already have peers (e.g. late join or bridge already synced)
	if start_game_timer.is_inside_tree():
		start_game_timer.start() # Start polling
	_check_start_game()

func _on_match_hosted(match_id: String) -> void:
	# Le Host reçoit l'ID réel ici. On l'affiche pour qu'il puisse le partager.
	if status_label: status_label.text = tr("LOBBY_STATUS_HOSTED")
	if ip_input:
		ip_input.text = match_id
		ip_input.editable = false # On verrouille pour montrer que c'est un output
	
	# On cache les boutons Host/Join pour épurér l'interface et laisser la place au QR Code
	if host_button and host_button.get_parent(): host_button.get_parent().hide()
	if join_button and join_button.get_parent(): join_button.get_parent().hide()
	if paste_button: paste_button.hide()
	
	# Generate Invite Link
	# Retour à la méthode standard '?' maintenant que nous sommes sur notre propre serveur.
	var invite_link = INVITE_BASE_URL + "?match_id=" + match_id + "&v=1"
	
	current_invite_link = invite_link
	
	share_container.show()
	
	# Fetch QR Code from API
	if qr_http_request:
		var api_url = "https://api.qrserver.com/v1/create-qr-code/?size=350x350&data=" + invite_link.uri_encode()
		qr_http_request.request(api_url)

func _on_connection_fail() -> void:
	if status_label: status_label.text = tr("LOBBY_STATUS_FAILED")
	_enable_buttons()
	start_game_timer.stop()

func _on_player_connected(user_id: String) -> void:
	if status_label: status_label.text = tr("LOBBY_STATUS_PLAYER_CONNECTED").format({"user_id": user_id})
	_check_start_game()

func _check_start_game() -> void:
	# Logic to start the game when 2 players are ready (Self + 1 Opponent)
	var peers_count = NetworkManager.match_presences.size()
	print("DEBUG: Checking start game. Peers count: ", peers_count)
	if peers_count >= 1 and NetworkManager.is_host:
		print("Enough players! Can start game logic here.")
		start_game_timer.stop()
		NetworkManager.start_game()

func _on_game_starting() -> void:
	if back_button: back_button.hide()
	if share_container: share_container.hide()
	# On affiche un texte de chargement pendant que Godot fige l'écran pour charger la scène 3D
	if status_label: status_label.text = tr("LOBBY_STATUS_STARTING")

func _disable_buttons() -> void:
	if host_button: host_button.disabled = true
	if join_button: join_button.disabled = true

func _enable_buttons() -> void:
	if host_button: host_button.disabled = false
	if join_button: join_button.disabled = false

func _check_for_auto_join() -> void:
	var match_id = ""
	
	# 1. Web: Check URL parameters
	if OS.has_feature("web"):
		# On récupère le paramètre 'match_id' de l'URL via JavaScript
		# On cherche d'abord dans les paramètres standards (?), puis dans le hash (#)
		var js_code = """
		(function() {
			var fromQuery = new URLSearchParams(window.location.search).get('match_id');
			if (fromQuery) return fromQuery;
			
			var hash = window.location.hash;
			if (hash.includes('match_id=')) {
				return hash.split('match_id=')[1].split('&')[0];
			}
			return null;
		})()
		"""
		var result = JavaScriptBridge.eval(js_code)
		if result:
			match_id = str(result)
			# Nettoyer l'URL pour ne pas re-joindre en boucle si on revient au menu
			JavaScriptBridge.eval("window.history.replaceState({}, document.title, window.location.pathname);")
	
	# 2. Desktop/Android (Deep Link): Check Command Line Arguments
	# Sur Android (avec App Links configuré) ou Desktop, l'URL complète peut être passée en argument.
	for arg in OS.get_cmdline_args():
		# Cas A : Argument explicite (ex: ligne de commande debug)
		if arg.begins_with("--match_id="):
			match_id = arg.split("=")[1]
			break
		# Cas B : URL complète (Deep Link Android) ex: https://kotapero.xyz/?match_id=...
		elif "match_id=" in arg:
			var query_string = arg.split("?")[1] if "?" in arg else arg
			for param in query_string.split("&"):
				if param.begins_with("match_id="):
					match_id = param.split("=")[1]
					break
		
		if not match_id.is_empty():
			break
	
	if not match_id.is_empty():
		print("🚀 Auto-Join detected for Match ID: ", match_id)
		if ip_input: ip_input.text = match_id
		
		if NakamaManager.socket_connected:
			_on_join_pressed()
		else:
			if status_label: status_label.text = tr("LOBBY_STATUS_AUTOJOIN")
			NakamaManager.nakama_ready.connect(func(): _on_join_pressed(), CONNECT_ONE_SHOT)

func _on_qr_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var error = image.load_png_from_buffer(body)
		if error == OK:
			var texture = ImageTexture.create_from_image(image)
			qr_texture_rect.texture = texture
			qr_texture_rect.show()

func _on_copy_link_pressed() -> void:
	if current_invite_link:
		DisplayServer.clipboard_set(current_invite_link)
		if status_label: status_label.text = tr("LOBBY_STATUS_LINK_COPIED")

func _on_whatsapp_pressed() -> void:
	if current_invite_link:
		var msg = tr("LOBBY_SHARE_MSG") + current_invite_link
		OS.shell_open("whatsapp://send?text=" + msg.uri_encode())

func _on_sms_pressed() -> void:
	if current_invite_link:
		var msg = tr("LOBBY_SHARE_MSG") + current_invite_link
		# 'sms:?body=' est le standard le plus compatible (Android/iOS)
		OS.shell_open("sms:?body=" + msg.uri_encode())

func _on_discord_pressed() -> void:
	if current_invite_link:
		DisplayServer.clipboard_set(current_invite_link)
		if status_label: status_label.text = tr("LOBBY_STATUS_LINK_COPIED_DISCORD")
		# Discord n'a pas de scheme 'share' universel. On ouvre l'app/web sur les DMs.
		OS.shell_open("https://discord.com/channels/@me")

func _setup_button_feedback(btn: Button) -> void:
	if not btn: return
	
	# On centre le pivot pour que le scale se fasse depuis le milieu
	# On le fait au démarrage et à chaque redimensionnement
	btn.pivot_offset = btn.size / 2
	btn.resized.connect(func(): btn.pivot_offset = btn.size / 2)
	
	# Effet d'enfoncement (Squash)
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size / 2
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.1)
		if ui_sound: ui_sound.play_varied(CHALK_TIC_SOUND)
	)
	
	# Effet de relâchement avec rebond (Stretch & Bounce)
	btn.button_up.connect(func():
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.3).from(Vector2(1.05, 1.05))
	)
