shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.5;
uniform float grain_size : hint_range(0.0, 500.0) = 100.0;
uniform float jitter_amount : hint_range(0.0, 0.01) = 0.002;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    // 1. Léger tremblement des UV pour l'effet "tracé à la main"
    // On utilise TIME pour que l'effet soit vivant, ou 0.0 pour du statique
    vec2 noisy_uv = UV + (hash(UV + TIME) - 0.5) * jitter_amount * intensity;
    
    // 2. Récupérer la texture et la couleur
    // FIX: On multiplie par COLOR (Vertex Color) pour supporter draw_line()
    // Pour les lignes, TEXTURE est blanc, COLOR est la couleur du trait.
    vec4 tex_col = texture(TEXTURE, noisy_uv);
    vec4 vert_col = COLOR;
    vec4 col = tex_col * vert_col;
    
    // 3. Générer le grain de la craie
    // FIX: Utiliser FRAGCOORD (Espace Ecran) au lieu de UV car draw_line() n'a pas d'UVs exploitables.
    float grain = hash(FRAGCOORD.xy);
    
    // 4. Supprimer des pixels aléatoirement pour l'effet poreux
    // Plus l'intensité est haute, plus il y a de "trous"
    float mask = step(intensity * 0.4, grain);
    col.a *= mask;
    
    // 5. Couleur "Blanc Craie" (légèrement crème)
    // On force la couleur seulement si le pixel est visible
    if (col.a > 0.0) {
        col.rgb = vec3(0.95, 0.95, 0.9);
    }
    
    COLOR = col;
}