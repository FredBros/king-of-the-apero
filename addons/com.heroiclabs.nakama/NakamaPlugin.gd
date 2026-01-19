@tool
extends EditorPlugin

func _enter_tree() -> void:
	# Ajoute le singleton Nakama automatiquement lors de l'activation
	add_autoload_singleton("Nakama", "res://addons/com.heroiclabs.nakama/Nakama.gd")

func _exit_tree() -> void:
	# Nettoie le singleton lors de la désactivation
	remove_autoload_singleton("Nakama")