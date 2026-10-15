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
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

import QtQuick.Controls.LuneOS 2.0
import LunaNext.Common 0.1
import LuneOS.Components 1.0
import LuneOS.Forms 1.0

import "../js/Recordings.js" as Recordings

/*
 * One recording in the list: its name, when it was made and how long it
 * is. Open, it grows the player underneath - position, -10 s / play /
 * +10 s - and the things to do with it.
 */
Item {
    id: row

    property var file
    property int index: 0
    property int count: 0
    property bool open: false
    property real durationMs: 0
    property MediaPlayer player
    property bool use24h: true

    signal tapped()
    signal held()
    signal renameClicked()
    signal sendClicked()
    signal deleteClicked()
    // Swiped away and confirmed in the row: delete without asking again.
    signal swipeDeleted()

    readonly property bool playing: open && player && player.playbackState === MediaPlayer.PlayingState

    height: summary.height + (open ? controls.implicitHeight + Units.gu(1) : 0)
    clip: true

    Behavior on height {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        color: row.open ? "#ffffff" : "transparent"
        opacity: 0.6
    }

    Item {
        id: summary

        width: parent.width
        height: Units.gu(7)

        // Swiped far enough: the row asks Delete / Cancel in place, the
        // way the legacy webOS lists did.
        property bool confirming: false

        // Under the row while it is swiped: the question.
        Rectangle {
            anchors.fill: parent
            visible: content.x !== 0 || summary.confirming
            color: "#5a5a5a"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Units.gu(1.5)
                anchors.rightMargin: Units.gu(1.5)
                spacing: Units.gu(1.5)
                visible: summary.confirming

                Item { Layout.fillWidth: true }
                Button {
                    objectName: "swipeDeleteButton"
                    text: "Delete"
                    LuneOSButton.mainColor: LuneOSButton.negativeColor
                    onClicked: { summary.confirming = false; row.swipeDeleted(); }
                }
                Button {
                    objectName: "swipeCancelButton"
                    text: "Cancel"
                    onClicked: summary.cancelSwipe()
                }
                Item { Layout.fillWidth: true }
            }
        }

        function cancelSwipe() {
            confirming = false;
            content.x = 0;
        }

        Item {
            id: content

            width: parent.width
            height: parent.height
            visible: !summary.confirming

            Behavior on x {
                enabled: !swipe.active
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
            }

            Rectangle {
                anchors.fill: parent
                visible: parent.x !== 0
                color: Colors.pageBackground
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Units.gu(1)
                anchors.rightMargin: Units.gu(0.5)
                spacing: Units.gu(1)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        Layout.fillWidth: true
                        text: Recordings.displayName(row.file.path)
                        elide: Text.ElideRight
                        color: Colors.text
                        font.pixelSize: FontUtils.sizeToPixels("medium")
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Recordings.formatWhen(new Date(row.file.modified), new Date(), row.use24h)
                              + " \u00b7 " + Recordings.formatSize(row.file.size)
                        elide: Text.ElideRight
                        color: Colors.secondaryText
                        font.pixelSize: FontUtils.sizeToPixels("small")
                    }
                }

                Label {
                    text: row.durationMs > 0 ? Recordings.formatDuration(row.durationMs) : ""
                    color: Colors.secondaryText
                    font.pixelSize: FontUtils.sizeToPixels("small")
                }

                // The things to do with it, without having to know about
                // touch and hold.
                ToolButton {
                    objectName: "moreButton"
                    Layout.preferredWidth: Units.gu(5)
                    Layout.preferredHeight: Units.gu(5)
                    text: "\u2026"
                    font.pixelSize: FontUtils.sizeToPixels("large")
                    onClicked: row.held()
                }
            }

            // A TapHandler, not a MouseArea: inside a ListView only a
            // pointer handler keeps a long press (Remote, the Wi-Fi page).
            TapHandler {
                id: tap
                property bool wasHeld: false
                longPressThreshold: 0.8
                onPressedChanged: if (pressed) wasHeld = false
                onLongPressed: { wasHeld = true; row.held(); }
                onTapped: if (!wasHeld) row.tapped()
            }

            // Swipe sideways to delete: past a third of the width the row
            // asks to confirm, short of it it springs back.
            DragHandler {
                id: swipe
                target: content
                yAxis.enabled: false
                xAxis.minimum: -row.width
                xAxis.maximum: row.width
                onActiveChanged: {
                    if (active)
                        return;
                    if (Math.abs(content.x) > row.width / 3) {
                        summary.confirming = true;
                        content.x = 0;
                    } else {
                        content.x = 0;
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: controls

        anchors.top: summary.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Units.gu(1)
        anchors.rightMargin: Units.gu(1)
        visible: row.open
        spacing: Units.gu(0.5)

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: Recordings.formatDuration(row.player ? row.player.position : 0)
                color: Colors.secondaryText
                font.pixelSize: FontUtils.sizeToPixels("small")
            }
            Slider {
                id: seek
                objectName: "seekSlider"
                Layout.fillWidth: true
                from: 0
                to: Math.max(1, row.player && row.player.duration > 0 ? row.player.duration : row.durationMs)
                value: row.player ? row.player.position : 0
                enabled: row.player && row.player.seekable
                onMoved: row.player.position = value
            }
            Label {
                text: Recordings.formatDuration(row.player && row.player.duration > 0 ? row.player.duration : row.durationMs)
                color: Colors.secondaryText
                font.pixelSize: FontUtils.sizeToPixels("small")
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Units.gu(1)

            Button {
                text: "−10 s"
                onClicked: row.player.position = Math.max(0, row.player.position - 10000)
            }
            Button {
                objectName: "playButton"
                Layout.preferredWidth: Units.gu(12)
                text: row.playing ? "Pause" : "Play"
                LuneOSButton.mainColor: LuneOSButton.affirmativeColor
                onClicked: row.playing ? row.player.pause() : row.player.play()
            }
            Button {
                text: "+10 s"
                onClicked: row.player.position = Math.min(row.player.duration, row.player.position + 10000)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Units.gu(0.5)
            spacing: Units.gu(1)

            Button {
                Layout.fillWidth: true
                text: "Rename"
                onClicked: row.renameClicked()
            }
            Button {
                Layout.fillWidth: true
                text: "Send"
                onClicked: row.sendClicked()
            }
            Button {
                Layout.fillWidth: true
                text: "Delete"
                LuneOSButton.mainColor: LuneOSButton.negativeColor
                onClicked: row.deleteClicked()
            }
        }
    }

    ListDelegateSeparator {
        anchors.fill: parent
        index: row.index
        count: row.count
    }
}
