shader_type canvas_item;
// Экран, залитый жижей, когда проходишь под проломом.
//
// Не равномерная плёнка: масса натекает сверху языками, стекает по стеклу и
// тянется вниз. Поэтому непрозрачность считается от того, докуда СПОЛЗ край.

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 goo_color : source_color = vec3(0.03, 0.035, 0.033);
uniform vec3 rim_color : source_color = vec3(0.16, 0.32, 0.22);
// Протирание: 0 — рука не идёт, 1 — уже прошла весь экран. Слева от края
// ладони чисто, у самого края тёмная полоса, справа жижа ещё на месте.
uniform float wipe : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x),
		mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// Край натёка гуляет по горизонтали и медленно ползёт вниз.
	float edge = amount * 1.35
		+ noise(vec2(uv.x * 5.0, TIME * 0.35)) * 0.22 * amount
		+ noise(vec2(uv.x * 17.0, TIME * 0.6)) * 0.09 * amount;
	// Считаем по uv.y напрямую: 0 — верх экрана, оттуда и натекает. Первая
	// версия шла от (1 - uv.y), и при полной заливке край уходил ЗА экран —
	// покрывалось ровно ничего, при том что все числа выглядели верными.
	float cover = 1.0 - smoothstep(edge - 0.14, edge, uv.y);
	// Тонкая светлая кромка по переднему краю натёка: по ней видно, что живое.
	float rim = smoothstep(edge - 0.07, edge - 0.01, uv.y) - smoothstep(edge - 0.01, edge + 0.05, uv.y);
	vec3 col = goo_color + rim_color * rim * 0.7;
	float a = clamp(cover, 0.0, 1.0) * 0.97;
	if (wipe > 0.0) {
		// Рука идёт НАИСКОСЬ, снизу вверх: так по глазам и проводят предплечьем.
		// Ровная вертикальная полоса читалась не рукой, а вторым краем натёка.
		float sweep = uv.x + (uv.y - 0.5) * 0.30;
		float x = wipe * 1.45 - 0.22;
		// Стёрто не начисто: остаются разводы, и сквозь них видно.
		float smear = 0.09 + 0.15 * noise(vec2(uv.y * 9.0 + wipe * 3.0, uv.x * 3.0));
		float keep = smoothstep(x - 0.03, x + 0.08, sweep);
		a *= mix(smear, 1.0, keep);
		// Предплечье: широкая тёмная полоса с мягким передним краем и жёстким
		// задним, плюс более светлая кромка — по ней видно, что это рука, а не
		// ещё одно пятно.
		float body = smoothstep(x - 0.30, x - 0.06, sweep) - smoothstep(x - 0.01, x + 0.07, sweep);
		float edge = smoothstep(x - 0.07, x - 0.02, sweep) - smoothstep(x - 0.02, x + 0.03, sweep);
		float on = smoothstep(0.0, 0.10, wipe) * (1.0 - smoothstep(0.88, 1.0, wipe));
		body *= on;
		edge *= on;
		col = mix(col, vec3(0.020, 0.019, 0.018), body);
		col = mix(col, vec3(0.10, 0.11, 0.10), edge * 0.8);
		a = max(a, max(body, edge) * 0.94);
	}
	COLOR = vec4(col, a);
}
