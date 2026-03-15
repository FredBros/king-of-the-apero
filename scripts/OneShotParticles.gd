class_name OneShotParticles
extends CPUParticles3D

func _ready() -> void:
	emitting = true
	# Connecte le signal de fin d'émission pour supprimer l'objet
	finished.connect(queue_free)
