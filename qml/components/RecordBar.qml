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

import LunaNext.Common 0.1


/*
 * The bar along the bottom, the camera's in video mode: the record button
 * on its round bezel in the middle, which turns into the stop button while
 * recording, and pause on the left. The page shows the running time.
 */
Rectangle {
    id: bar

    property bool active: false
    property bool paused: false
    // False while the privacy switch has the microphone off.
    property bool canRecord: true
    // A shorter bar on a short screen, so the list keeps room.
    property bool compact: false
    readonly property real buttonSize: compact ? Units.gu(8) : Units.gu(10)

    signal recordClicked()
    signal stopClicked()
    signal pauseClicked()
    signal resumeClicked()

    height: compact ? Units.gu(9.5) : Units.gu(12)
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#3a3a3a" }
        GradientStop { position: 0.08; color: "#202020" }
        GradientStop { position: 1.0; color: "#0c0c0c" }
    }

    Image {
        anchors.centerIn: parent
        width: bar.buttonSize
        height: width
        source: "../images/bezel.svg"
        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
    }

    SvgButton {
        id: recordButton

        objectName: "recordButton"
        anchors.centerIn: parent
        width: bar.buttonSize
        height: width
        source: Qt.resolvedUrl(bar.active ? "../images/stop.svg" : "../images/record.svg")
        pressedSource: Qt.resolvedUrl(bar.active ? "../images/stop-pressed.svg" : "../images/record-pressed.svg")
        opacity: bar.canRecord || bar.active ? 1 : 0.4
        onClicked: {
            if (bar.active)
                bar.stopClicked();
            else if (bar.canRecord)
                bar.recordClicked();
        }
    }

    RoundButton {
        objectName: "pauseButton"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Units.gu(2)
        visible: bar.active
        glyph: bar.paused ? "resume" : "pause"
        onClicked: bar.paused ? bar.resumeClicked() : bar.pauseClicked()
    }
}
