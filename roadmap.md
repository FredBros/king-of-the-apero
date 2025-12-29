

# Contexte du Projet : Jeu Apéro "Rois du Ring"

## 1. Vision du Projet

* **Concept :** Adaptation numérique du jeu de plateau "Les Rois du Ring" (Chien Sauvage).
* **Genre :** Jeu de stratégie tour par tour, 1v1, rapide (format "jeu apéro").
* **Gameplay :** Déplacement de pions sur une grille (5x5 ou 6x6) via un système de cartes (Mouvement, Attaque, Projection).
* **Cible :** Mobile et Web (PWA).
* **Objectif long terme :** Multijoueur P2P (WebRTC), système de skins/emotes déblocables.

## 2. Stack Technique

* **Moteur :** Godot Engine 4.x.
* **Langage :** GDScript.
* **Direction Artistique :** 3D Low-Poly (Blender) avec animations Mixamo.
* *Note :* Utilisation de caméras orthographiques pour garder la lisibilité "jeu de plateau".


* **Architecture :** Logique autoritaire synchronisée (préparation pour le futur multijoueur).

## 3. Objectif Actuel : Le P.O.C. (Proof of Concept)

L'objectif est de créer une version **Hotseat** (2 joueurs sur la même machine) pour valider les mécaniques de base, le déplacement et l'utilisation des cartes, sans aucune couche réseau pour l'instant.

---

# Roadmap : Phase 1 - Prototype Mécanique (P.O.C.)

L'agent doit implémenter les fonctionnalités suivantes, étape par étape :

### Étape 1 : Mise en place de l'Arène (Grid System)

* Créer une scène 3D avec une caméra fixe (vue de dessus/isométrique).
* Générer un plateau de jeu (le Ring) constitué d'une grille logique (ex: `TileMap` ou tableau de coordonnées `Vector2`).
* Mettre en place un système de conversion : Coordonnées du Monde 3D <-> Coordonnées de Grille (x, y).

### Étape 2 : Les Catcheurs (Pions)

* Importer un modèle 3D placeholder (capsule ou low poly simple).
* Créer une classe `Wrestler` avec des propriétés de base :
* `grid_position` (Vector2)
* `health` / `state` (Debout, Au sol, KO)


* Implémenter le déplacement visuel d'une case à l'autre (via `Tween` pour la fluidité).

### Étape 3 : Système de Cartes (Logique)

* Créer une ressource `CardData` (Resource Godot) définissant :
* Type (Déplacement, Frappe, Projection).
* Valeur (Portée ou Dégâts).


* Créer une UI simple (CanvasLayer) affichant une "Main" de 3 cartes factices en bas de l'écran.

### Étape 4 : La Boucle de Jeu (Game Loop)

* Implémenter un système de **Tour par Tour** basique :
* Tour du Joueur 1 -> Sélectionne une carte -> Clique sur la grille/cible -> Action -> Fin du tour.
* Tour du Joueur 2 -> Idem.


* Gérer la validation des coups (ex: "Est-ce que la case cible est à portée de la carte Déplacement ?").

### Étape 5 : Conditions de Victoire

* Détecter si un joueur est éjecté du ring (coordonnées hors grille) ou si ses PV tombent à 0.
* Afficher un message de victoire simple et un bouton "Reset".

---

**Instruction pour l'agent :** Commence par l'Étape 1 (Mise en place de l'arène et de la grille logique).