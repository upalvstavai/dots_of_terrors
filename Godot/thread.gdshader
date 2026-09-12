shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// Нить от палочки к цели. Не линия в один пиксель, а лента с бегущими метками:
// по ним видно НАПРАВЛЕНИЕ, а не только сам путь.

uniform vec3 tint : source_color = vec3(0.42, 0.30, 0.72);
uniform float speed = 1.6;
uniform float fade_len = 14.0;   // на скольких метрах нить гаснет

void fragment() {
	// UV.x — расстояние вдоль пути в метрах, UV.y — поперёк ленты.
	float across = abs(UV.y - 0.5) * 2.0;
	// Мягкие края: жёсткая лента читается как полоска скотча на полу.
	float band = 1.0 - smoothstep(0.35, 1.0, across);
	// Бегущие метки. Уходят ОТ игрока, поэтому вычитаем время.
	float marks = fract(UV.x * 0.85 - TIME * speed);
	float dash = smoothstep(0.55, 0.85, marks) * (1.0 - smoothstep(0.9, 1.0, marks));
	// Гаснет с расстоянием: нить показывает направление, а не весь маршрут
	// целиком — иначе лабиринт превращается в схему.
	float far = 1.0 - smoothstep(0.0, fade_len, UV.x);
	ALBEDO = tint * band * (0.22 + dash * 1.5) * far;
	ALPHA = 1.0;
}
