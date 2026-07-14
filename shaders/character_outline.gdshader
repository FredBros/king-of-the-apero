shader_type canvas_item;

// Contour pixel-perfect : sample les 4 voisins directs dans l'espace texture (pas écran),
// pour rester net quel que soit le scale du Sprite2D.
uniform vec4 outline_color : source_color = vec4(0.196, 0.196, 0.196, 1.0); // #323232
uniform float outline_width : hint_range(0.0, 4.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);

	if (tex_color.a > 0.5) {
		COLOR = tex_color;
	} else {
		vec2 texel = TEXTURE_PIXEL_SIZE * outline_width;
		float neighbor_alpha = 0.0;
		neighbor_alpha += texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV - vec2(texel.x, 0.0)).a;
		neighbor_alpha += texture(TEXTURE, UV + vec2(0.0, texel.y)).a;
		neighbor_alpha += texture(TEXTURE, UV - vec2(0.0, texel.y)).a;

		if (neighbor_alpha > 0.0) {
			COLOR = vec4(outline_color.rgb, 1.0);
		} else {
			COLOR = tex_color;
		}
	}
}
