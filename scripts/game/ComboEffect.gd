class_name ComboEffect
extends Resource

## Effets d'une position de combo. Utilisé par TurnManager et consommé par
## CombatSequencer (is_unblockable, block_tier_bonus, damage_multiplier)
## et GridManager (free_direction, push_and_follow).

@export var is_unblockable: bool = false
@export var block_tier_bonus: int = 0
@export var damage_multiplier: int = 1
@export var free_direction: bool = false
@export var push_and_follow: bool = false
@export var push_damage: int = 0
