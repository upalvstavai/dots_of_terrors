shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// fog_disabled обязателен. Туман накладывается и на прозрачные поверхности, и
// весь прямоугольник проявлялся серой заплатой вокруг глаз — видно было рамку,
// а не взгляд.
// Глаза, которые открываются прямо в стене. Не наклейка: ничего не отражают,
// только светятся — потому и видны в темноте, где больше не видно ничего.

uniform vec3 eye_color : source_color = vec3(0.90, 0.16, 0.11);
uniform float t0 = 0.0;      // когда открылись
uniform float life = 3.2;    // сколько живут

float lens(vec2 uv, vec2 c, float open) {
	vec2 d = (uv - c) / vec2(0.105, 0.070 * open + 0.006);
	return smoothstep(1.0, 0.28, length(d));
}

void fragment() {
	float age = TIME - t0;
	// Моргание редкое и БЫСТРОЕ. Плавное закрывание читается как засыпание,
	// а не как взгляд.
	float open = 1.0 - pow(abs(sin(age * 1.9)), 26.0);
	// Появляются и исчезают не мгновенно: мгновенное чтается как сбой картинки.
	// НЕ smoothstep(life, life-0.7, age): в GLSL перевёрнутые границы не
	// определены — приём из GDScript, где так можно. Здесь получался ноль,
	// и глаза не рисовались вообще.
	float fade = smoothstep(0.0, 0.45, age) * (1.0 - smoothstep(life - 0.7, life, age));
	float e = lens(UV, vec2(0.36, 0.5), open) + lens(UV, vec2(0.64, 0.5), open);
	// Зрачок темнее — иначе это два фонаря, а не глаза.
	float pup = lens(UV, vec2(0.36, 0.5), open * 0.42) + lens(UV, vec2(0.64, 0.5), open * 0.42);
	ALBEDO = eye_color * clamp(e - pup * 0.55, 0.0, 1.0) * fade;
	ALPHA = 1.0;
}
