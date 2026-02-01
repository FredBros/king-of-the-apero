extends Control

# Assign these in the inspector after creating the scene
@export var host_button: Button
@export var join_button: Button
@export var ip_input: LineEdit
@export var status_label: Label
var start_game_timer: Timer

# Port par défaut (doit correspondre à celui dans NetworkManager)
const DEFAULT_PORT = 7000
const DEFAULT_IP = "127.0.0.1"

var qr_http_request: HTTPRequest
var qr_texture_rect: TextureRect
var copy_link_button: Button
var whatsapp_button: Button
var sms_button: Button
var discord_button: Button
var current_invite_link: String = ""
const INVITE_BASE_URL = "https://kotapero.xyz/"

func _ready() -> void:
	# Timer to check for game start conditions periodically
	# Init at the top to ensure it's ready before any signal callback
	start_game_timer = Timer.new()
	start_game_timer.wait_time = 1.0
	start_game_timer.timeout.connect(_check_start_game)
	add_child(start_game_timer)

	if host_button: host_button.pressed.connect(_on_host_pressed)
	if join_button: join_button.pressed.connect(_on_join_pressed)
	
	# UI Setup for Host/Join
	if host_button: host_button.text = "CREATE MATCH"
	if join_button: join_button.text = "JOIN MATCH"
	
	# Désactiver le bouton tant que Nakama n'est pas prêt
	if NakamaManager.socket == null:
		if join_button: join_button.disabled = true
		if status_label: status_label.text = "Connecting to Online Services..."
		NakamaManager.nakama_ready.connect(_on_nakama_ready)
	
	# Placeholder for Match ID
	if ip_input:
		ip_input.placeholder_text = "Enter Match ID here..."
	
	# Connect to NetworkManager signals
	# Note: NetworkManager is an Autoload, so we can access it globally
	NetworkManager.connection_successful.connect(_on_connection_success)
	NetworkManager.connection_failed.connect(_on_connection_fail)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.match_hosted.connect(_on_match_hosted)
	
	# Check for auto-join parameters (URL or Command Line)
	_check_for_auto_join()
	
	# Setup QR Code & Copy Link UI
	qr_http_request = HTTPRequest.new()
	add_child(qr_http_request)
	qr_http_request.request_completed.connect(_on_qr_request_completed)
	
	qr_texture_rect = TextureRect.new()
	qr_texture_rect.custom_minimum_size = Vector2(300, 300) # Plus grand pour être lisible de loin
	qr_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER # Centre le QR code horizontalement
	qr_texture_rect.hide()
	
	# Container pour les boutons de partage
	# Utilisation de HFlowContainer pour que les boutons passent à la ligne si l'écran est étroit
	var buttons_container = HFlowContainer.new()
	buttons_container.alignment = FlowContainer.ALIGNMENT_CENTER
	buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons_container.add_theme_constant_override("h_separation", 20)
	buttons_container.add_theme_constant_override("v_separation", 10)
	
	copy_link_button = Button.new()
	copy_link_button.text = "COPY"
	copy_link_button.hide()
	copy_link_button.pressed.connect(_on_copy_link_pressed)
	buttons_container.add_child(copy_link_button)
	
	whatsapp_button = Button.new()
	whatsapp_button.text = "WHATSAPP"
	whatsapp_button.hide()
	whatsapp_button.pressed.connect(_on_whatsapp_pressed)
	buttons_container.add_child(whatsapp_button)
	
	sms_button = Button.new()
	sms_button.text = "SMS"
	sms_button.hide()
	sms_button.pressed.connect(_on_sms_pressed)
	buttons_container.add_child(sms_button)
	
	discord_button = Button.new()
	discord_button.text = "DISCORD"
	discord_button.hide()
	discord_button.pressed.connect(_on_discord_pressed)
	buttons_container.add_child(discord_button)
	
	# Add UI elements to the layout (below ip_input if possible)
	if ip_input and ip_input.get_parent():
		ip_input.get_parent().add_child(qr_texture_rect)
		ip_input.get_parent().add_child(buttons_container)
	else:
		add_child(qr_texture_rect)
		add_child(buttons_container)
		qr_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		buttons_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)

func _on_host_pressed() -> void:
	if status_label: status_label.text = "Creating Match..."
	NetworkManager.host_game()
	_disable_buttons()

func _on_join_pressed() -> void:
	var match_id = ip_input.text.strip_edges()
	if match_id.is_empty():
		if status_label: status_label.text = "Please enter a Match ID."
		return
		
	if status_label: status_label.text = "Joining Match..."
	
	NetworkManager.is_host = false
	# On rejoint directement l'ID
	NetworkManager.join_game(match_id)
	_disable_buttons()

func _on_nakama_ready() -> void:
	if join_button: join_button.disabled = false
	if status_label: status_label.text = "Online Services Ready."

func _on_connection_success() -> void:
	if status_label: status_label.text = "Connected! Waiting for game..."
	
	# Si on est le client qui rejoint, on cache aussi l'interface de connexion
	if not NetworkManager.is_host:
		if host_button: host_button.hide()
		if join_button: join_button.hide()
		if ip_input: ip_input.hide()

	# Check immediately if we already have peers (e.g. late join or bridge already synced)
	if start_game_timer.is_inside_tree():
		start_game_timer.start() # Start polling
	_check_start_game()

func _on_match_hosted(match_id: String) -> void:
	# Le Host reçoit l'ID réel ici. On l'affiche pour qu'il puisse le partager.
	if status_label: status_label.text = "Match Created! Share the Code below."
	if ip_input:
		ip_input.text = match_id
		ip_input.editable = false # On verrouille pour montrer que c'est un output
	
	# On cache les boutons Host/Join pour épurér l'interface et laisser la place au QR Code
	if host_button: host_button.hide()
	if join_button: join_button.hide()
	
	# Generate Invite Link
	# On ajoute un paramètre factice (&v=1) à la fin pour protéger le point final de l'ID.
	# Sinon, les messageries (WhatsApp, Discord) risquent de considérer le point comme une ponctuation de fin de phrase et de couper le lien.
	var invite_link = INVITE_BASE_URL + "?match_id=" + match_id + "&v=1"
	current_invite_link = invite_link
	copy_link_button.show()
	whatsapp_button.show()
	sms_button.show()
	discord_button.show()
	
	# Fetch QR Code from API
	if qr_http_request:
		var api_url = "https://api.qrserver.com/v1/create-qr-code/?size=350x350&data=" + invite_link.uri_encode()
		qr_http_request.request(api_url)

func _on_connection_fail() -> void:
	if status_label: status_label.text = "Connection Failed."
	_enable_buttons()
	start_game_timer.stop()

func _on_player_connected(user_id: String) -> void:
	if status_label: status_label.text = "Player " + user_id + " connected."
	_check_start_game()

func _check_start_game() -> void:
	# Logic to start the game when 2 players are ready (Self + 1 Opponent)
	var peers_count = NetworkManager.match_presences.size()
	print("DEBUG: Checking start game. Peers count: ", peers_count)
	if peers_count >= 1 and NetworkManager.is_host:
		print("Enough players! Can start game logic here.")
		start_game_timer.stop()
		NetworkManager.start_game()

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
		var js_code = "new URLSearchParams(window.location.search).get('match_id')"
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
		
		if NakamaManager.socket:
			_on_join_pressed()
		else:
			if status_label: status_label.text = "Auto-joining..."
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
		if status_label: status_label.text = "Link copied to clipboard!"

func _on_whatsapp_pressed() -> void:
	if current_invite_link:
		var msg = "Rejoins-moi sur King of the Apero! " + current_invite_link
		OS.shell_open("whatsapp://send?text=" + msg.uri_encode())

func _on_sms_pressed() -> void:
	if current_invite_link:
		var msg = "Rejoins-moi sur King of the Apero! " + current_invite_link
		# 'sms:?body=' est le standard le plus compatible (Android/iOS)
		OS.shell_open("sms:?body=" + msg.uri_encode())

func _on_discord_pressed() -> void:
	if current_invite_link:
		DisplayServer.clipboard_set(current_invite_link)
		if status_label: status_label.text = "Link copied! Paste it in Discord."
		# Discord n'a pas de scheme 'share' universel. On ouvre l'app/web sur les DMs.
		OS.shell_open("https://discord.com/channels/@me")