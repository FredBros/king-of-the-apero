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
    // On définit la taille (0.4 pour laisser une marge de flou autour, car UV va de -0.5 à 0.5)
    float d = sdRoundedBox(p, vec2(0.4), radius);
    
    // On crée un fondu doux à partir du bord du rectangle
    // smoothstep(edge0, edge1, x) -> interpolation
    float mask = smoothstep(0.05, -0.1, d);
    
    // 2. Ajouter le bruit animé (l'effet de flamme/fumée)
    vec2 moving_uv = UV + vec2(TIME * speed * 0.1, TIME * speed * 0.2);
    float noise = texture(noise_tex, moving_uv).r;
    
    // 3. Fusion finale
    // On multiplie le masque par le bruit et l'intensité
    float alpha = mask * noise * intensity;
    
    // On applique la couleur avec l'alpha calculé
    COLOR = vec4(aura_color.rgb, alpha * aura_color.a);
}