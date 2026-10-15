#!/bin/sh
# Runs the QML tests on the build host: the helpers (tst_recordings.qml) and
# the app's pages (tst_ui.qml) with luneos-components' desktop stand-ins.
#
#   tests/run-qml-tests.sh [path to luneos-components]
#
# luneos-components needs its desktop build (CONFIG+=desktop, see its
# README) for the style and LuneOS.Components plugins.
set -e
cd "$(dirname "$0")/.."
LC=${1:-../luneos-components}
CONF=$(mktemp -d)
trap 'rm -rf "$CONF"' EXIT
# The preferences go to a throwaway config directory, not the user's.
XDG_CONFIG_HOME=$CONF QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-offscreen} \
QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS \
    ${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner} \
    -import tests/qml/imports -import "$LC/modules" -import "$LC/test/imports" \
    -input tests/qml "$@"
