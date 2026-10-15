#!/bin/bash
# Tests for the artwork tools: svgcheck against itself, and vectorfit on
# pictures whose answer is known - each known-*.svg is rendered to a bitmap,
# fitted with the same shapes, and must come back nearly exact.
#
#   tools/vectorize/tests/run-tests.sh <build dir with svgcheck and vectorfit>
set -e
cd "$(dirname "$0")"
B=${1:?usage: run-tests.sh <build dir>}
B=$(cd "$B" && pwd)
mkdir -p out
fail=0
pass() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fail=1; }

# svgcheck: a render compared with itself is exact; scale 2 doubles the size.
"$B/svgcheck" render known-button.svg 1 out/self.png
r=$("$B/svgcheck" compare known-button.svg out/self.png)
case "$r" in "max 0  exact 100.00%"*) pass "svgcheck: a render matches its SVG exactly" ;; *) bad "svgcheck self" "$r" ;; esac
"$B/svgcheck" render known-button.svg 2 out/twice.png
size=$(python3 -I -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print(*struct.unpack(">II", d[16:24]))' out/twice.png)
[ "$size" = "160 160" ] && pass "svgcheck: scale 2 renders 160x160" || bad "svgcheck scale" "$size"

# vectorfit: known designs come back.
for case in known-button:50:8 known-glow:50:3; do
    IFS=: read -r name minpsnr maxdiff <<< "$case"
    "$B/svgcheck" render $name.svg 1 $name.png
    out=$("$B/vectorfit" $name.json | tail -n 1)
    psnr=$(echo "$out" | sed -E 's/.*PSNR ([0-9.]+) dB.*/\1/')
    max=$(echo "$out" | sed -E 's/^result max ([0-9]+).*/\1/')
    if awk -v p="$psnr" -v m="$max" -v mp="$minpsnr" -v mm="$maxdiff" 'BEGIN { exit !(p >= mp && m <= mm) }'; then
        pass "vectorfit: $name recovered ($out)"
    else
        bad "vectorfit $name" "$out (want PSNR >= $minpsnr, max <= $maxdiff)"
    fi
done

# --freeze: the spec it writes gives the same SVG again.
cp known-glow.json out/frozen.json
sed -i 's|"known-glow.png"|"../known-glow.png"|; s|"out/known-glow.svg"|"frozen-1.svg"|' out/frozen.json
python3 -I - out/frozen.json <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["refine"] = ["rects"]; d["passes"] = 1; d["step"] = 0.25
json.dump(d, open(sys.argv[1], "w"))
PY
"$B/vectorfit" out/frozen.json --freeze > /dev/null
python3 -I - out/frozen.json <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); assert d["passes"] == 0, d["passes"]; d["out"] = "frozen-2.svg"
json.dump(d, open(sys.argv[1], "w"))
PY
"$B/vectorfit" out/frozen.json > /dev/null
cmp -s out/frozen-1.svg out/frozen-2.svg && pass "vectorfit: --freeze reproduces its SVG" || bad "freeze" "frozen-1.svg and frozen-2.svg differ"

rm -f known-button.png known-glow.png
exit $fail
