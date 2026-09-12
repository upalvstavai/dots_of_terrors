shader_type spatial;
render_mode cull_disabled, unshaded, fog_disabled;
// fog_disabled: столб света — это светящийся туман, и он ложился ПОВЕРХ массы,
// перекрашивая её в серое. Масса должна оставаться чёрным провалом в луче.
// unshaded — не прихоть. Масса ЧЁРНАЯ при любом свете; если её освещать, солнце
// из дыры превращает струю в серую трубу, а она должна быть провалом в луче.
// Масса, которая льётся сквозь дыру в потолке. Не вода: густая, тёмная, течёт
// рывками. Полосы бегут вниз с разной скоростью, поэтому струя не выглядит
// прокручиваемой картинкой.

uniform vec3 flow_color : source_color = vec3(0.07, 0.075, 0.08);
uniform vec3 edge_color : source_color = vec3(0.24, 0.42, 0.30);
// Насколько нижний край оплывает языками. Ноль — ровный срез.
uniform float melt = 0.0;
// Половина высоты меша: по ней считается, где «низ», который течёт.
uniform float half_h = 0.7;

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

void vertex() {
	// Без раннего return: в вершинном процессоре Godot его не допускает.
	// Языки разной длины по ободу. Струя посередине дыры висела бы в воздухе —
	// литься массе неоткуда, кроме КРАЁВ пролома. Здесь низ цилиндра вытягивается
	// вниз неравномерно, и обод выглядит оплывающим, а не отрезанным.
	float ang = atan(VERTEX.x, VERTEX.z);
	// У каждого языка СВОЯ фаза и своя скорость. Раньше длина шла от шума во
	// времени: язык тянулся вниз, потом полз обратно вверх, и масса не текла, а
	// колыхалась — картинка спорила со звуком течения.
	//
	// Теперь фаза пилообразная: медленно растёт, срывается, растёт заново. Это
	// и есть капание, а не качание.
	float seed = noise(vec3(cos(ang) * 2.6, 0.0, sin(ang) * 2.6));
	float speed = 0.16 + seed * 0.22;
	float ph = fract(seed * 7.13 + TIME * speed);
	float grow = ph < 0.88 ? ph / 0.88 : (1.0 - (ph - 0.88) / 0.12);
	// Границы по возрастанию: smoothstep(0.0, -half_h, y) в GLSL не определён.
	float k = smoothstep(0.0, half_h, -VERTEX.y);
	VERTEX.y -= melt * (0.2 + grow * 1.7) * k;
	// К низу язык сужается — иначе это труба, а не капля.
	VERTEX.xz *= 1.0 - k * 0.16 * step(0.001, melt);
}


void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Три скорости. С одной струя читается как лента, которую тянут.
	float a = noise(vec3(wp.x * 7.0, wp.y * 2.2 - TIME * 2.6, wp.z * 7.0));
	float b = noise(vec3(wp.x * 13.0, wp.y * 5.0 - TIME * 4.1, wp.z * 13.0));
	float c = noise(vec3(wp.x * 26.0, wp.y * 11.0 - TIME * 6.7, wp.z * 26.0));
	float flow = a * 0.55 + b * 0.3 + c * 0.15;
	// Края струи светлее — по ним и видно, что она объёмная.
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(-VERTEX))), 2.5);
	ALBEDO = flow_color * (0.35 + flow * 0.9) + edge_color * rim * (0.10 + flow * 0.30);
}
