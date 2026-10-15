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

// A small dark button for the dashboard, which is drawn on the shell's
// black notification area rather than on a page.
Rectangle {
    id: button

    property alias text: label.text
    signal clicked()

    width: Math.max(Units.gu(7), label.implicitWidth + Units.gu(2))
    height: Units.gu(4)
    radius: Units.gu(0.6)
    color: area.pressed ? "#555555" : "#333333"
    border.color: "#666666"

    Text {
        id: label
        anchors.centerIn: parent
        color: "white"
        font.pixelSize: FontUtils.sizeToPixels("small")
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -Units.gu(0.5)
        onClicked: button.clicked()
    }
}
