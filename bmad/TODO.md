Tuto : On va maintenant se concentrer sur le tutorial du jeu.
Il existe deja un tuto texte (tuto_layer) qui servait de placeHolder, mais, sans surprise personne le lit.
On va reflechir a la mise en place d'un tuto en jeu .
On n'agit pas sur le code  pour l'instant.
Je voudrai un tutorial modulaire a base d'infobulles qui pop pour expliquer chaque mecanique jeu.
Je veux un tuto modulaire, chaque infobulle est un composant, Un composant a part servira de chef d'orchestre et testera pour savoir quelle infobulle afficher.
Il faut aussi un moyen de tracker quelles infobulles ont été activée ou pas, pour ne pas proposer plusieures fois e suite la meme infobulle.
Il faudra un composant infobulle general flexible dans lequel on pourra definir du texte, des images, une video ou un GIF, des boutons de fermeture / next, et une position pour faire pop la fenetre.

Voila l'idée :
On arrive en jeu. Presentation rapide : deck commun de 52 cartes, on joue autant de 