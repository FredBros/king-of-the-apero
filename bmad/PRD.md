# Product Requirements Document (PRD) - King of the Apero

## Vision
Adaptation numérique du jeu de plateau "Les Rois du Ring". Un jeu de stratégie au tour par tour en 1v1, rapide ("jeu apéro").
**Cible principale :** Multijoueur local "présentiel" (Canapé, Bar, Soirée) via smartphones (Android & Web App). L'objectif est de remplacer le plateau physique par les téléphones, sans friction de connexion.

## État du Projet
**Phase Actuelle :** Phase 3 (Graphismes et Modèles 3D).
**Statut :** Boucle de jeu fonctionnelle (Phase 2 terminée). Intégration 3D en cours.

## Fonctionnalités Implémentées (Core Gameplay)

### 1. Arène et Grille
*   **Structure :** Grille logique (par défaut 6x6) mappée sur un monde 3D.
*   **Visuel :** Plateau généré procéduralement.
*   **Placement :** Les personnages apparaissent dans les coins opposés (Haut-Gauche vs Bas-Droite).

### 2. Système de Tour (Game Loop)
*   **Structure :** Tour par tour strict (Joueur 1 -> Joueur 2).
*   **Actions :** Pas de points d'action. Le joueur joue autant de cartes qu'il le souhaite/peut.
*   **Fin de tour :** Manuelle via bouton "END TURN".

### 3. Gestion des Cartes (Deck & Main)
*   **Deck :** Jeu de 54 cartes standard (52 + 2 Jokers).
*   **Main :**
    *   Taille max : 5 cartes.
    *   Pioche : Max 2 cartes par début de tour (pour compléter la main).
    *   Défausse : Possible via bouton contextuel "X" sur la carte (ne consomme pas d'action de jeu, permet de cycler).

### 4. Règles des Cartes (Mapping)
*   **Cartes Noires (Mouvement) :**
    *   ♠️ Pique : Mouvement Orthogonal.
    *   ♣️ Trèfle : Mouvement Diagonal.
    *   Portée : Valeur de la carte.
*   **Cartes Rouges (Attaque) :**
    *   ♥️ Cœur : Attaque Orthogonale (Portée 1).
    *   ♦️ Carreau : Attaque Diagonale (Portée 1).
    *   Dégâts : 1 PV (pour l'instant).
*   **Jokers :** Wildcard (Mouvement ou Attaque, Orthogonal ou Diagonal).

### 5. Feedback Visuel
*   **Highlight :** Cases bleues (Mouvement valide) et Rouges (Cible valide) lors de la sélection d'une carte.
*   **Indicateur Actif :** Cercle vert au sol sous le personnage dont c'est le tour.
*   **Orientation :** Le personnage pivote vers la case cible avant d'agir.

## Fonctionnalités à Venir (Backlog Immédiat)

### Phase Critique : Multijoueur Online
1.  **Architecture Réseau :** Support WebSockets pour compatibilité HTML5/Android.
2.  **Infrastructure :** Backend Nakama (Docker) pour le Matchmaking et le Relais.
3.  **Topologie :** Client-Server Relayed via Nakama Socket (JSON). Abandon du High-Level Multiplayer API de Godot pour une gestion manuelle des messages (plus robuste pour le tour par tour).
4.  **Plateforme :** Optimisation Web (PWA) pour jouer sans installation, et App Android pour la performance.

### Phase 3 : Graphismes & 3D
1.  **Animation Controller :** Connecter le script du personnage (actuellement `Wrestler.gd`) à l'`AnimationPlayer` (Idle, Walk, Punch, Hurt).
2.  **Obstacles :** Ajout d'objets sur le plateau (caisses, obstacles) bloquant le passage ou destructibles.

### Règles Avancées (Gameplay)
1.  **Tomates (Anti-AFK) :** Si un joueur termine son tour sans avoir joué ni défaussé de carte, il perd 1 PV (sanction du public).
2.  **Poussée (Choix Tactique) :** Lors d'une attaque réussie, l'attaquant choisit entre :
    *   Infliger 1 Dégât.
    *   Pousser l'adversaire d'1 case (dans la direction de l'attaque). *Note : Impossible si la case cible est hors du ring.*
3.  **Réactions (Tour Adverse) :** *Cible prioritaire : Mode Online.*
    *   **Blocage :** Jouer une carte de la même couleur que l'attaque, valeur strictement supérieure. Annule l'attaque.
    *   **Esquive :** Jouer une carte de Mouvement "Opposé" (Ortho vs Diag), valeur strictement supérieure. Annule l'attaque.
        *   Attaque Orthogonale (♦) -> Esquive via Mouvement Diagonal (♠).
        *   Attaque Diagonale (♥) -> Esquive via Mouvement Orthogonal (♣).

### Phase 4 : Polish & UI
1.  **Caméra :** Ajout de mouvements de caméra ou de screenshake lors des impacts.
2.  **VFX :** Particules lors des coups.
3.  **Ergonomie Mobile :** Interface tactile adaptée (gros boutons, drag & drop facile).
*   **Attaque :** Nécessite une cible adjacente.
*   **Mort :** PV <= 0 -> `queue_free()` -> Fin de partie si 1 seul survivant.