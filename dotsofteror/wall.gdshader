shader_type spatial;
render_mode cull_back, diffuse_burley;
// ТОЧКИ УЖАСА — камень стен.
//
// Плоские серые коробки нельзя «испортить»: у них нет формы, которой меняться.
// Поэтому поверхность получает рельеф и медленное дыхание, а безумие
// усиливает и то и другое. Тогда рост безумия видно, а не читаешь в углу.

uniform vec3 base_color : source_color = vec3(0.36, 0.36, 0.38);
uniform vec3 mad_color : source_color = vec3(0.16, 0.26, 0.18);
uniform float madness : hint_range(0.0, 1.0) = 0.0;   // 0 — лабиринт спокоен, 1 — потолок
uniform float breathe = 0.022;                         // амплитуда шевеления, метры
uniform float grain_amt : hint_range(0.0, 1.0) = 0.35; // насколько заметна крошка

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(
		mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y),
		f.z);
	return n;
}

void vertex() {
	// Дышит медленно и неравномерно. Быстрое шевеление читается как «глюк»,
	// медленное — как «оно живое».
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.35;
	float n = noise(wp * 0.55 + vec3(0.0, t, 0.0)) - 0.5;
	float amp = breathe * (0.3 + madness * 1.6);
	VERTEX += NORMAL * n * amp;
}

void fragment() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// КРУПНОЕ важнее мелкого. Первая версия давила высокой частотой (шум ×9),
	// и получалась рябь без ориентиров: глазу не за что зацепиться, движение
	// не читается, и кажется, что стоишь на месте, как в зеркальной комнате.
	// Теперь ведёт крупная кладка, а крошка только подмешана.
	float big = noise(wp * 0.45);          // крупные пятна — по ним видно, что идёшь
	float mid = noise(wp * 1.8);
	float fine = noise(wp * 6.0);
	float grain = big * 0.6 + mid * 0.3 + fine * 0.1;
	vec3 col = mix(base_color, mad_color, madness);
	col *= 0.86 + (grain - 0.5) * grain_amt;
	// прожилки: с ростом безумия камень начинает светиться изнутри
	float vein = smoothstep(0.70, 0.92, noise(wp * 1.2 + vec3(0.0, TIME * 0.10, 0.0)));
	ALBEDO = col;
	EMISSION = vec3(0.08, 0.5, 0.22) * vein * madness * 0.35;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
