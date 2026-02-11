class_name SmokePuff
extends AnimatedSprite2D

func _ready() -> void:
	# 1. Auto-destruction à la fin de l'animation
	animation_finished.connect(queue_free)
	
	# 2. Variété visuelle (Rotation et Taille aléatoires)
	# Cela évite que toutes les explosions se ressemblent si on en joue plusieurs
	rotation = randf_range(0, TAU) # 0 à 360 degrés
	var random_scale = randf_range(2.4, 3.6)
	scale = Vector2(random_scale, random_scale)
	
	# 3. Lancer l'animation (sécurité si l'autoplay n'est pas coché)
	if not is_playing():
		play("default")

# Fonction utilitaire pour configurer l'effet lors de l'instanciation
func setup(pos: Vector2, color: Color = Color.WHITE) -> void:
	global_position = pos
	modulate = color