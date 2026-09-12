#!/usr/bin/env python3
"""Все проверки GDScript разом. Каждая появилась после реальной поломки."""
import re, os, sys
# Список нетипизированных переменных СОБИРАЕТСЯ ИЗ ФАЙЛА, а не задаётся вручную:
# рукописный список одновременно пропускал настоящие ошибки и ругался на
# player_node, который объявлен как Node3D и выводится прекрасно.
def untyped_vars(src):
    out = set(re.findall(r'^var\s+(\w+)\s*$', src, re.M))          # var x
    out |= set(re.findall(r'^var\s+(\w+)\s*=\s*', src, re.M))      # var x = ... без типа
    # ПЕРЕМЕННАЯ ЦИКЛА ПО ЛИТЕРАЛУ МАССИВА — это Variant. Годо не выводит из неё
    # тип, и «var w := f + d2» падает разбором. Ловил такое уже в живом коде.
    out |= set(re.findall(r'\bfor\s+(\w+)\s+in\s*\[', src))
    # И по значениям словаря/массива, взятым через индекс, тип тоже не выводится.
    return out
KW = set('if elif else for while match break continue return pass and or not in is as var const func '
         'signal class_name extends enum static void self true false null await super assert when'.split())
FN = set('''abs absf absi acos asin atan atan2 ceil ceilf clamp clampf cos cosh deg_to_rad ease exp floor floorf
fmod fposmod inverse_lerp is_equal_approx is_inf is_nan is_zero_approx lerp lerpf linear_to_db log max maxf maxi
clampi min minf mini move_toward pingpong posmod pow rad_to_deg randf randf_range randi randi_range randomize remap round
roundf sign signf signi sin sinh smoothstep snapped sqrt str typeof wrapf wrapi len range preload load db_to_linear
print push_warning push_error ceil'''.split())

# Унаследованное от Node/Control/Node3D: объявлять такое не надо.
ENGINE = set('''get_world_3d get_children move_child to_local to_global bool float int export export_group onready size visible position rotation scale
global_position global_transform transform velocity mesh material_override text color
queue_redraw queue_free set_process set_physics_process set_process_unhandled_input add_child
is_physics_processing is_processing seed layer modulate get_process_delta_time get_physics_process_delta_time is_instance_valid
find_child get_node has_node get_parent has_signal look_at move_and_slide move_toward get_viewport
draw_rect draw_circle draw_line draw_polyline draw_string draw_texture_rect draw_arc
get_local_mouse_position set_anchors_preset mouse_filter create_tween get_tree add_theme_color_override
add_theme_font_size_override top_level sorting_offset name emit connect'''.split())

def lines(f):
    return open(f, encoding='utf-8').read().split('\n')

def c_tabs(f):
    return [(i, 'табы вперемешку с пробелами') for i, l in enumerate(lines(f), 1)
            if ' ' in l[:len(l) - len(l.lstrip())] and '\t' in l[:len(l) - len(l.lstrip())]]

def c_indent(f):
    bad, stack, po, depth, cont = [], [0], False, 0, False
    for i, line in enumerate(lines(f), 1):
        code = line.split('#')[0]
        if not line.strip() or line.strip().startswith('#'):
            continue
        if cont:
            cont = code.rstrip().endswith('\\')
            # Заголовок блока может кончаться на строке-продолжении после «\».
            # Та же ловушка, что и со скобками: без этого двоеточие терялось.
            if not cont:
                po = code.rstrip().endswith(':')
            continue
        if depth > 0:
            depth += sum(code.count(c) for c in '([{') - sum(code.count(c) for c in ')]}')
            # Заголовок блока может закончиться на строке-продолжении:
            #   for x in [ ... ,
            #             ... ]:
            # Без этой строки двоеточие тут терялось, и следующая строка тела
            # объявлялась «лишним отступом». Проверялка врала на живом коде.
            if depth <= 0:
                depth = 0
                po = code.rstrip().endswith(':')
            continue
        ind = len(line) - len(line.lstrip('\t'))
        if po:
            if ind <= stack[-1]: bad.append((i, 'после ":" нет отступа'))
            else: stack.append(ind)
        else:
            if ind > stack[-1]: bad.append((i, 'лишний отступ'))
            while len(stack) > 1 and ind < stack[-1]: stack.pop()
            if ind != stack[-1]: bad.append((i, 'уровень отступа не совпал'))
        depth = max(0, sum(code.count(c) for c in '([{') - sum(code.count(c) for c in ')]}'))
        po = depth == 0 and code.rstrip().endswith(':')
        cont = code.rstrip().endswith('\\')
    return bad

def c_infer(f):
    src = open(f, encoding='utf-8').read()
    names = untyped_vars(src)
    if not names:
        return []
    pat = re.compile(r'\b(' + '|'.join(sorted(names)) + r')\b')

    def strip_calls(x):
        """Убрать содержимое скобок: тип выражения задаёт вызов, а не аргументы.
        Vector3(sz, 1, 1) — это Vector3, сколько бы Variant ни лежало внутри."""
        out, depth = [], 0
        for ch in x:
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth = max(0, depth - 1)
            elif depth == 0:
                out.append(ch)
        return ''.join(out)

    bad = []
    for i, l in enumerate(lines(f), 1):
        m = re.search(r'var\s+\w+\s*:=\s*(.+?)\s*(?:#.*)?$', l.split('#')[0])
        if not m:
            continue
        hit = pat.search(strip_calls(m.group(1)))
        if hit:
            bad.append((i, ':= от нетипизированного (' + hit.group(1) + ') — укажи тип'))
    return bad

def c_names(f):
    src = '\n'.join(re.sub(r'"[^"]*"', '""', l.split('#')[0]) for l in lines(f))
    decl = set(re.findall(r'\b(?:var|const)\s+(\w+)', src)) | set(re.findall(r'\bfunc\s+(\w+)', src))
    decl |= set(re.findall(r'\bsignal\s+(\w+)', src)) | set(re.findall(r'\bfor\s+(\w+)\s+in\b', src))
    # параметры функций, лямбд и сигналов
    for pr in re.findall(r'func\s*\w*\s*\(([^)]*)\)', src) + re.findall(r'signal\s+\w+\s*\(([^)]*)\)', src):
        for x in pr.split(','):
            n = x.split(':')[0].split('=')[0].strip()
            if n: decl.add(n)
    used = re.findall(r'\b([a-z_][a-z0-9_]*)\b', re.sub(r'\.\s*\w+', '.', src))
    return [(0, 'нет имени: ' + u) for u in sorted(set(used))
            if u not in decl and u not in KW and u not in FN and not u.startswith('_')
            and u not in ENGINE]

def c_selfcalls(files):
    """Вызовы собственных методов файла: _foo() должен быть объявлен здесь же.
    Раньше проверка пропускала всё, что начинается с подчёркивания, — а именно
    там и живут опечатки в именах методов и следы неудачных правок."""
    out = []
    for f in files:
        src = open(f, encoding='utf-8').read()
        have = set(re.findall(r'^(?:static\s+)?func\s+(_\w+)', src, re.M))
        have |= set(re.findall(r'^(?:@export )?(?:static\s+)?(?:const|var)\s+(_\w+)', src, re.M))
        body = re.sub(r'^\s*#.*$', '', src, flags=re.M)
        for m in sorted(set(re.findall(r'(?<![\w.])(_\w+)\s*\(', body))):
            if m in have or m in KW or m in ENGINE or m in FN:
                continue
            if m.startswith('__'):
                continue
            out.append((f, 'нет своего метода: ' + m))
    return out

def c_dupes(files):
    out = []
    for f in files:
        src = open(f, encoding='utf-8').read()
        seen = {}
        for m in re.finditer(r'^(?:static\s+)?func\s+(\w+)', src, re.M):
            n = m.group(1)
            line = src[:m.start()].count(chr(10)) + 1
            if n in seen:
                out.append((f, 'функция %s объявлена дважды: строки %d и %d' % (n, seen[n], line)))
            else:
                seen[n] = line
    return out

def c_refs(files):
    decl = {}
    for f in files:
        src = open(f, encoding='utf-8').read()
        decl[f] = (set(re.findall(r'^(?:@export )?(?:static\s+)?(?:const|var)\s+(\w+)', src, re.M))
                   | set(re.findall(r'^(?:static\s+)?func\s+(\w+)', src, re.M))
                   | set(re.findall(r'^signal\s+(\w+)', src, re.M)))
    out = []
    for f in files:
        src = open(f, encoding='utf-8').read()
        # Комментарии вырезаем: упоминание файла в пояснении — не вызов.
        clean = re.sub(r'#.*$', '', src, flags=re.M)
        clean = re.sub(r'preload\("[^"]*"\)', 'preload()', clean)
        for alias, path in re.findall(r'const\s+(\w+)\s*:=\s*preload\("res://([\w.]+)"\)', src):
            if path not in decl: continue
            for u in sorted(set(re.findall(r'\b' + alias + r'\.(\w+)', clean))):
                if u not in decl[path] and u != 'new':
                    out.append((f, f'{alias}.{u} — нет в {path}'))
    return out

files = sorted(x for x in os.listdir('.') if x.endswith('.gd'))
bad = False
for f in files:
    probs = []
    for name, fn in (('табы', c_tabs), ('отступы', c_indent), ('вывод типов', c_infer), ('имена', c_names)):
        for i, msg in fn(f):
            # известные ложные срабатывания: перенос строки через \
            if name == 'отступы' and any(l.rstrip().endswith('\\') for l in lines(f)[max(0, i - 3):i]):
                continue
            probs.append(f'{i}: {msg}' if i else msg)
    print(f'{f:<14} {"; ".join(probs[:4]) if probs else "чисто"}')
    if probs: bad = True
for f, msg in c_refs(files) + c_dupes(files) + c_selfcalls(files):
    print(f'{f:<14} {msg}'); bad = True
print()
print('ВСЁ ЧИСТО' if not bad else 'ЕСТЬ ЗАМЕЧАНИЯ')
sys.exit(1 if bad else 0)
