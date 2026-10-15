#!/bin/sh
# Runs the QML tests on the build host: the helpers (tst_recordings.qml) and
# the app's pages (tst_ui.qml) with luneos-components' desktop stand-ins.
#
#   tests/run-qml-tests.sh [path to luneos-components [qmltestrunner arguments]]
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style and LuneOS.Components plugins; the latter provides
# image://artwork, which the app's buttons load through. A further
# "-import <dir>" puts a build of either in <dir> ahead of the checkout's.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
[ $# -gt 0 ] && shift
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT
# The preferences and the artwork cache go to a throwaway directory, not the
# user's.
XDG_CONFIG_HOME=$CONF XDG_CACHE_HOME=$CONF/cache QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
    ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
    -import tests/qml/imports -import "$LC/modules" -import "$LC/test/imports" \
    -input tests/qml "$@"
