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

import Eos.Window 0.1
import LunaNext.Common 0.1

import "components"
import "js/Recordings.js" as Recordings

/*
 * The dashboard in the notification area while a recording runs: how long
 * it has gone, pause and stop, and a tap anywhere else to bring the card
 * back. The card shell takes any floating window as a dashboard and reads
 * its height from LuneOS_dashheight when the window first shows, so those
 * are set before it does.
 */
WebOSWindow {
    id: dashboard

    property Item recorder

    signal openRequested()

    windowType: "_WEBOS_WINDOW_TYPE_FLOATING"
    width: Settings.displayWidth
    height: Units.gu(6)
    color: "transparent"
    visible: false

    Component.onCompleted: {
        setWindowProperty("LuneOS_window", "dashboard");
        setWindowProperty("LuneOS_metrics", "units");
        setWindowProperty("LuneOS_dashheight", "6");
        // The record button, in the notification area's row of icons;
        // relative to the app's folder.
        setWindowProperty("LuneOS_icon", "qml/images/dashboard-icon.png");
        visible = true;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: dashboard.openRequested()
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Units.gu(1.5)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Units.gu(1.5)

        // The red dot of the camera's record button, pulsing while it records.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Units.gu(1.6)
            height: width
            radius: width / 2
            color: "#e0261b"
            opacity: dashboard.recorder && dashboard.recorder.paused ? 0.35 : pulse.value

            QtObject {
                id: pulse
                property real value: 1
            }
            SequentialAnimation {
                running: dashboard.recorder && dashboard.recorder.recording
                loops: Animation.Infinite
                NumberAnimation { target: pulse; property: "value"; to: 0.35; duration: 700 }
                NumberAnimation { target: pulse; property: "value"; to: 1; duration: 700 }
                onRunningChanged: if (!running) pulse.value = 1
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: dashboard.recorder && dashboard.recorder.paused ? "Recording paused" : "Recording"
                color: "white"
                font.pixelSize: FontUtils.sizeToPixels("medium")
            }
            Text {
                text: Recordings.formatDuration(dashboard.recorder ? dashboard.recorder.duration : 0, true)
                color: "#aaaaaa"
                font.pixelSize: FontUtils.sizeToPixels("small")
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Units.gu(1)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Units.gu(1)

        DashboardButton {
            text: dashboard.recorder && dashboard.recorder.paused ? "Resume" : "Pause"
            onClicked: {
                if (dashboard.recorder.paused)
                    dashboard.recorder.resume();
                else
                    dashboard.recorder.pause();
            }
        }
        DashboardButton {
            text: "Stop"
            onClicked: dashboard.recorder.stop()
        }
    }
}
