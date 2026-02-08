class_name ModelRelay
extends Node3D

# Signal émis quand l'animation atteint le moment de l'impact
signal hit_triggered
signal ko_impact_triggered

# Cette fonction sera appelée par la "Call Method Track" de l'AnimationPlayer
func on_hit_frame() -> void:
	hit_triggered.emit()

func on_ko_impact() -> void:
	ko_impact_triggered.emit()
