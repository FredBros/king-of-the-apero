# Conventions de Code - King of the Apero

## Langage
*   **GDScript 2.0** (Godot 4.x).
*   Typage statique fort recommandé (`: int`, `: void`, `: String`, `-> bool`).
*   **Anglais obligatoire** pour tout le code (noms de variables, fonctions, classes) et les commentaires.

## Nommage
*   **Fichiers/Classes :** `PascalCase` (ex: `GridManager.gd`, `CardData.gd`).
*   **Variables/Fonctions :** `snake_case` (ex: `current_health`, `calculate_offset()`).
*   **Constantes/Enums :** `SCREAMING_SNAKE_CASE` (ex: `MAX_HEALTH`, `CardType.ATTACK`).
*   **Privé :** Préfixe `_` pour les fonctions/variables internes (ex: `_update_highlights()`).

## Structure des Scripts
Ordre standard des éléments dans un fichier `.gd` :
1.  `class_name`
2.  `extends`
3.  `signal`
4.  `@export` vars
5.  `@onready` vars
6.  Public vars
7.  `_init` / `_ready`
8.  `_process` / `_input` (fonctions système)
9.  Public functions
10. Private functions / Signal callbacks (`_on_...`)

## Gestion de la 3D
*   **Y-Up :** L'axe Y est la hauteur. Le sol est à Y=0.
*   **Grid Mapping :**
    *   Grid X = World X.
    *   Grid Y = World Z.
*   **Tweening :** Utiliser `create_tween()` pour les mouvements fluides plutôt que `_process`.

## Gestion des Animations
*   Utilisation de l'`AnimationTree` (State Machine) ou appels directs `AnimationPlayer.play()` si simple.
*   Noms d'animations standardisés : "Idle", "Walk", "Run", "Punch", "Hurt", "Die".

## Debug
*   Utiliser `print()` pour les logs de gameplay majeurs.
*   Utiliser `printerr()` pour les erreurs critiques (ex: dépendance manquante).
*   Les objets de debug (ex: grille visuelle) doivent être générés par code ou dans un dossier "Debug".

## Chemins de Fichiers
*   Scripts : `res://scripts/`
*   Scènes : `res://scenes/`
*   Assets 3D : `res://scenes/Players/` ou `res://assets/models/`