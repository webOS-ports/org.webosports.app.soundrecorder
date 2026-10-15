#!/bin/bash
# Takes the README's screenshots on a device: the list with three sample
# recordings, a recording's player, a recording in progress (with its
# dashboard) and the preferences. The screen must be on and unlocked.
# Recordings already on the device are moved aside for the screenshots and
# put back after; what it records is deleted and the app's preferences are
# put back.
#
#   tools/screenshots.sh <adb serial> <name>
#
# Install the app first (tools/install.sh). Writes build/screenshots/<name>/.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: tools/screenshots.sh <adb serial> <name>}
NAME=${2:?usage: tools/screenshots.sh <adb serial> <name>}
ADB="adb -s $SERIAL"
ID=org.webosports.app.soundrecorder
DIR=/media/internal/Recordings
PREFS=/home/root/.config/$ID/preferences.ini
OUT=build/screenshots/$NAME
mkdir -p "$OUT"

sh_() { $ADB shell "$1" | tr -d '\r'; }
# Activity, so the screen neither dims nor locks while the script works.
awake() {
    sh_ "luna-send -n 1 -w 3000 luna://com.palm.display/control/notifyUserActivity '{}' > /dev/null 2>&1"
}
launch() {
    awake
    sh_ "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\",\"params\":$1}' > /tmp/sr-l.out 2>&1"
}
close() {
    sh_ "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' > /dev/null 2>&1; sleep 1"
}
shot() {
    awake
    sh_ "luna-send -w 10000 -n 1 luna://com.webos.surfacemanager/captureCompositorOutput '{\"output\":\"/tmp/sr-shot.png\",\"format\":\"PNG\"}' > /tmp/sr-c.out 2>&1"
    $ADB pull /tmp/sr-shot.png "$OUT/$1.png" > /dev/null
    echo "   $OUT/$1.png"
}
newest() { sh_ "ls -t $DIR | head -n 1"; }

made=()
ASIDE=$DIR.screenshots-aside
sh_ "cp $PREFS /tmp/sr-prefs.saved 2>/dev/null || rm -f /tmp/sr-prefs.saved"
# The user's recordings out of the way, on the same file system.
sh_ "mkdir -p $DIR $ASIDE; for f in $DIR/*; do [ -f \"\$f\" ] && mv \"\$f\" $ASIDE/; done; true"
cleanup() {
    close
    for f in "${made[@]}"; do sh_ "rm -f '$DIR/$f'"; done
    sh_ "for f in $ASIDE/*; do [ -f \"\$f\" ] && mv -n \"\$f\" $DIR/; done; rmdir $ASIDE 2>/dev/null; true"
    sh_ "if [ -f /tmp/sr-prefs.saved ]; then cp /tmp/sr-prefs.saved $PREFS; else rm -f $PREFS; fi"
    echo "   deleted ${#made[@]} sample recordings, put back $(sh_ "ls $DIR | wc -l") recordings, restored the app's preferences"
}
trap cleanup EXIT

sh_ "luna-send -n 1 -w 3000 luna://com.palm.display/control/setState '{\"state\":\"on\"}' > /dev/null 2>&1"

# Three samples, one per format, renamed the way a user would; the length
# the app stored moves with each.
for sample in "mp3:Lecture notes:9" "flac:Interview with Anna:14" "wav:Song idea:6"; do
    IFS=: read -r fmt title secs <<< "$sample"
    close
    sh_ "mkdir -p \$(dirname $PREFS); printf '[recording]\nformat=$fmt\nquality=2\ninputId=\ninputVolume=1\n' > $PREFS.tmp; \
        if [ -f $PREFS ]; then grep -v -E '^(format|quality|inputId|inputVolume)=' $PREFS | grep -v '^\[recording\]' >> $PREFS.tmp; fi; mv $PREFS.tmp $PREFS"
    # Up first, so the recording is as long as asked.
    launch '{}'
    sleep 3
    launch '{"action":"record"}'
    sleep "$secs"
    launch '{"action":"stop"}'
    # Closing the card within seconds of its recording dashboard closing
    # leaves the card shell drawing the next launch squashed (a shell bug):
    # give the dashboard time to go first.
    sleep 12
    f=$(newest)
    ext=${f##*.}
    sh_ "mv '$DIR/$f' '$DIR/$title.$ext'; sed -i 's|^$(echo "$f" | sed 's/ /%20/g')=|$(echo "$title.$ext" | sed 's/ /%20/g')=|' $PREFS"
    made+=("$title.$ext")
    sleep 1
done
sh_ "sed -i 's/^format=.*/format=mp3/' $PREFS"

echo "== $NAME"
# A fresh card, and time for the shell to settle after the samples'
# dashboards have come and gone.
# Is the card drawn right? The card shell sometimes draws a fresh launch
# squashed and pinned to the bottom (a shell bug, after a dashboard closes):
# then the header's record icon sits far below its place.
drawn_right() {
    python3 -I - "$OUT/$1.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
w, h = im.size
p = im.load()
for y in range(h // 4):
    if any(p[x, y][0] > 200 and p[x, y][1] < 80 and p[x, y][2] < 80 for x in range(w // 6)):
        sys.exit(0 if y / h < 0.11 else 1)
sys.exit(1)
PY
}

# Started again, so it reads the names, lengths and preferences set above.
for attempt in 1 2 3; do
    close
    sleep 12
    launch '{}'
    sleep 6
    shot 1-recordings
    drawn_right 1-recordings && break
    echo "   the card shell drew the card squashed; again"
done

launch "{\"target\":\"$DIR/Interview with Anna.flac\"}"
sleep 3
shot 2-player

launch '{"action":"record"}'
sleep 5
shot 3-recording
launch '{"action":"stop"}'
sleep 2
made+=("$(newest)")

launch '{"page":"preferences"}'
sleep 3
shot 4-preferences
