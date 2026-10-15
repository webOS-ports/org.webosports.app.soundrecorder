/*
 * (c) 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick

import "../js/Recordings.js" as Recordings

/*
 * The microphone's level as a strip of bars that scrolls right to left,
 * the newest on the right: what has just been said stays visible for a
 * couple of seconds.
 */
Item {
    id: bars

    // The loudest sample, 0..1 of full scale (LevelMeter.peak).
    property real peak: 0
    property bool running: false
    property color color: "#e0261b"
    property int count: Math.max(8, Math.floor(width / 6))

    // 0..1 per bar, oldest first.
    property var history: []

    function clear() {
        history = [];
    }

    Timer {
        interval: 60
        repeat: true
        running: bars.running
        onTriggered: {
            var h = bars.history.slice(Math.max(0, bars.history.length - bars.count + 1));
            h.push(Recordings.meterLevel(bars.peak));
            bars.history = h;
        }
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        layoutDirection: Qt.RightToLeft

        Repeater {
            model: bars.history.length

            Rectangle {
                // index 0 is drawn rightmost: the newest.
                readonly property real level: bars.history[bars.history.length - 1 - index] || 0
                width: 4
                height: Math.max(2, level * bars.height)
                anchors.verticalCenter: parent.verticalCenter
                radius: 2
                color: bars.color
                opacity: 0.45 + 0.55 * level
            }
        }
    }
}
