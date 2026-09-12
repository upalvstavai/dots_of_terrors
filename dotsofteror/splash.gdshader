shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
// Брызги. Кольцо, разбегающееся от точки удара, с неровным краем.
//
// Ровный круг читается как круг из компьютерной игры. Настоящая клякса
// расходится неравномерно, поэтому радиус здесь гуляет по углу — и у каждой
// брызги свой рисунок, потому что искажение завязано на время рождения.

uniform vec3 tint : source_color = vec3(0.22, 0.46, 0.32);
uniform float t0 = 0.0;
uniform float life = 0.55;

void fragment() {
	float age = (TIME - t0) / life;
	vec2 d = UV - vec2(0.5);
	float r = length(d) * 2.0;
	float ang = atan(d.y, d.x);
	// Искажение СЛАБОЕ. При 0.16 кольцо превращалось в семилучевую звезду:
	// колебание съедало всю ширину ободка. Нужна неровность, а не узор.
	float wob = 0.94 + 0.05 * sin(ang * 7.0 + t0 * 11.0) + 0.03 * sin(ang * 13.0 - t0 * 6.0);
	float outer = clamp(age, 0.0, 1.15) * wob;
	// Ободок тонкий и чуть расплывается со временем. И внутренний край НЕ ниже
	// нуля: иначе на первых кадрах он заливал всю середину сплошным пятном.
	float w = 0.07 + age * 0.09;
	float inner = max(outer - w, 0.015);
	// Обе границы по возрастанию: перевёрнутые в GLSL не определены, и я уже
	// дважды на этом попадался за вечер.
	float ring = smoothstep(inner, inner + w * 0.45, r) * (1.0 - smoothstep(outer - w * 0.4, outer, r));
	// Гаснет к концу и не существует до рождения.
	float fade = (1.0 - smoothstep(0.55, 1.0, age)) * step(0.0, age) * (1.0 - step(1.0, age));
	ALBEDO = tint * ring * fade;
}
