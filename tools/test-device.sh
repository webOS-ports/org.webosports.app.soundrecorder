#!/bin/bash
# Records on a real device and checks what comes out: for each format and
# channel count, set the preference, start the app with {"action":
# "record"}, stop it with {"action": "stop"} a few seconds later, pull the
# file and check with ffprobe that it is that format, about that long and
# not silence. Takes a screenshot of the screen while recording (the
# dashboard included). The app's preferences are put back at the end and
# the test recordings deleted.
#
#   tools/test-device.sh <adb serial> <name> [seconds]
#
# Install the app first (tools/install.sh). Needs ffprobe and ffmpeg here.
set -e
cd "$(dirname "$0")/.."
SERIAL=${1:?usage: tools/test-device.sh <adb serial> <name> [seconds]}
NAME=${2:?usage: tools/test-device.sh <adb serial> <name> [seconds]}
SECONDS_REC=${3:-5}
ADB="adb -s $SERIAL"
ID=org.webosports.app.soundrecorder
DIR=/media/internal/Recordings
PREFS=/home/root/.config/$ID/preferences.ini
OUT=build/test-output/device/$NAME
mkdir -p "$OUT"
failures=0

launch() {
    $ADB shell "luna-send -n 1 -w 8000 luna://com.webos.service.applicationmanager/launch '{\"id\":\"$ID\",\"params\":$1}' > /tmp/sr-l.out 2>&1"
}
shot() {
    $ADB shell "luna-send -w 10000 -n 1 luna://com.webos.surfacemanager/captureCompositorOutput '{\"output\":\"/tmp/sr-shot.png\",\"format\":\"PNG\"}' > /tmp/sr-c.out 2>&1"
    $ADB pull /tmp/sr-shot.png "$OUT/$1.png" >/dev/null 2>&1 || true
}

echo "== $NAME: $($ADB shell uname -m), recording ${SECONDS_REC}s per case"
$ADB shell "cp $PREFS /tmp/sr-prefs.saved 2>/dev/null || rm -f /tmp/sr-prefs.saved"
before=$($ADB shell "ls $DIR 2>/dev/null" | tr -d '\r')

restore() {
    $ADB shell "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' >/dev/null 2>&1; \
        if [ -f /tmp/sr-prefs.saved ]; then cp /tmp/sr-prefs.saved $PREFS; else rm -f $PREFS; fi"
    echo "   restored the app's preferences"
}
trap restore EXIT

for case in mp3 flac wav; do
    fmt=$case
    # Two channels: Qt's GStreamer backend records stereo, always.
    ch=2
    # The app reads its preferences when it starts.
    $ADB shell "luna-send -n 1 -w 3000 luna://com.webos.service.applicationmanager/closeByAppId '{\"id\":\"$ID\"}' >/dev/null 2>&1; sleep 1; \
        mkdir -p \$(dirname $PREFS); printf '[recording]\nformat=$fmt\nquality=2\ninputId=\ninputVolume=1\n' > $PREFS"
    launch '{"action":"record"}'
    sleep "$SECONDS_REC"
    [ "$case" = mp3 ] && shot "recording"
    launch '{"action":"stop"}'
    sleep 2
    new=$($ADB shell "ls -t $DIR | head -n 1" | tr -d '\r')
    if echo "$before" | grep -qxF "$new" || [ -z "$new" ]; then
        echo "FAIL $case: no new recording"; failures=$((failures + 1)); continue
    fi
    $ADB pull "$DIR/$new" "$OUT/$case-$new" >/dev/null
    f="$OUT/$case-$new"
    codec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,channels -of csv=p=0 "$f" 2>/dev/null || echo "unreadable ($(stat -c %s "$f") bytes)")
    # Decoding counts the samples, which works for FLAC without a length too.
    dur=$(ffmpeg -nostats -i "$f" -f null - 2>&1 | grep -oE 'time=[0-9:.]+' | tail -n 1 | cut -d= -f2)
    secs=$(echo "$dur" | awk -F: '{ print $1 * 3600 + $2 * 60 + $3 }')
    peak=$(ffmpeg -nostats -i "$f" -af volumedetect -f null - 2>&1 | grep -oE 'max_volume: [-0-9.]+' | awk '{ print $2 }')
    want_codec=$([ $fmt = wav ] && echo pcm_s16le || echo $fmt)
    ok=1
    case "$codec" in "$want_codec,$ch") ;; *) ok=0 ;; esac
    awk -v p="$peak" 'BEGIN { exit !(p > -80) }' || ok=0
    # The length the app stored for the list must be the file's: the
    # recording starts only once the app is up, so not the full SECONDS_REC.
    stored=$($ADB shell "grep -F \"$(echo "$new" | sed 's/ /%20/g')=\" $PREFS" | tr -d '\r' | cut -d= -f2)
    awk -v s="$secs" -v m="${stored:-0}" 'BEGIN { exit !(m > 0 && s > 1 && (s - m / 1000) < 0.6 && (m / 1000 - s) < 0.6) }' || ok=0
    if [ $ok = 1 ]; then
        echo "ok   $case: $new ($codec, ${secs}s, app says ${stored} ms, peak ${peak} dB)"
    else
        echo "FAIL $case: $new ($codec, wanted $want_codec,$ch; ${secs}s; app says ${stored:-nothing} ms; peak ${peak} dB)"; failures=$((failures + 1))
    fi
    $ADB shell "rm -f '$DIR/$new'"
done

shot "after"
echo "$([ $failures = 0 ] && echo PASS || echo "FAILED: $failures") - files and screenshots in $OUT"
exit $failures
