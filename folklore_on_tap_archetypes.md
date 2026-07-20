# Folklore On Tap — Archétypes

> Document de travail — squelettes mécaniques des 4 archétypes de base.
> Rien n'est gravé dans le marbre : à ajuster au playtest physique (proto août).
>
> **Règle d'écriture** : les compétences (passif, ultime, déclencheur de combo signature) se décrivent en **Palier** (ce qui est visible dans le tooltip et en jeu), jamais en **Tier** (attribut caché de la carte). Le Tier reste réservé à la composition du deck, au blocage et à l'esquive.

---

## Vocabulaire de référence

| Terme | Définition |
|---|---|
| **Tier (T0–T5)** | Valeur imprimée sur la carte. Ne détermine ni la puissance du coup ni l'amplitude du déplacement. Sert uniquement de seuil pour le blocage/l'esquive, et à la construction du combo (ordre strictement croissant). T0/T5 n'existent jamais dans le deck — uniquement créées via token, exceptionnelles, propres à certains champions. |
| **Palier** | Position dans la séquence de combo (les étoiles du tooltip). Seul déterminant de la puissance/effet réel de la carte jouée. |
| **Init** | La carte qui ouvre le combo, peu importe son tier. |
| **Blocage** | Défense classique : même enseigne, tier supérieur au minimum requis. Coût standard. |
| **Esquive** | Défense alternative (réservée à certains persos/archétypes) : carte de mouvement, enseigne **opposée**, tier supérieur (coût plus élevé, ex. +2). Le défenseur choisit sa case de repli. |

---

## 1. Le Bourrin (Tank)

**Fantasme** : lent à démarrer, dévastateur une fois lancé. Punit l'adversaire qui reste au contact trop longtemps.

| Couche | Détail |
|---|---|
| Deck | Rouge dominant (≈60%), tiers hauts sur-représentés, peu de T1 |
| Blocage / Esquive | Bloque uniquement, coût standard. Pas d'esquive. |
| Tokens | Peu (2–3) |
| T0 / T5 | Aucun accès |
| **Passif** | Bloquer une attaque arrivée au **Palier 3 ou 4** repousse l'adversaire d'une case en plus d'annuler le coup |
| **Combo signature** | *(à définir)* |
| **Ultime** | Jauge : monte en encaissant des coups. Effet : frappe imparable en zone (4 cases adjacentes), dégâts doublés si déclenchée depuis la case centrale |
| Point fort (tooltip) | Un combo complet de lui fait très mal — ne le laisse jamais l'amorcer tranquillement |
| Point faible (tooltip) | Il est lent à démarrer et ne suit pas — garde la distance, il finira par jeter ses grosses cartes sans les enchaîner |

---

## 2. Le Marksman (Contrôle à distance)

**Fantasme** : punit la distance, faible au corps à corps.

| Couche | Détail |
|---|---|
| Deck | Une seule enseigne dominante (diagonale ou orthogonale), rouge, tiers bas/moyens |
| Blocage / Esquive | Bloque bien dans son enseigne dominante, très mal dans l'autre |
| Tokens | Moyen (4–5) |
| T0 / T5 | Aucun accès |
| **Passif** | Bonus de dégâts proportionnel à la distance avec l'adversaire |
| **Combo signature** | *(à définir)* |
| **Ultime** | Jauge : monte en touchant à distance (hors contact). Effet : tir chargé, gros dégâts, une seule direction |
| Point fort (tooltip) | Chaque coup à distance fait mal et remplit son ultime — ne le laisse jamais respirer loin de toi |
| Point faible (tooltip) | Colle-toi à lui et change d'angle — il ne peut pas parer ce qu'il ne voit pas venir dans son enseigne faible |

---

## 3. L'Assassin (Agile)

**Fantasme** : rapide, mobile, fragile. Compense l'intensité par la fréquence.

| Couche | Détail |
|---|---|
| Deck | Noir dominant (≈65%), tiers bas, très peu/pas de T4 |
| Blocage / Esquive | Esquive uniquement (enseigne opposée, coût supérieur). Ne bloque jamais. |
| Tokens | Peu (2–3) |
| T0 / T5 | Accès **Palier 0** (via token) — permet d'amorcer un combo sur une main autrement injouable |
| **Passif** | Bonus d'attaque si frappe de dos |
| **Combo signature** | *(à définir — ex. mouvement au contact → repositionnement libre → prochain coup bonus "attaque de dos")* |
| **Ultime** | Jauge : monte en se déplaçant. Effet : téléportation derrière l'adversaire + prochain coup bonus garanti |
| Point fort (tooltip) | Il frappe souvent et se replace sans arrêt — un instant d'inattention et il est déjà dans ton dos |
| Point faible (tooltip) | Il encaisse peu — un gros coup qui passe peut suffire à le finir |

---

## 4. L'Enabler (Technique)

**Fantasme** : peu fiable seul, explosif avec ses tokens. "Triche" la statistique de combo.

| Couche | Détail |
|---|---|
| Deck | Équilibré rouge/noir, tiers mélangés sans dominante |
| Blocage / Esquive | Moyen partout, sans exceller |
| Tokens | Beaucoup (7–8) — c'est son moteur principal |
| T0 / T5 | Accès **Palier 5** (via token) — prolonge un combo déjà lancé d'un palier supplémentaire |
| **Passif** | *(à définir)* |
| **Combo signature** | *(à définir)* |
| **Ultime** | Jauge : monte en dépensant des tokens. Effet : recharge instantanée de tous les tokens dépensés dans la partie |
| Point fort (tooltip) | Rien ne l'arrête une fois lancé — son ultime peut relancer un deuxième combo dans la foulée |
| Point faible (tooltip) | Il a besoin de temps pour s'installer — rush-le avant qu'il ait pu dépenser ses tokens |

---

## Champions assignés (provisoire)

| Champion | Archétype | Note de lore |
|---|---|---|
| Santa Klaus | Bourrin | Fatigue de décembre, hotte vide en guise d'arme |
| Chaperon Rouge | Marksman | A récupéré le fusil du chasseur pour venger les enfants du loup |
| Marchand de Sable | Enabler | Joue avec le temps — l'adversaire s'endort après un nombre de tours, réductible via compétences |
| Leprechaun *(ou Lapin de Pâques en réserve)* | Assassin | Lutin mobile, sautillant |

---

## Points de vigilance identifiés

- Bourrin et Marksman ont un point faible proche ("garde la distance") — à surveiller au playtest, l'asymétrie doit se ressentir en jeu (lenteur générale vs enseigne aveugle spécifique)
- T0 (Assassin) et T5 (Enabler) sont testés un chacun — comparer lequel des deux mécanismes est le plus fun/lisible à la table avant de généraliser

## Questions ouvertes héritées du GDD (rappel)

1. Fin de partie si la défausse recycle en boucle (limite tours/temps, ou victoire uniquement par KO ?)
2. Rebattage ou non de la défausse recyclée (impact sur le comptage de cartes)
3. Déclenchement de l'ultime : manuel confirmé — joker comme piste, à confirmer
4. Blocage mouvement → attaque : esquive pure ou contre avec riposte ?
5. Rôle du joker : universel seul, ou effet signature par champion ?
6. Calibration fine des seuils de blocage/esquive
