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

import LuneOS.Components 1.0

/*
 * A button drawn from the app's artwork (qml/images, the legacy camera's
 * buttons redrawn as vectors: tools/vectorize): "<image>.svg" normally and
 * "<image>-pressed.svg" while it is held. LuneOS.Components' ArtworkImage
 * draws each once at the size shown and keeps it as PNG; both are loaded up
 * front, so the first press does not wait for its picture.
 */
Item {
    id: button

    /// The artwork's name in qml/images, without "-pressed" or ".svg".
    property string image
    readonly property alias pressed: area.pressed

    signal clicked()

    ArtworkImage {
        objectName: "normalImage"
        anchors.fill: parent
        svg: button.image ? Qt.resolvedUrl("../images/" + button.image + ".svg") : ""
        visible: !area.pressed
    }

    ArtworkImage {
        objectName: "pressedImage"
        anchors.fill: parent
        svg: button.image ? Qt.resolvedUrl("../images/" + button.image + "-pressed.svg") : ""
        visible: area.pressed
    }

    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: button.clicked()
    }
}
