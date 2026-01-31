shader_type canvas_item;

uniform vec4 halo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 5.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.0;
uniform float margin : hint_range(0.0, 0.5) = 0.25; // Marge augmentée pour éviter de couper l'aura
uniform float halo_width : hint_range(0.0, 0.3) = 0.12; // Taille triplée (0.04 -> 0.12)

void fragment() {
	// 1. Redimensionner les UVs pour créer une marge autour de la texture
	float scale = 1.0 + margin * 2.0;
	vec2 scaled_uv = (UV - 0.5) * scale + 0.5;
	
	vec4 tex_color = vec4(0.0);
	if (scaled_uv.x >= 0.0 && scaled_uv.x <= 1.0 && scaled_uv.y >= 0.0 && scaled_uv.y <= 1.0) {
		tex_color = texture(TEXTURE, scaled_uv);
	}
	
	float alpha = tex_color.a;
	
	// Effet de respiration : La pulsation affecte la taille de l'aura
	float pulse = (sin(TIME * pulse_speed) + 1.0) * 0.5;
	float current_width = halo_width * scale * (0.8 + 0.3 * pulse); 
	
	float glow = 0.0;
	
	// 2. Sampling sur 3 anneaux pour créer un dégradé (Aura douce)
	// On fait tourner un vecteur pour échantillonner autour du pixel
	for (float i = 0.0; i < 6.28; i += 0.785) { // 8 directions (step ~PI/4)
		vec2 dir = vec2(cos(i), sin(i));
		
		// Anneau 1 (Proche) : Fort
		vec2 uv1 = scaled_uv + dir * current_width * 0.33;
		if (uv1.x >= 0.0 && uv1.x <= 1.0 && uv1.y >= 0.0 && uv1.y <= 1.0) 
			glow += texture(TEXTURE, uv1).a;
			
		// Anneau 2 (Moyen) : Moyen
		vec2 uv2 = scaled_uv + dir * current_width * 0.66;
		if (uv2.x >= 0.0 && uv2.x <= 1.0 && uv2.y >= 0.0 && uv2.y <= 1.0) 
			glow += texture(TEXTURE, uv2).a * 0.6;
			
		// Anneau 3 (Loin) : Faible (Transparence extérieure)
		vec2 uv3 = scaled_uv + dir * current_width * 1.0;
		if (uv3.x >= 0.0 && uv3.x <= 1.0 && uv3.y >= 0.0 && uv3.y <= 1.0) 
			glow += texture(TEXTURE, uv3).a * 0.3;
	}
	
	// Normalisation approximative (Somme des poids max ~15)
	glow /= 12.0; 
	glow = clamp(glow, 0.0, 1.0);
	
	// On ne garde que l'extérieur de la carte
	float final_alpha = glow * (1.0 - alpha);
	
	// Application de l'intensité
	final_alpha *= intensity;
	
	vec3 final_halo = halo_color.rgb;
	COLOR = vec4(mix(final_halo, tex_color.rgb, alpha), max(alpha, final_alpha));
}