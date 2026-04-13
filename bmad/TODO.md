Tuto : On va maintenant se concentrer sur le tutorial du jeu.
Il existe deja un tuto texte (tuto_layer) qui servait de placeHolder, mais, sans surprise personne le lit.
On va reflechir a la mise en place d'un tuto en jeu . 
Un tuto souple (agile ? :D), abordable, et discret.
On n'agit pas sur le code  pour l'instant.
Je voudrai un tutorial modulaire a base d'infobulles qui pop pour expliquer chaque mecanique jeu. La base de l'infobulle est \scenes\UI\Tutorial\TutoTooltip.tscn et scripts\UI\Tutorial\TutoTooltip.gd. On utilisera un ChalkPanel scenes\UI\Components\ChalkPanel.tscn
Il faut aussi un moyen de tracker quelles infobulles ont été activée ou pas, pour ne pas proposer plusieures fois de suite la meme infobulle.
Il faudra un composant infobulle general flexible dans lequel on pourra definir du texte, des images, une video ou un GIF, des boutons de fermeture / next, stoper le tuto, et une position pour faire pop la fenetre.
Un composant a part servira de chef d'orchestre et testera pour savoir quelle infobulle afficher. scripts\UI\Tutorial\Tutorial.gd et scenes\UI\Tutorial\Tutorial.tscn 

Voila l'idée :
On arrive en jeu. Presentation rapide avec plusieures infobulles : deck commun de 52 cartes, 5 cartes en main maxi, on joue autant de cartes qu'on veut.

On propose de jouer une carte mouvement en cliquant sur la carte et en cliquant sur la case destination(deplacement intuitif). On explique les fleches, le deplacement d'une seule case.
Si on a une autre carte deplacement, on explique le swipe pour se deplacer (cette feature n'est pas intuitive, mais les testeurs l'adoptent vite)
On explique le changement de tour.
Les combats, les poussée, les blocages (il faudra mettre en pose le jeu lors de cette explication)
etc....

Cependant :
Il ne faut pas que les tooltips s'enchainent du premier au dernier.
Il faut traquer quels tooltips restent a afficher, et verifier avant d'afficher un tooltip si il est coherent avec la situation.
Par exemple : 
Si la premiere main est pleine de cartes rouges, il faut commencer par expliquer les cartes attaques, leur statut grisé, la penalité AFK et du coup, la poubelle ou jeter des cartes.

Evidemment tout est localisé avec le fichier resources\translations\translations.csv

Voila l'idée. Si c'est clair dans ma tete, la façon de proceder est un peu confuse. Surtout la serie de test, et comment elaborer l'arbre de comportement du tuto.

Pour l'instant, on n'interveint pas dans le code.
Tu en penses quoi ? Quelle est la meilleure façon d'aborder cette feature primordiale : Si un nouveau venu ne pige pas le jeu, il y jouera plus. La qualité du tuto est vitale. Meme si le jeu est conçu pour jouer cote a cote a l'apero.


