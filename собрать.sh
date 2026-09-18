#!/bin/bash
# СБОРКА «ТОЧЕК УЖАСА»: четыре пакета, с проверкой и с уборкой за собой.
#
# Почему скриптом, а не руками. Один раз я собрал свежий срез в новую папку, а
# в Downloads остался одноимённый старый — играющий открыл его и сказал, что
# ничего не починено. Другой раз в пакет не попали записи шагов, и банк собрался
# из синтеза: в редакторе всё звучало, в сборке — шипело.
#
# Отсюда три правила, и все три здесь:
#   1. старое сносится ДО сборки, чтобы двойников не было физически;
#   2. собирается по тем путям, которые человек открывает;
#   3. проверка идёт ВНУТРИ собранного приложения, а не в редакторе.

set -e
GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
PROJ="$(cd "$(dirname "$0")" && pwd)/dotsofteror"
OUT="$HOME/Downloads"

echo "══ 1. СНОСИМ СТАРОЕ ══"
for p in "$OUT/DotsOfTerror" "$OUT/DotsOfTerror_mac" "$OUT/SrezWindows" \
         "$OUT/SrezMac" "$OUT/Срез.app" "$(dirname "$PROJ")/build"; do
    for dup in "$p" "$p 2" "$p 3" "$p 4" "$p 5"; do
        if [ -e "$dup" ]; then
            echo "  убрано: $dup ($(du -sh "$dup" | cut -f1))"
            rm -rf "$dup"
        fi
    done
done
rm -f "$OUT/ТочкиУжаса_Windows.zip" "$OUT/ТочкиУжаса_macOS.zip" \
      "$OUT/Срез_Windows.zip" "$OUT/Срез_macOS.zip"

echo "══ 2. СОБИРАЕМ ══"
mkdir -p "$OUT/DotsOfTerror" "$OUT/DotsOfTerror_mac" "$OUT/SrezWindows"
"$GODOT" --headless --path "$PROJ" --export-release "Windows" \
    "$OUT/DotsOfTerror/DotsOfTerror.exe" > /dev/null
"$GODOT" --headless --path "$PROJ" --export-release "Срез Windows" \
    "$OUT/SrezWindows/DotsOfTerror.exe" > /dev/null
"$GODOT" --headless --path "$PROJ" --export-release "macOS" \
    "$OUT/DotsOfTerror_mac/DotsOfTerror.app" > /dev/null
"$GODOT" --headless --path "$PROJ" --export-release "Срез macOS" \
    "$OUT/Срез.app" > /dev/null
echo "  собрано четыре пакета"

echo "══ 3. ПРОВЕРЯЕМ ВНУТРИ СБОРОК ══"
bad=0
check() {   # $1 — путь к .app, $2 — как называется
    local out
    out=$("$1/Contents/MacOS/dotsofteror" --resolution 640x360 --max-fps 60 \
        -- бот изкомнаты опись 2>/dev/null || true)   # Годот дублирует вывод в stderr
    echo "$out" | grep -E "звуки на месте|подмен|СИНТЕЗ|неполные|карта \(" \
        | sed "s/^/  [$2] /"
    if echo "$out" | grep -q "СИНТЕЗ"; then
        echo "  !!! [$2] в пакет не попали записи — банки собрались из синтеза"
        bad=1
    fi
    if ! echo "$out" | grep -q "звуки на месте"; then
        echo "  !!! [$2] стенд не отозвался — сборка не запустилась"
        bad=1
    fi
}
check "$OUT/DotsOfTerror_mac/DotsOfTerror.app" "полная"
check "$OUT/Срез.app" "срез"
if [ "$bad" != "0" ]; then
    echo "══ СБОРКА НЕ ГОДИТСЯ, архивы не делаю ══"
    exit 1
fi

echo "══ 4. ПАКУЕМ ══"
( cd "$OUT/DotsOfTerror" && zip -qr9 "$OUT/ТочкиУжаса_Windows.zip" . -x ".*" )
( cd "$OUT/SrezWindows" && zip -qr9 "$OUT/Срез_Windows.zip" . -x ".*" )
ditto -c -k --sequesterRsrc --keepParent "$OUT/DotsOfTerror_mac" \
    "$OUT/ТочкиУжаса_macOS.zip"
# Срезу нужна записка рядом с приложением, а само приложение лежит в Downloads.
tmpd=$(mktemp -d)
ditto "$OUT/Срез.app" "$tmpd/Срез.app"
[ -f "$OUT/SrezWindows/СРЕЗ-ЧИТАЙ.txt" ] && cp "$OUT/SrezWindows/СРЕЗ-ЧИТАЙ.txt" "$tmpd/"
ditto -c -k --sequesterRsrc --keepParent "$tmpd" "$OUT/Срез_macOS.zip"
rm -rf "$tmpd"

echo "══ ГОТОВО ══"
ls -lah "$OUT"/ТочкиУжаса_Windows.zip "$OUT"/ТочкиУжаса_macOS.zip \
        "$OUT"/Срез_Windows.zip "$OUT"/Срез_macOS.zip | awk '{print "  " $9, $5, $7, $8}'
echo "  играть отсюда: $OUT/Срез.app и $OUT/DotsOfTerror_mac/DotsOfTerror.app"
