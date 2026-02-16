# UI Reference - King of the Apero

## Direction Artistique : "Chalkboard" (Tableau Noir)
L'interface doit évoquer un plan de match ou un menu de bar dessiné à la craie sur un tableau noir.

## 1. Palette de Couleurs

| Usage | Code Hex | Description |
| :--- | :--- | :--- |
| **Fond (Background)** | `#181425` | Violet très sombre / Noir profond. Couleur de fond des panneaux et fenêtres. |
| **Premier Plan (Foreground)** | `#ffffff` | Blanc Craie. Utilisé pour le texte, les icônes et les contours. |

## 2. Typographie
*   **Police :** Conserver la police actuelle (Bangers ou équivalent).
*   **Couleur :** `#ffffff`.
*   **Effet :** Appliquer le shader `chalk.gdshader`.

## 3. Iconographie
*   **Source :** Les assets fournis sont en Noir.
*   **Traitement Godot :** Utiliser la propriété `modulate` (ou `self_modulate`) pour les passer en `#ffffff`.
*   **Effet :** Appliquer le shader `chalk.gdshader`.

## 4. Contours & Formes (Boutons / Fenêtres)

### Style "Coins Croisés" (Crossed Corners)
Au lieu d'un contour classique (`StyleBoxFlat` border), nous utilisons un style architectural spécifique :

*   **Épaisseur du trait :** 2px.
*   **Couleur du trait :** `#ffffff`.
*   **Arrondi :** Aucun (0px radius).
*   **Géométrie :**
    *   Les lignes sont décalées vers l'intérieur (Inset) de **5px** par rapport au bord du conteneur.
    *   Cependant, la longueur des lignes correspond à **100%** de la largeur/hauteur du conteneur.
    *   **Résultat visuel :** Les lignes se croisent aux 4 coins, créant un dépassement de 5px à chaque intersection.

### Implémentation Technique Suggérée
Puisque le `StyleBoxFlat` ne permet pas nativement de faire dépasser les bordures (le border suit le content rect), deux approches sont possibles :
1.  **Custom Draw (`_draw`) :** Un script attaché au composant UI qui dessine 4 lignes (`draw_line`) avec les coordonnées calculées.
2.  **NinePatchRect :** Une texture pré-dessinée avec les coins croisés, étirée correctement.

*Note : L'approche `_draw` est préférable pour appliquer le shader de craie proprement sur les lignes générées.*

## 5. Shaders & Effets

### Shader Craie (`chalk.gdshader`)
Doit être appliqué via un `ShaderMaterial` sur :
1.  Les Labels (Texte).
2.  Les TextureRect / TextureButton (Icônes).
3.  Les composants de bordure (Lignes blanches).

*Le fond (`#181425`) ne reçoit PAS le shader de craie, il reste uni pour simuler l'ardoise.*