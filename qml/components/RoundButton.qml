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
 * The legacy camera's black round button, as vectors, with a glyph drawn
 * on it, so no icon font is needed.
 */
Item {
    id: button

    // "pause", "resume" (a red dot: back to recording) or "none".
    property string glyph: "pause"
    signal clicked()

    width: Units.gu(6.25)
    height: width

    Image {
        anchors.fill: parent
        source: area.pressed ? "../images/round-button-pressed.svg" : "../images/round-button.svg"
        sourceSize: Qt.size(Math.ceil(button.width), Math.ceil(button.height))
    }

    Row {
        anchors.centerIn: parent
        spacing: button.width * 0.08
        visible: button.glyph === "pause"
        Repeater {
            model: 2
            Rectangle {
                width: button.width * 0.09
                height: button.width * 0.32
                radius: 1
                color: "white"
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        visible: button.glyph === "resume"
        width: button.width * 0.3
        height: width
        radius: width / 2
        color: "#e0261b"
        border.color: "#ff8a80"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
