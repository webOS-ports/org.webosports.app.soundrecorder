#!/bin/sh
# Runs the QML tests on the build host: the helpers (tst_recordings.qml) and
# the app's pages (tst_ui.qml) once, with luneos-components' desktop
# stand-ins; then every screen (tst_screens.qml) once per device screen in
# PROFILES - by default the mindphone, the Q25, the TouchPad and the
# FuriPhone FLX1s (radon) - each saved as
# build/test-output/ui/<profile>-<screen>.png.
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#   PROFILES=q25 tests/run-qml-tests.sh ...      one screen only
#   TESTS= tests/run-qml-tests.sh ...            only the screens
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style and LuneOS.Components plugins; the latter provides
# image://artwork, which the app's buttons load through. A further
# "-import <dir>" puts a build of either in <dir> ahead of the checkout's.
#
# The stand-ins read their profile, and with it the window's size and the
# grid unit, once as they load, and qmltestrunner passes no --profile on:
# each profile runs against a copy of LunaNext.Common whose default profile
# is that screen, imported after (so ahead of) the stand-ins.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
PROFILES=${PROFILES:-mindphone q25 tp radon}
TESTS=${TESTS-tst_recordings.qml tst_ui.qml}
# tst_screens' real recording goes to build/test-output/recordings, emptied
# on the way out.
mkdir -p build/test-output/ui build/test-output/recordings
CONF=$(mktemp -d "$(pwd)/build/qmltest.XXXXXX")
trap 'rm -rf "$CONF" build/test-output/recordings' EXIT

# The preferences and the artwork cache go to a throwaway directory, not the
# user's, and start afresh for each run.
run() {
    rm -rf "$CONF/config" "$CONF/cache"
    XDG_CONFIG_HOME=$CONF/config XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
    QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
        ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
        -import tests/qml/imports -import "$LC/modules" -import "$LC/test/imports" "$@"
}

status=0
for t in $TESTS; do
    echo "--- $t"
    run -input "tests/qml/$t" "$@" || status=1
done
for profile in $PROFILES; do
    common=$CONF/profile-$profile/LunaNext/Common
    mkdir -p "$common"
    cp "$LC"/test/imports/LunaNext/Common/* "$common/"
    sed -i "s/^var defaultProfile = .*/var defaultProfile = \"$profile\";/" "$common/SettingsStub.js"
    if ! grep -q "^var defaultProfile = \"$profile\";" "$common/SettingsStub.js"; then
        echo "could not select profile $profile in SettingsStub.js" >&2
        status=1
        continue
    fi
    echo "--- tst_screens.qml ($profile)"
    run -import "$CONF/profile-$profile" -input tests/qml/tst_screens.qml "$@" || status=1
done
exit $status
