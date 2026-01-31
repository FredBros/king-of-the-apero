shader_type canvas_item;

uniform vec4 halo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Effet de pulsation (sinusoidal entre 0 et 1)
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	
	// Détection de contour simple (basée sur l'alpha)
	float alpha = tex_color.a;
	float size = 0.02; // Épaisseur du contour
	
	float outline = 0.0;
	outline += texture(TEXTURE, UV + vec2(size, 0.0)).a;
	outline += texture(TEXTURE, UV - vec2(size, 0.0)).a;
	outline += texture(TEXTURE, UV + vec2(0.0, size)).a;
	outline += texture(TEXTURE, UV - vec2(0.0, size)).a;
	
	// Si le pixel est transparent mais qu'un voisin est opaque, c'est un contour
	float is_outline = max(0.0, outline - 4.0 * alpha);
	is_outline = clamp(is_outline, 0.0, 1.0);
	
	// Calcul final du Halo
	vec3 final_halo = halo_color.rgb;
	float halo_alpha = is_outline * intensity * (0.5 + 0.5 * pulse);
	
	// Mix du halo et de la texture originale
	COLOR = vec4(mix(final_halo, tex_color.rgb, alpha), max(alpha, halo_alpha));
}