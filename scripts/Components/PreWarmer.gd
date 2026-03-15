extends Node3D

@export var particles_to_warm: Array[PackedScene] = []
@export var sounds_to_warm: Array[AudioStream] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("🔥 PreWarmer: Starting background warm-up...")
	
	# 1. Préchauffage des Particules / Shaders
	print("🔥 PreWarmer: Warming up ", particles_to_warm.size(), " particles...")
	for scene in particles_to_warm:
		if scene:
			print("   -> Spawning particle: ", scene.resource_path)
			var inst = scene.instantiate()
			add_child(inst)
			
			# On le place AU CENTRE de l'écran pour forcer le GPU à le rendre (Culling off)
			# Mais on le rend quasi-invisible. Le rideau noir masquera le reste.
			if inst is Node3D:
				inst.position = Vector3(0, 1, 0)
			elif inst is Node2D or inst is Control:
				inst.position = get_viewport().get_visible_rect().size / 2.0
				inst.modulate = Color(1, 1, 1, 0.01) # 1% d'opacité
				inst.z_index = -100 # On s'assure qu'il est dessiné DERRIÈRE le rideau noir
				
			# Force l'émission si c'est un système de particules natif
			if "emitting" in inst:
				inst.emitting = true
				
			if inst.has_method("setup"):
				inst.setup(get_viewport().get_visible_rect().size / 2.0)
			
	# 2. Préchauffage des Sons (Lecture silencieuse)
	print("🔥 PreWarmer: Warming up ", sounds_to_warm.size(), " sounds...")
	for sound in sounds_to_warm:
		if sound:
			print("   -> Playing sound silently: ", sound.resource_path)
			var player = AudioStreamPlayer.new()
			player.stream = sound
			player.volume_db = -80.0 # Totalement inaudible (-80 dB)
			add_child(player)
			player.play()
			
	# On donne un peu plus de temps au navigateur pour tout digérer en arrière-plan
	await get_tree().create_timer(1.0).timeout
	
	print("✅ PreWarmer: Warm-up complete. Self-destructing.")
	queue_free()
