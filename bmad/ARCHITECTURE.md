# Architecture Technique - King of the Apero

## Vue d'ensemble
Le projet suit une architecture basée sur la **Composition** et les **Signaux**. L'état du jeu est centralisé, mais la logique spatiale est déléguée.

## Nœuds Principaux

### 1. Arena (`Arena.gd`)
*   **Rôle :** Racine de la scène de jeu (Composition Root).
*   **Responsabilité :** Instancie les sous-systèmes, injecte les dépendances et connecte les signaux majeurs entre l'UI, le Manager de Jeu et la Grille.
*   **Enfants directs :** `GameManager`, `GridManager`, `DeckManager`, `GameUI`.

### 2. GameManager (`GameManager.gd`)
*   **Rôle :** Arbitre et Machine à États.
*   **Responsabilité :**
    *   Gère le tour par tour (`active_player_index`).
    *   Gère les mains des joueurs (`player_hands`).
    *   Valide l'utilisation des cartes (`use_card`).
    *   Gère la pioche et la défausse via `DeckManager`.
*   **Communication :** Émet des signaux (`turn_started`, `card_drawn`, `turn_ended`) écoutés par l'UI et l'Arena.

### 3. GridManager (`GridManager.gd`)
*   **Rôle :** Gestionnaire Spatial et Visuel 3D.
*   **Responsabilité :**
    *   Génère le Ring procédural.
    *   Convertit Grille (Vector2i) <-> Monde (Vector3).
    *   Gère le pathfinding/validation des mouvements (`valid_cells`).
    *   Gère le Raycasting (clic souris).
    *   Instancie et stocke les `Wrestler`.
*   **Dépendance :** A besoin de `GameManager` pour consommer les cartes après action.

### 4. Wrestler (`Wrestler.gd`)
*   **Rôle :** Pion / Entité.
*   **Responsabilité :**
    *   Stocke ses PV et sa position grille.
    *   Gère son déplacement visuel (Tween).
    *   Contient le modèle 3D et l'`AnimationPlayer`.
*   **Dépendance :** A besoin de `GridManager` pour connaître les coordonnées monde.

### 5. GameUI & CardUI
*   **Rôle :** Interface Utilisateur.
*   **Responsabilité :** Afficher la main, le tour actuel, et capturer les inputs UI (boutons, clics cartes).
*   **Communication :** Ne modifie jamais l'état du jeu directement. Émet des signaux (`card_selected`, `discard_requested`) vers l'Arena/GameManager.

## Flux de Données (Data Flow)

1.  **Début de Tour :** `GameManager` -> Signal `turn_started` -> `Arena` met à jour `GridManager` (pion actif) et `GameUI` (main).
2.  **Sélection Carte :** `CardUI` (clic) -> Signal `card_selected` -> `GridManager` (calcule validité + highlight).
3.  **Action Jeu :** `GridManager` (clic plateau) -> Valide mouvement -> Déplace `Wrestler` -> Appelle `GameManager.use_card()`.
4.  **Défausse :** `CardUI` (clic X) -> Signal `discard_requested` -> `GameManager` (retire de la main + pioche potentielle future).

## Conventions de Signaux
*   Les composants de bas niveau (UI, Entity) ne doivent pas appeler directement les fonctions des Managers si possible, mais émettre des signaux.
*   `Arena.gd` sert de "hub" de connexion pour éviter le couplage fort entre `GameUI` et `GridManager`.

## Structure des Scènes
*   `Wrestler.tscn` : Racine `Node3D` (Script) -> Modèle 3D (GLB) -> AnimationPlayer.
*   `CardUI.tscn` : Racine `PanelContainer`.