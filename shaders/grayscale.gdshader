shader_type canvas_item;

// 1.0 = noir et blanc complet, 0.0 = couleurs originales.
uniform float gray_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(tex_color.rgb, vec3(gray), gray_amount), tex_color.a);
}
