# Contexte du Projet : Jeu Apéro "Rois du Ring"

**Règles originales (PDF) :** [Télécharger les règles](http://golgoisland.free.fr/articles/roisduring/RoisduRing-FR.pdf)

## 1. Vision du Projet

*   **Concept :** Adaptation numérique du jeu de plateau "Les Rois du Ring" (Chien Sauvage).
*   **Genre :** Jeu de stratégie tour par tour, 1v1, rapide (format "jeu apéro").
*   **Gameplay :** Déplacement de pions sur une grille (5x5 ou 6x6) via un système de cartes (Mouvement, Attaque, Projection).
*   **Cible :** Mobile et Web (PWA).
*   **Objectif long terme :** Multijoueur P2P (WebRTC), système de skins/emotes déblocables.

## 2. Stack Technique

*   **Moteur :** Godot Engine 4.x.
*   **Langage :** GDScript.
*   **Direction Artistique :** 3D Low-Poly (Blender) avec animations Mixamo.
*   **Architecture :** Logique autoritaire synchronisée (préparation pour le futur multijoueur).

## 3. Objectif Actuel : Le P.O.C. (Proof of Concept)

L'objectif est de passer d'un prototype mécanique à une boucle de jeu complète (Phase 2).

---

# Roadmap

## Phase 1 : Prototype Mécanique (P.O.C.) [COMPLETED]

- [x] **Étape 1 :** Mise en place de l'Arène (Grid System)
- [x] **Étape 2 :** Les Catcheurs (Pions)
- [x] **Étape 3 :** Système de Cartes (Logique)
- [x] **Étape 4 :** La Boucle de Jeu (Game Loop)
- [x] **Étape 5 :** Conditions de Victoire

## Phase 2 : Game Loop & Système de Deck

**Objectif :** Passer d'un mode "bac à sable" à un match structuré en tour par tour où les actions sont dictées par une main de cartes limitée et piochée aléatoirement.

### Architecture Technique
*   **GameManager :** Nœud central qui pilote le déroulement (Machine à états).
*   **HandManager (UI) :** Conteneur visuel pour afficher les cartes piochées.
*   **DeckManager :** Gestion de la pile de cartes (Mélange, Pioche, Défausse).

### Tâches à réaliser

- [x] **Étape 2.1 : L'Arbitre (Turn Manager)**
    *   Implémenter un script `GameManager` gérant l'alternance entre Player1 et Player2.
    *   Variables : `active_player`, `remaining_actions`.
    *   UI : Ajouter un bouton "Fin de Tour".
- [x] **Étape 2.2 : Logique du Deck et de la Main**
    *   **Deck :** Tableau de `CardData`, mélangé (`shuffle`) au début.
    *   **Main :** Limite de cartes (ex: 5). Pioche au début du tour.
    *   **Défausse :** Pile pour les cartes jouées.
- [ ] **Étape 2.3 : Liaison UI -> Gameplay**
    *   Mise à jour de `CardUI` pour être dynamique.
    *   Logique de sélection stricte (Carte + Cible valide).
- [ ] **Étape 2.4 : Amélioration du Feedback Visuel**
    *   **Highlight :** Colorer les cases accessibles (Bleu=Move, Rouge=Attack).
    *   **Orientation :** Pivoter le pion vers la cible avant l'action.
- [ ] **Étape 2.5 : Traduction du jeu de 52 cartes**
    *   Adapter `CardData` (ou créer un traducteur) pour convertir une carte standard en action.
    *   **Cartes Noires (Mouvement) :** Pique (Orthogonal), Trèfle (Diagonal). Portée = Valeur.
    *   **Cartes Rouges (Attaque) :** Cœur (Orthogonal), Carreau (Diagonal). Portée = 1, Force = Valeur.
    *   **Conséquence :** Attaque réussie = Poussée (selon Force). Sortie de ring = KO.

### Règles de Validation
*   **MOVE :** La case cible doit être vide.
*   **ATTACK :** La case cible doit contenir un adversaire et être adjacente (distance = 1).
*   **THROW :** La case cible doit contenir un adversaire. Déplace l'adversaire de X cases dans la direction opposée.
