extends Node

signal match_created(match_id: String)
signal match_joined(match_id: String)
signal nakama_ready

# Nakama Configuration (Localhost by default for dev)
var SCHEME = "http"
var HOST = "127.0.0.1"
var PORT = 7350
var SERVER_KEY = "defaultkey" # Default key for Nakama Docker image

# Main Nakama API objects
var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket

func _ready() -> void:
	# Load secrets/config if available
	_load_config()
	
	# 1. Client Initialization
	# The 'Nakama' singleton is provided by the plugin you just installed
	client = Nakama.create_client(SERVER_KEY, HOST, PORT, SCHEME)
	
	# Timeout configuration (optional but recommended)
	client.timeout = 10
	
	print("✅ Nakama Client initialized: %s://%s:%d" % [SCHEME, HOST, PORT])
	
	# Automatic connection on startup
	login_with_device()

func _load_config() -> void:
	var config = ConfigFile.new()
	var err = config.load("res://secrets.cfg")
	if err == OK:
		SCHEME = config.get_value("nakama", "scheme", SCHEME)
		HOST = config.get_value("nakama", "host", HOST)
		PORT = config.get_value("nakama", "port", PORT)
		SERVER_KEY = config.get_value("nakama", "server_key", SERVER_KEY)
		print("🔒 Configuration loaded from secrets.cfg")
	elif not OS.is_debug_build():
		# Configuration de Production (Export) - S'active automatiquement sur itch.io / Android APK
		SCHEME = "https"
		HOST = "kotapero.xyz"
		PORT = 443 # Caddy gère le SSL sur le port standard HTTPS
		print("🚀 Release Mode detected. Using Production Server: ", HOST)
	else:
		print("⚠️ No secrets.cfg found. Using default (Localhost) configuration.")

func login_with_device() -> void:
	# Use unique device/machine ID as identifier
	var device_id = OS.get_unique_id()
	
	# DEBUG: If running in editor/desktop, append process ID to simulate distinct devices
	if OS.is_debug_build() and OS.has_feature("pc"):
		device_id += "_" + str(OS.get_process_id())
	
	# Authentication (or account creation if first time)
	# 'await' allows waiting for server response without blocking the game
	session = await client.authenticate_device_async(device_id)
	
	if session.is_exception():
		printerr("❌ Auth Error: ", session.get_exception().message)
		return
		
	print("✅ Authenticated! Session Token: ", session.token)
	print("👤 User ID: ", session.user_id)
	
	# Once authenticated, open real-time connection (Socket)
	_connect_socket()

func _connect_socket() -> void:
	# Socket creation via Nakama singleton (Standard)
	socket = Nakama.create_socket_from(client)
	
	# DEBUG: Listen to presence events globally to verify network traffic
	socket.received_match_presence.connect(_on_match_presence_debug)
	
	# Connect with the session we just obtained
	var connected = await socket.connect_async(session)
	
	if connected.is_exception():
		printerr("❌ Socket Error: ", connected.get_exception().message)
		return
		
	print("✅ Socket Connected! Ready for Multiplayer.")
	nakama_ready.emit()

func create_match() -> void:
	if socket == null:
		return
		
	print("⚡ Creating a new match...")
	var result = await socket.create_match_async()
	
	if result.is_exception():
		printerr("❌ Create Match Error: ", result.get_exception().message)
	else:
		print("✅ Match Created! ID: ", result.match_id)
		match_created.emit(result.match_id)

func join_match_manually(match_id: String) -> Dictionary:
	# Manually join to get the initial presences list reliably
	print("⚓ Joining match manually to fetch presences...")
	var join_msg = NakamaRTMessage.MatchJoin.new()
	join_msg.match_id = match_id
	
	var request = socket._send_async(join_msg, NakamaRTAPI.Match)
	var result = await request.completed
	
	if result.is_exception():
		printerr("❌ Manual Join Error: ", result.get_exception().message)
		return {}
		
	print("✅ Manual Join Success. Presences count: ", result.presences.size())
	return {"presences": result.presences, "self": result.self_user}

func inject_presences(match_id: String, presences: Array) -> void:
	if presences.is_empty():
		return
	print("💉 Injecting ", presences.size(), " presences into socket stream...")
	var event = NakamaRTAPI.MatchPresenceEvent.new()
	event.match_id = match_id
	event.joins = presences
	socket.received_match_presence.emit(event)

func _on_match_presence_debug(p_presence: NakamaRTAPI.MatchPresenceEvent) -> void:
	print("DEBUG: Socket received presence event for match: ", p_presence.match_id)
	print("DEBUG: Joins: ", p_presence.joins.size(), " Leaves: ", p_presence.leaves.size())

func get_socket() -> NakamaSocket:
	return socket

func get_client() -> NakamaClient:
	return client