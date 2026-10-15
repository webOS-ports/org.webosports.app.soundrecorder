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

/*
 * A button drawn from two SVGs, its normal and its pressed look. Rendered
 * at the size it is shown at, so it is sharp at any scale (the legacy
 * camera's buttons, redrawn as vectors: tools/vectorize).
 */
Item {
    id: button

    property url source
    property url pressedSource
    readonly property alias pressed: area.pressed

    signal clicked()

    Image {
        anchors.fill: parent
        source: area.pressed && button.pressedSource.toString() !== "" ? button.pressedSource : button.source
        sourceSize: Qt.size(Math.ceil(button.width), Math.ceil(button.height))
        smooth: true
        asynchronous: false
    }

    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
