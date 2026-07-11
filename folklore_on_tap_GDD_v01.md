# Folklore On Tap — Game Design Document v0.1

> *Que font les légendes enfantines de leurs soirées ? Elles vont au pub et se castagnent.*

**Statut** : Document de travail — Mai 2026  
**Format** : Dev solo amateur · Android + Web App · 1v1 présentiel  
**Prochaine étape** : Design des archétypes et d'une dizaine de champions

---

## Piliers de design

| Pilier | Description |
|--------|-------------|
| ⚡ **Rapidité** | Priorité absolue sur tout. 5-10 min par partie, décisions immédiates |
| 🃏 **All-in possible** | Vider sa main est une option viable, avec le risque que ça implique |
| 🔥 **Combos** | 2 à 4 cartes, sensation versus fighting — des séquences qui font "wow" |
| 👥 **Asymétrie** | Gameplay véritablement différent par champion, pas juste des stats |
| 🎯 **Points faibles** | Chaque perso a une faiblesse exploitable qui dicte le rythme adverse |

---

## Contexte & format

### Situation de jeu
- À l'apéro, à l'arrêt de bus, à la pause café
- 1v1 en présentiel sur Android
- Un joueur crée une partie → génère un QR code → l'autre scanne
- App Android ou Web App si l'application n'est pas installée

### Plateau
- Grille 5×5 cases
- Départ dans deux coins opposés
- Case centrale = place du champion (dégâts ×2)
- Les poussées et positions ont de l'importance tactique

---

## Le deck

### Structure des cartes
- **Couleur** : rouge (attaque/parade) · noir (déplacement)
- **Enseigne** : `+` orthogonal · `×` diagonal
- **Tier** : T1 à T4 — 3 cartes par tier par enseigne = 48 cartes + 2 jokers
- **Zéro texte sur les cartes** — tout passe par icônes et couleur
- 4 flèches en bordure de carte indiquent la direction de l'effet

### Deck individuel par champion ✅ DÉCIDÉ
- Même nombre de cartes total pour tous les champions
- Ratio rouge/noir variable selon l'archétype (rusher = plus de noir, bourrin = plus de rouge)
- Répartition des tiers variable (perso lourd = plus de T3/T4)
- Répartition des enseignes variable (plus de `+` ou plus de `×`)
- **La composition du deck EST le personnage**, avant même la première carte jouée

---

## Règles de base (vanilla)

### Tour de jeu
- Main max : **5 cartes** *(à régler par playtesting)*
- Jouer / jeter : autant de cartes que désiré par tour
- Pioche en début de tour : **2 cartes max** *(à régler par playtesting)*
- Les joueurs jouent en alternance

### Conditions de victoire
- **KO** : l'adversaire tombe à 0 point d'endurance
- **Aux points** : vainqueur = plus de PV restants en fin de partie
- **Égalité** si même endurance restante
- **Règle de fin de deck** : ⚠️ EN SUSPENS (voir Questions ouvertes)

### Règles spéciales vanilla conservées
- Case centrale : dégâts doublés
- Inaction = tomate (−1 endurance)
- Joker : universel + rôle à définir par champion
- Poussée : repousse l'adversaire d'une case

---

## Système de combo

### Principe clé
**La puissance vient de la position dans le combo, pas du tier de la carte.**

Un combo se construit en jouant des cartes de tiers **strictement croissants** dans le même tour.

- On peut mélanger rouge et noir (prise d'élan + coup final)
- On peut commencer à n'importe quel tier (T2→T3 est un combo valide)
- La carte jouée doit être de tier ≥ à sa position dans le combo

### Effets par position

| Position | Tier minimum requis | Effet attaque | Effet déplacement |
|----------|--------------------|------------------------------------|-------------------------------|
| 1 | T1+ | Coup normal | Déplacement normal |
| 2 | T2+ | Parable par tier +1 minimum | Déplacement normal |
| 3 | T3+ | Imparable | Direction libre au choix |
| 4 | T4 | Double dégâts, imparable | Direction libre au choix / Peut pousser l'adversaire et lui infliger 1 degat et le suivre|

### Combos mixtes
Mélanger noir et rouge dans un même combo est autorisé et encouragé.  
Exemple : Noir T1 (élan) → Rouge T2 (coup) = la prise d'élan amplifie l'impact.

---

## Tokens de tier

### Motivation
Avec une main de 5 cartes, assembler un combo de 3 ou 4 cartes de tiers strictement croissants est difficile par nature — le tirage peut ne pas s'y prêter. Les tokens compensent ce manque de fluidité sans réduire la taille de main ni augmenter la pioche.

### Principe
Chaque champion dispose d'un **stock personnel de tokens**, défini une fois pour toutes (fait partie de la fiche du champion, au même titre que la composition du deck).

Un token peut être dépensé à n'importe quel moment lors du tour du joueur pour **modifier le tier d'une carte en main de ±1**, dans la limite T1–T4.

- Augmenter le tier d'une carte : facilite l'enchaînement vers la position suivante du combo
- Baisser le tier d'une carte : permet de redémarrer un combo depuis un tier plus bas

### Règles
- Un token dépensé est **perdu pour toute la partie** — la ressource est limitée et non rechargeable (sauf passif de champion)
- Un seul token par carte par utilisation (pas de double upgrade en un coup)
- La modification est visible pour les deux joueurs (la carte affiche son tier modifié)

### Ce que ça crée tactiquement
- Décision de gestion de ressource sur le long terme : dépenser maintenant pour un combo décisif, ou garder pour plus tard
- Interaction avec le bluff : l'adversaire sait que tu as des tokens, mais pas quand tu vas les utiliser
- Différenciation des archétypes : un bourrin a peu de tokens (son deck est déjà homogène), un acrobate en a beaucoup (son deck est varié par conception)

> ⚠️ **Questions ouvertes liées aux tokens** : voir section Questions ouvertes (point 7).

---

## Système de blocage

### Principe
- Le blocage se décide **à chaque carte du combo adverse** (pas au combo entier)
- Décision **immédiate et binaire** : j'ai une carte qui bloque, je choisis oui/non
- **Main vide = impossible de bloquer** — le combo s'enchaîne librement
- Les cartes de déplacement (noir) peuvent bloquer une attaque (rouge) → **esquive forcée** (le défenseur est contraint de se déplacer)

### Niveaux de blocage
| Type | Condition | Effet |
|------|-----------|-------|
| **Bloquer juste** | Tier minimum requis pour la position | Annule la carte, le combo continue |
| **Bloquer fort** | Tier supérieur au minimum requis | Annule la carte ET interrompt le combo |

Des **aides visuelles** sur les cartes indiqueront les seuils de blocage en temps réel pendant la réaction.

### Ce que ça crée tactiquement
- **Le bluff du combo** : poser T1 pour forcer une carte de blocage adverse, puis enchaîner T3 sur une main affaiblie
- **Le choix déchirant** : bloquer maintenant (et s'exposer) ou encaisser (et conserver ses ressources)
- **Le all-in** : vider sa main en combo = priver l'adversaire de toute possibilité de blocage

---

## Anatomie d'un champion

Chaque champion est défini par **5 couches de différenciation** :

### 1. Composition du deck
La répartition rouge/noir, tiers et enseignes définit le style de jeu fondamental.

### 2. Passif
Règle permanente liée à une carte spécifique, un tier, ou une situation de jeu.  
Exemples :
- Un tank qui bloque avec T4 repousse automatiquement l'adversaire
- Les cartes rouge T4 d'un perso contrôle tapent ET repoussent
- Bonus d'attaque si frappe de dos

### 3. Combo signature
Séquence de cartes spécifique au personnage déclenchant un effet unique.  
Exemple (Ninja) : `Noir (contact) → Noir (repositionnement libre) → prochain rouge = bonus "attaque de dos"`

### 4. Jauge d'ultime
- Condition de remplissage **propre au champion** (gérée invisiblement par l'appli)
- Déclenchement **manuel** — le joueur choisit le moment
- Piste de déclenchement : jouer un **joker** quand la jauge est pleine ⚠️ À CONFIRMER
- Tooltip perso = **icônes uniquement**, zéro texte long

### 5. Point faible
Condition exploitable par l'adversaire pour contrer le rythme naturel du champion.  
Le point faible doit dicter une stratégie adverse claire et lisible.

---

## Champions envisagés

### Santa Klaus
**Archétype** : Brute / Tank

| | |
|---|---|
| Deck | Riche en rouge, tiers hauts |
| Passif | Résistance aux poussées |
| Jauge | Monte en encaissant des coups |
| Ultime | Frappe imparable à zone |
| Faiblesse | Lent et prévisible — le kiter l'empêche d'enrager |

---

### Marchand de Sable
**Archétype** : Contrôle / Temps

| | |
|---|---|
| Deck | Équilibré, tiers bas/moyens |
| Passif | À définir |
| Jauge | Monte automatiquement chaque tour (le temps joue pour lui) |
| Ultime | Endormissement — l'adversaire perd un tour |
| Faiblesse | Passif, doit survivre assez longtemps — le rusher le neutralise |

> Note design : ce perso pourrait dicter la règle de fin de deck.

---

### Chaperon Rouge
**Archétype** : Distance / Contrôle de zone

| | |
|---|---|
| Deck | Noir ++, rouge ×, tiers mixtes |
| Passif | Bonus à distance (portée = nombre de cases séparant les persos) |
| Jauge | À définir |
| Ultime | Tir chargé dévastateur |
| Faiblesse | Vulnérable au corps à corps |

---

### Leprechaun
**Archétype** : Mobilité / Esquive

| | |
|---|---|
| Deck | Noir +++, tiers bas/moyens |
| Passif | À définir |
| Jauge | Monte en se déplaçant |
| Ultime | À définir |
| Faiblesse | Peu de puissance brute |

---

### Ninja (archétype acrobate — exemple de combo signature)
`Noir (déplacement au contact)` → `Noir (repositionnement libre sur toute case adjacente)` → prochain coup rouge bénéficie d'un bonus "attaque de dos".  
La mécanique raconte le personnage sans un mot.

---

## Questions ouvertes

> Ces points sont délibérément laissés en suspens — à arbitrer lors du design des champions ou du playtesting.

1. **Fin de deck** : Recycler la défausse / arrêt au 1er deck vide / arrêt au 2e deck vide.  
   Le Marchand de Sable (jauge auto = jouer sur l'épuisement) pourrait naturellement dicter la réponse.

2. **Taille de main & pioche** : Main max 5 cartes, pioche 2 par tour.  
   Valeurs à confirmer par le playtesting.

3. **Déclenchement de l'ultime** : Manuel. Piste = joker quand jauge pleine.  
   À confirmer.

4. **Blocage mouvement → attaque** : Esquive pure (déplacement forcé) ou contre avec repositionnement et éventuelle riposte ?

5. **Rôle du joker** : Universel uniquement, ou effet signature par champion en plus ?

6. **Calibration du blocage** : Les seuils du tableau (T+1, T+2, imparable...) sont des pistes — à ajuster en playtesting.

7. **Tokens de tier** : Stock initial par champion à calibrer. Pistes à explorer :
   - Les tokens sont-ils rechargeables (en fin de tour, en encaissant des coups, via passif) ?
   - Peut-on modifier une carte déjà jouée dans le combo en cours, ou uniquement avant de la jouer ?
   - Le tier modifié affecte-t-il le niveau de blocage requis côté défenseur ?

---

*Folklore On Tap · GDD v0.1 · Prochaine étape : design des archétypes et d'une dizaine de champions*
