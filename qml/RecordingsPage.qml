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

import SoundRecorderApp 1.0

import "components"
import "js/Recordings.js" as Recordings

/*
 * The one page most people need: the recordings, newest first, and the
 * record bar under them. Tapping a recording opens its player in place;
 * touch and hold for rename, send, details and delete.
 */
AppPage {
    id: page

    title: "Sound Recorder"
    explanationOnShortScreen: false
    explanation: appWindow.recorder.active ? ""
               : files.length > 0 ? "Tap a recording to play it, swipe it away to delete it."
               : ""

    readonly property var recorder: appWindow.recorder
    // Room for the list under the recording panel? On a short screen (the
    // Q25's square) it would be a sliver with a cut-off heading, so while
    // recording the panel has the page to itself there.
    readonly property bool listFitsWhileRecording: height - Units.gu(16) - Units.gu(12) >= Units.gu(18)
    readonly property var prefs: appWindow.prefs
    readonly property var fileOps: appWindow.fileOps

    // { path, name, size, modified } from FileOperations.list(), newest first.
    property var files: []
    // The recording whose player is open, by path; "" for none.
    property string openPath: ""
    // The recording the touch-and-hold menu is about.
    property var menuFile: null

    // Not the one being recorded: it is not finished, and shows as 0 bytes.
    readonly property var shownFiles: files.filter(function(f) {
        return f.path !== page.recorder.currentPath
                && Recordings.matches(Recordings.displayName(f.path), searchField.text);
    })

    function reload() {
        files = Recordings.sortNewestFirst(fileOps.list(Recordings.extensions));
        if (openPath !== "" && !files.some(function(f) { return f.path === openPath; }))
            closePlayer();
    }

    Component.onCompleted: reload()
    StackView.onActivated: reload()

    Connections {
        target: appWindow
        function onRecordingsRevisionChanged() { page.reload(); }
    }

    Connections {
        target: page.recorder
        // A new recording is on top; show it.
        function onSaved(path) { list.positionViewAtBeginning(); }
    }

    function togglePlayer(path) {
        if (openPath === path) {
            closePlayer();
            return;
        }
        audioPlayer.stop();
        openPath = path;
        audioPlayer.source = "file://" + path;
    }

    function closePlayer() {
        audioPlayer.stop();
        audioPlayer.source = "";
        openPath = "";
    }

    function removeFile(file) {
        if (openPath === file.path)
            closePlayer();
        if (!fileOps.remove(file.path)) {
            appWindow.notice = "Could not delete " + Recordings.displayName(file.path) + ".";
            return;
        }
        appWindow.durations.setDuration(Recordings.fileNameOf(file.path), 0);
        reload();
    }

    function renameFile(file, newName) {
        var name = Recordings.sanitizeName(newName);
        if (name === "" || name === Recordings.displayName(file.path))
            return;
        var wasOpen = openPath === file.path;
        if (wasOpen)
            closePlayer();
        var renamed = fileOps.rename(file.path, name);
        if (renamed === "") {
            appWindow.notice = "There is already a recording called “" + name + "”.";
            return;
        }
        appWindow.durations.renameDuration(Recordings.fileNameOf(file.path), Recordings.fileNameOf(renamed));
        reload();
        if (wasOpen)
            togglePlayer(renamed);
    }

    MediaPlayer {
        id: audioPlayer
        audioOutput: AudioOutput {}

        // Learn the length of recordings made before durations were kept,
        // or copied in from elsewhere.
        onDurationChanged: {
            if (duration > 0 && page.openPath !== "" && appWindow.durations.durationOf(Recordings.fileNameOf(page.openPath)) <= 0) {
                appWindow.durations.setDuration(Recordings.fileNameOf(page.openPath), duration);
                page.files = page.files.slice();
            }
        }
        onErrorOccurred: function(error, errorString) {
            appWindow.notice = "Could not play this recording: " + errorString;
        }
    }

    // A recording starting stops playback: one sound at a time.
    Connections {
        target: page.recorder
        function onActiveChanged() {
            if (page.recorder.active)
                audioPlayer.pause();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // While recording: the level and the time, big.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: page.recorder.active ? Units.gu(16) : 0
            Layout.fillHeight: page.recorder.active && !page.listFitsWhileRecording
            visible: page.recorder.active
            clip: true

            LevelMeter {
                id: meter
                active: page.recorder.recording
                deviceId: page.prefs.inputId
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Units.gu(4)
                spacing: Units.gu(1)

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.recorder.paused ? "Paused" : "Recording"
                    color: page.recorder.paused ? Colors.secondaryText : "#be0003"
                    font.pixelSize: FontUtils.sizeToPixels("medium")
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Recordings.formatDuration(page.recorder.duration, true)
                    color: Colors.text
                    font.pixelSize: Units.gu(5)
                    font.weight: Font.Light
                }
                LevelBars {
                    id: levelBars
                    width: parent.width
                    height: Units.gu(5)
                    // Only once the meter hears something: some inputs (the
                    // TouchPad's) give a second stream nothing while the
                    // recorder has the microphone, and an empty strip would
                    // look like a dead microphone.
                    opacity: heard ? 1 : 0
                    property bool heard: false
                    onPeakChanged: if (peak > 0) heard = true
                    peak: meter.peak
                    running: page.recorder.recording
                    color: page.recorder.paused ? "#999999" : "#be0003"
                    Connections {
                        target: page.recorder
                        function onActiveChanged() {
                            if (page.recorder.active) {
                                levelBars.clear();
                                levelBars.heard = false;
                            }
                        }
                    }
                }
            }
        }

        GroupBox {
            objectName: "recordingsGroup"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Units.gu(1)
            visible: !page.recorder.active || page.listFitsWhileRecording
            title: "Recordings"

            ColumnLayout {
                anchors.fill: parent
                spacing: Units.gu(0.5)

                TextField {
                    id: searchField
                    objectName: "searchField"
                    Layout.fillWidth: true
                    // Worth it once the list no longer fits at a glance.
                    visible: page.files.length >= 6
                    placeholderText: "Search"
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onVisibleChanged: if (!visible) text = ""
                }

                ListView {
                    id: list
                    objectName: "recordingsList"

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: page.shownFiles

                    delegate: RecordingRow {
                        width: list.width
                        file: modelData
                        index: model.index
                        count: list.count
                        open: page.openPath === modelData.path
                        durationMs: open && audioPlayer.duration > 0 ? audioPlayer.duration
                                    : appWindow.durations.durationOf(Recordings.fileNameOf(modelData.path))
                        player: audioPlayer
                        use24h: appWindow.use24h

                        onTapped: page.togglePlayer(modelData.path)
                        onHeld: {
                            page.menuFile = modelData;
                            fileMenu.popup();
                        }
                        onRenameClicked: { page.menuFile = modelData; renameDialog.open(); }
                        onSendClicked: appWindow.sendByEmail(modelData.path)
                        onDeleteClicked: { page.menuFile = modelData; deleteDialog.visible = true; }
                        onSwipeDeleted: page.removeFile(modelData)
                    }

                    Label {
                        parent: list
                        anchors.centerIn: list
                        width: list.width - Units.gu(4)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: list.count === 0
                        text: page.files.length > 0 ? "No recording matches “" + searchField.text + "”."
                                                    : "No recordings yet.\nTap the red button to record."
                        color: Colors.secondaryText
                        font.pixelSize: FontUtils.sizeToPixels("medium")
                    }

                    ScrollIndicator.vertical: ScrollIndicator { }
                }
            }
        }

        RecordBar {
            Layout.fillWidth: true
            active: page.recorder.active
            paused: page.recorder.paused
            canRecord: !appWindow.micBlocked

            onRecordClicked: appWindow.startRecording()
            onStopClicked: page.recorder.stop()
            onPauseClicked: page.recorder.pause()
            onResumeClicked: page.recorder.resume()
        }
    }

    Menu {
        id: fileMenu

        MenuItem {
            text: "Rename"
            onTriggered: renameDialog.open()
        }
        MenuItem {
            text: "Send by Email"
            onTriggered: appWindow.sendByEmail(page.menuFile.path)
        }
        MenuItem {
            text: "Details"
            onTriggered: detailsDialog.visible = true
        }
        MenuItem {
            text: "Delete"
            onTriggered: deleteDialog.visible = true
        }
    }

    PromptDialog {
        id: renameDialog

        function open() {
            defaultValue = page.menuFile ? Recordings.displayName(page.menuFile.path) : "";
            visible = true;
        }

        visible: false
        title: "Rename recording"
        onAccepted: function(text) {
            visible = false;
            if (page.menuFile)
                page.renameFile(page.menuFile, text);
        }
        onRejected: visible = false
    }

    ConfirmDialog {
        id: deleteDialog

        visible: false
        title: "Delete recording"
        message: page.menuFile ? "Delete “" + Recordings.displayName(page.menuFile.path) + "”? This cannot be undone." : ""
        onAccepted: {
            visible = false;
            if (page.menuFile)
                page.removeFile(page.menuFile);
        }
        onRejected: visible = false
    }

    AlertDialog {
        id: detailsDialog

        visible: false
        dialogHeight: Units.gu(26)
        dialogWidth: Math.min(Units.gu(40), page.width - Units.gu(4))
        title: page.menuFile ? Recordings.displayName(page.menuFile.path) : ""
        message: {
            if (!page.menuFile)
                return "";
            var f = page.menuFile;
            var format = Recordings.formatForPath(f.path);
            var ms = appWindow.durations.durationOf(Recordings.fileNameOf(f.path));
            return "Recorded: " + new Date(f.modified).toLocaleString(Qt.locale(), Locale.ShortFormat)
                    + "\nLength: " + (ms > 0 ? Recordings.formatDuration(ms) : "unknown")
                    + "\nFormat: " + (format ? format.label : Recordings.extensionOf(f.path))
                    + "\nSize: " + Recordings.formatSize(f.size)
                    + "\nFile: " + f.path;
        }
        onAccepted: visible = false
    }
}
