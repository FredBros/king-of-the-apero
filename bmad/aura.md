Voici un guide technique clair et fonctionnel pour créer cette **aura en carré arrondi** (Rounded Box) sans aucune image externe, directement dans Godot.

### 1. Le Code du Shader

Ce shader remplace le "cercle" par une formule mathématique de rectangle arrondi.

Crée un nouveau fichier shader (ex: `aura_sous_bock.gdshader`) et colle ceci :

```glsl
shader_type canvas_item;

uniform vec4 aura_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform sampler2D noise_tex : repeat_enable;
uniform float intensity : hint_range(0.0, 5.0) = 2.0;
uniform float speed : hint_range(0.0, 2.0) = 0.5;
uniform float radius : hint_range(0.0, 0.5) = 0.2; // Rayon de l'arrondi

// Fonction pour calculer un rectangle arrondi (SDF)
float sdRoundedBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void fragment() {
    // Centrer les UV pour le calcul du rectangle (-0.5 à 0.5)
    vec2 p = UV - 0.5;
    
    // 1. Créer le masque de base (Rectangle arrondi)
    // On définit la taille (0.4 pour laisser une marge de flou)
    float d = sdRoundedBox(p, vec2(0.4), radius);
    
    // On crée un fondu doux à partir du bord du rectangle
    float mask = smoothstep(0.1, -0.2, d);
    
    // 2. Ajouter le bruit animé (l'effet de flamme/fumée)
    vec2 moving_uv = UV + vec2(TIME * speed * 0.1, TIME * speed * 0.2);
    float noise = texture(noise_tex, moving_uv).r;
    
    // 3. Fusion finale
    // On multiplie le masque par le bruit et l'intensité
    float alpha = mask * noise * intensity;
    
    // On applique la couleur avec l'alpha calculé
    COLOR = vec4(aura_color.rgb, alpha * aura_color.a);
}

```

### 2. Mise en place dans Godot

1. **Le Nœud :** Ajoute un `ColorRect` comme enfant de ton container de carte. Place-le **au-dessus** de ton Sprite de carte dans l'arbre (pour qu'il apparaisse derrière visuellement) ou règle son `Z Index`.
2. **Taille :** Fais en sorte que le `ColorRect` soit légèrement plus grand que ton sous-bock (par exemple 600x600 si ta carte fait 512x512) pour que l'aura puisse dépasser.
3. **Le Matériau :**
* Dans l'inspecteur du `ColorRect`, va dans **Material** > **New ShaderMaterial**.
* Glisse le fichier `.gdshader` créé plus haut.


4. **Le Bruit (Texture) :**
* Dans les paramètres du Shader (`Shader Parameters`), clique sur `Noise Tex` > **New NoiseTexture2D**.
* Dans la NoiseTexture2D, coche **Seamless** (indispensable !).
* Clique sur `Noise` > **New FastNoiseLite**. Règle le `Frequency` à `0.05` pour un effet de fumée fluide.



### 3. Pourquoi c'est parfait pour ton projet ?

* **Adaptabilité :** Tu peux changer `aura_color` en rouge (Attaque) ou noir/violet (Mouvement) instantanément par code.
* **Performance :** C'est une seule passe de calcul GPU très simple, bien plus léger sur smartphone qu'une animation de 30 images.
* **Design :** Le paramètre `radius` te permet de caler l'arrondi de l'aura pile sur celui de ton design de sous-bock.

### 4. Piloter l'aura par code

Si tu veux activer l'aura seulement quand la carte est jouable ou sélectionnée :

```gdscript
# Exemple sur ton nœud de carte
func set_aura_active(active: bool):
    var target_intensity = 2.0 if active else 0.0
    # On anime l'intensité pour un effet fluide
    var tween = create_tween()
    tween.tween_property($ColorRect.material, "shader_parameter/intensity", target_intensity, 0.3)

```

Est-ce que cette fois-ci le guide te semble plus clair pour ton intégration ?