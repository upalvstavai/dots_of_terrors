#!/bin/bash
# СЪЁМКА ЛЕНТ «ТОЧЕК УЖАСА»: четыре ролика, с уборкой за собой.
#
# Почему скриптом, а не руками. Ленты снимались вручную, и каждый раз я заново
# вспоминал ключи Годо, частоту кадров и настройки ffmpeg. А главное — рядом
# копились старые mp4 с теми же именами, и отличить вчерашний ролик от
# сегодняшнего можно было только по времени файла.
#
# Правила те же, что у сборки:
#   1. старое сносится ДО съёмки, чтобы двойников не было физически;
#   2. снимается в те же файлы, которые человек потом открывает;
#   3. после каждой ленты проверяется, что файл вообще получился и не пустой.
#
# Что снимаем:
#   Ролик.mp4          — полная лента, девять актов, около двух минут
#   Ролик_английский   — она же по-английски
#   Тизер.mp4          — короткая, чтобы позвать зрителя, без добивания
#   Магазин.mp4        — версия для страницы в Steam, сильное впереди
#
# У каждой ленты делается ещё «_лёгкий»: тот же ролик, но в разы меньше —
# такой уходит в мессенджер, а полный остаётся для загрузки.

set -e
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
PROJ="$(cd "$(dirname "$0")" && pwd)/dotsofteror"
OUT="$HOME/Downloads/ТочкиУжаса_ролики"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "══ 1. СНОСИМ СТАРОЕ ══"
for dup in "$OUT" "$OUT 2" "$OUT 3" "$OUT 4"; do
    if [ -e "$dup" ]; then
        echo "  убрано: $dup ($(du -sh "$dup" | cut -f1))"
        rm -rf "$dup"
    fi
done
rm -f "$HOME/Downloads/ТочкиУжаса_ролики.zip"
mkdir -p "$OUT"

# снять <имя файла> <ключи площадки...>
# ВНУТРИ — ТОЛЬКО ЛАТИНИЦА. bash не умеет кириллических имён переменных:
# `local имя=...` он разбирает как «not a valid identifier» и молча роняет
# функцию. На этом я уже горел в сборочном скрипте.
snyat() {
    local name="$1"; shift
    echo "  снимаю: $name"
    # --fixed-fps держит ровно шестьдесят кадров вне зависимости от того, с
    # какой скоростью машина успевает считать: иначе на тяжёлых актах лента
    # замедляется, а на лёгких летит.
    "$GODOT" --path "$PROJ" --resolution 1920x1080 --fixed-fps 60 \
        --write-movie "$TMP/$name.avi" res://stage.tscn -- запись "$@" \
        > /dev/null 2>&1 || true
    if [ ! -s "$TMP/$name.avi" ]; then
        echo "  !!! [$name] файла нет — лента не снялась"
        return 1
    fi
    # AVI от Годо — это MJPEG: честный, но огромный. Полная версия h264 с
    # хорошим качеством, лёгкая — вдвое меньше по стороне и жёстче по битрейту.
    ffmpeg -y -i "$TMP/$name.avi" -c:v libx264 -preset slow -crf 18 \
        -pix_fmt yuv420p -c:a aac -b:a 192k "$OUT/$name.mp4" > /dev/null 2>&1
    ffmpeg -y -i "$TMP/$name.avi" -vf scale=1280:-2 -c:v libx264 -preset slow \
        -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k \
        "$OUT/${name}_лёгкий.mp4" > /dev/null 2>&1
    rm -f "$TMP/$name.avi"
    local secs
    secs=$(ffprobe -v error -show_entries format=duration -of csv=p=0 \
        "$OUT/$name.mp4" 2>/dev/null | cut -d. -f1)
    echo "      $name.mp4 — ${secs} с, $(du -h "$OUT/$name.mp4" | cut -f1)" \
        "| лёгкий $(du -h "$OUT/${name}_лёгкий.mp4" | cut -f1)"
}

echo "══ 2. СНИМАЕМ ══"
snyat "Ролик"
snyat "Ролик_английский" англ
snyat "Тизер" тизер
snyat "Магазин" магазин

echo "══ 3. ПРОВЕРЯЕМ ══"
bad=0
for f in "$OUT"/*.mp4; do
    secs=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" \
        2>/dev/null | cut -d. -f1)
    snd=$(ffprobe -v error -select_streams a -show_entries stream=codec_type \
        -of csv=p=0 "$f" 2>/dev/null | head -1)
    if [ -z "$secs" ] || [ "$secs" -lt 3 ]; then
        echo "  !!! $(basename "$f") короче трёх секунд — брак"
        bad=1
    fi
    if [ "$snd" != "audio" ]; then
        echo "  !!! $(basename "$f") без звука"
        bad=1
    fi
done
[ "$bad" = "0" ] && echo "  все ленты со звуком и нужной длины"

echo "══ ГОТОВО ══"
ls -lah "$OUT"/*.mp4 | awk '{print "  " $9, $5}'
echo "  смотреть отсюда: $OUT"
