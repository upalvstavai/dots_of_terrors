shader_type spatial;
render_mode cull_back, diffuse_burley;
// ТОЧКИ УЖАСА — пол. Та же чёрная масса, что и стены, но лежачая и МОКРАЯ.
//
// Пузыри живут по-настоящему: надуваются, стоят и опадают, каждый в своём
// темпе. Считаются по сетке — у каждой ячейки свой пузырь со своим размером,
// смещением от центра и фазой, поэтому решётки не видно.
//
// Нормаль наклоняется по градиенту той же высоты. Без этого пузыри были бы
// видны только по силуэту у самого края: свет ложился бы на плоскость.

// Отражение почти нулевое. При 0.032 свет палочки давал ровный серый настил:
// масса должна быть ЧЁРНОЙ, а видно её по бликам на макушках пузырей.
uniform vec3 base_color : source_color = vec3(0.017, 0.018, 0.021);
uniform vec3 sheen : source_color = vec3(0.14, 0.30, 0.21);
uniform float madness : hint_range(0.0, 1.0) = 0.0;
uniform float grid = 1.15;        // шаг сетки пузырей, метры
uniform float bub_rise = 0.14;    // на сколько поднимается купол
uniform float wet : hint_range(0.0, 1.0) = 0.72;
// 0 — без наклона нормали. Самая дорогая строчка во всей игре: наклон требует
// ДВУХ лишних выборок поля пузырей на каждый пиксель, то есть утраивает цену
// пола. На слабой машине это первое, что надо гасить.
uniform float relief : hint_range(0.0, 1.0) = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
		f.z);
}

// Высота массы в точке: максимум по девяти соседним пузырям плюс мелкая рябь.
float bubbles(vec2 p) {
	vec2 gi = floor(p / grid);
	float h = 0.0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 c = gi + vec2(float(dx), float(dy));
			float r1 = hash(vec3(c, 1.0));
			float r2 = hash(vec3(c, 7.0));
			vec2 centre = (c + vec2(0.22 + 0.56 * r1, 0.22 + 0.56 * r2)) * grid;
			// Каждый в своём темпе, иначе всё поле дышит разом, как лёгкое.
			float ph = fract(r1 * 3.1 + TIME * (0.05 + r2 * 0.09));
			float life = sin(ph * 3.14159);
			float rad = grid * (0.26 + 0.20 * r2);
			float d = clamp(length(p - centre) / rad, 0.0, 1.0);
			h = max(h, cos(d * 1.5708) * life);
		}
	}
	return h + noise(vec3(p.x * 3.2, TIME * 0.06, p.y * 3.2)) * 0.09;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += bubbles(wp.xz) * bub_rise;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = bubbles(wp.xz);
	if (relief > 0.01) {
		// Наклон нормали по градиенту: две лишние выборки, зато купола ловят свет.
		float e = 0.09;
		vec2 g = vec2(bubbles(wp.xz + vec2(e, 0.0)) - h, bubbles(wp.xz + vec2(0.0, e)) - h) / e;
		vec3 nw = normalize(vec3(-g.x * bub_rise * relief, 1.0, -g.y * bub_rise * relief));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}

	vec3 col = base_color * (0.7 + h * 0.9);
	ALBEDO = col;
	// Плёнка на макушке пузыря: тонкая светлая каёмка, по ней и видно, что мокро.
	float film = smoothstep(0.62, 0.95, h);
	EMISSION = mix(sheen, vec3(0.24, 0.12, 0.36), madness) * film * (0.05 + madness * 0.10);
	// Мокрое отражает. Единственная блестящая поверхность в игре — под ногами.
	ROUGHNESS = mix(0.85, 0.16, wet * (0.45 + h * 0.55));
	SPECULAR = 0.08 + wet * 0.34;
	METALLIC = 0.0;
}
