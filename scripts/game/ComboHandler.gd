class_name ComboHandler
extends Resource

## Script de base pour les effets de combo spécifiques à un champion.
## Étendre cette classe dans un script attaché à WrestlerData.combo_handler
## pour surcharger ou enrichir les effets de base.

func get_effect(position: int, base_effect: ComboEffect) -> ComboEffect:
	return base_effect
