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
import QtQuick.Controls.LuneOS 2.0

import LunaNext.Common 0.1
import LuneOS.Service 1.0
import LuneOS.System 1.0
import LuneOS.Forms 1.0

import SoundRecorderApp 1.0

import "js/Recordings.js" as Recordings

/*
 * Sound Recorder: record from the microphone, then play, rename, send or
 * delete what was recorded.
 *
 * The window holds what lives as long as the app does - the recorder, the
 * preferences, the bus - so a recording carries on while the card is in the
 * background, with a dashboard to stop it from, and the device stays awake
 * until it is done.
 */
AppWindow {
    id: appWindow

    title: "Sound Recorder"
    icon: Qt.resolvedUrl("../icon.png")
    initialPage: Qt.resolvedUrl("RecordingsPage.qml")

    // Where recordings go: the user's media partition, next to DCIM.
    property string recordingsPath: "/media/internal/Recordings"

    // Closing the card while recording must not lose the recording: the app
    // stays alive (the dashboard still shows) until it is stopped.
    keepAlive: recorder.active

    property alias prefs: preferences
    property alias durations: durationStore
    property alias recorder: recorder
    property alias fileOps: fileOps

    // The hardware privacy switch has the microphone off.
    property bool micBlocked: false
    // Says what went wrong, under the header, until dismissed.
    property string notice: ""
    // Bumped whenever the set of recordings changes, so the list reloads.
    property int recordingsRevision: 0

    PreferencesModel {
        id: preferences
    }

    // Coming back to the app: files may have been copied in or deleted
    // (over USB, from the file manager) while it was in the background.
    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive)
                appWindow.recordingsRevision++;
        }
    }

    DurationStore {
        id: durationStore
    }

    FileOperations {
        id: fileOps
        rootPath: appWindow.recordingsPath
    }

    Recorder {
        id: recorder

        formatKey: preferences.format
        quality: preferences.quality
        inputId: preferences.inputId
        inputVolume: preferences.inputVolume

        onSaved: function(path, durationMs) {
            durationStore.setDuration(Recordings.fileNameOf(path), durationMs);
            appWindow.recordingsRevision++;
        }
        onFailed: function(path, reason) {
            appWindow.notice = "The recording failed: " + reason;
            appWindow.recordingsRevision++;
        }
        onActiveChanged: appWindow.updateWakeActivity()
    }

    /*
     * Starts a recording with the next free name. Returns false and sets
     * notice when it cannot.
     */
    function startRecording() {
        if (micBlocked) {
            notice = "The microphone is switched off with the privacy switch.";
            return false;
        }
        if (!fileOps.ensureRoot()) {
            notice = "Could not create " + recordingsPath + ".";
            return false;
        }
        var free = fileOps.freeSpace();
        if (free >= 0 && free < 20 * 1024 * 1024) {
            notice = "There is not enough free space to record.";
            return false;
        }
        var ext = Recordings.format(preferences.format).ext;
        var taken = fileOps.list(Recordings.extensions).map(function(f) { return f.name; });
        var name = Recordings.uniqueName(Recordings.defaultName(new Date()), ext, taken);
        notice = "";
        if (!recorder.start(recordingsPath + "/" + name + ext)) {
            notice = recorder.error !== "" ? recorder.error : "The recorder is not ready.";
            return false;
        }
        return true;
    }

    // The clock style of Settings > Date & Time, for the list's times.
    readonly property bool use24h: systemPrefs.values.timeFormat !== "HH12"

    SystemPreferences {
        id: systemPrefs
        keys: ["timeFormat"]
        clientName: "org.webosports.app.soundrecorder"
    }

    LunaService {
        id: service
        name: "org.webosports.app.soundrecorder"
    }

    /*
     * Keeps the device from suspending while recording: sleepd ends an
     * activity after at most 15 minutes, so it is renewed well before.
     * Needs "sleep.operation" (sysbus/...perm.json).
     */
    readonly property string wakeActivityId: "org.webosports.app.soundrecorder.recording"

    function updateWakeActivity() {
        if (recorder.active) {
            renewWakeActivity();
        } else {
            service.call("luna://com.palm.sleep/com/palm/power/activityEnd",
                         JSON.stringify({"id": wakeActivityId}), function() {}, function() {});
        }
    }

    function renewWakeActivity() {
        service.call("luna://com.palm.sleep/com/palm/power/activityStart",
                     JSON.stringify({"id": wakeActivityId, "duration_ms": 900000}),
                     function() {},
                     function(error) { console.warn("Could not keep the device awake: " + error); });
    }

    /*
     * The screen kept on while recording, if the user wants it: luna-
     * displaymanager's "requestBlock" holds the display as it is (no
     * dimming, no timeout) for as long as the call stays open, and
     * cancelling the call lets go. Needs "display.operation".
     */
    readonly property bool screenKeptOn: recorder.active && preferences.keepScreenOn
    property var screenBlockCall: null
    onScreenKeptOnChanged: updateScreenBlock(screenKeptOn)

    function updateScreenBlock(on) {
        if (on && !screenBlockCall) {
            // The desktop stand-in for the bus returns no call object.
            screenBlockCall = service.subscribe("luna://com.palm.display/control/setProperty",
                                                JSON.stringify({"requestBlock": true, "client": "org.webosports.app.soundrecorder"}),
                                                function() {},
                                                function(error) { console.warn("Could not keep the screen on: " + error); })
                              || ({});
        } else if (!on && screenBlockCall) {
            if (typeof screenBlockCall.cancel === "function")
                screenBlockCall.cancel();
            screenBlockCall = null;
        }
    }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: recorder.active
        onTriggered: appWindow.renewWakeActivity()
    }

    // The privacy switches, as Camera follows them for the camera.
    ServiceStatus {
        serviceName: "org.webosports.service.killswitch"
        clientName: "org.webosports.app.soundrecorder"
        onAvailableChanged: {
            if (available)
                appWindow.subscribeKillSwitch();
            else
                appWindow.micBlocked = false;
        }
    }

    property var killSwitchCall: null
    function subscribeKillSwitch() {
        if (killSwitchCall)
            killSwitchCall.cancel();
        killSwitchCall = service.subscribe("luna://org.webosports.service.killswitch/getStatus",
                                           JSON.stringify({"subscribe": true}),
                                           function(message) {
                                               var payload = JSON.parse(message.payload);
                                               var blocked = false;
                                               var switches = payload.switches || [];
                                               for (var i = 0; i < switches.length; i++) {
                                                   if (switches[i].id === "microphone" && switches[i].state === "blocked")
                                                       blocked = true;
                                               }
                                               appWindow.micBlocked = blocked;
                                           },
                                           function() { appWindow.micBlocked = false; });
    }

    // The switch going on mid-recording: what is recorded so far is kept.
    onMicBlockedChanged: {
        if (micBlocked && recorder.active) {
            recorder.stop();
            notice = "The microphone was switched off; the recording so far is saved.";
        }
    }

    // Needs "application.launcher" and "appmanager.management".
    AppLauncher {
        id: launcher
        clientName: "org.webosports.app.soundrecorder"
    }

    // A new e-mail with the recording attached (com.palm.app.email's
    // "newEmail" launch parameter).
    function sendByEmail(path) {
        launcher.launch("com.palm.app.email", {
            "newEmail": {
                "summary": Recordings.displayName(path),
                "attachments": [{ "fullPath": path, "mimeType": Recordings.mimeForPath(path) }]
            }
        }, undefined, function(error) { appWindow.notice = "Could not open Email: " + error; });
    }

    /* The status bar's app menu relaunches the app with "palm-command":
     * "open-app-menu"; LaunchParams turns that into appMenuRequested. */
    /* {"action": "record"} starts a recording straight away and
     * {"action": "stop"} ends it: for a launcher shortcut or Just Type,
     * and for driving the app from a test over the bus.
     * {"target": "<path or file:// URL>"} opens that recording's player,
     * as the Files app opens a file; {"page": "preferences"} opens the
     * preferences. */
    LaunchParams {
        window: appWindow
        onAppMenuRequested: appMenu.popup(0, 0)
        onLaunched: function(params) {
            // Opened again (from the launcher, from Files): the folder may
            // have changed meanwhile.
            appWindow.recordingsRevision++;
            if (params.action === "record" && !recorder.active)
                appWindow.startRecording();
            else if (params.action === "stop")
                recorder.stop();
            if (params.page === "preferences")
                appWindow.openPreferences();
            if (typeof params.target === "string" && params.target !== "")
                appWindow.openRecording(params.target);
        }
    }

    // Back to the list and the recording's player open, if it is one of ours.
    function openRecording(target) {
        var path = String(target).replace(/^file:\/\//, "");
        if (Recordings.directoryOf(path) !== recordingsPath || !fileOps.exists(path)) {
            notice = "Sound Recorder only plays its own recordings.";
            return;
        }
        pageStack.pop(null);
        recordingsRevision++;
        var page = pageStack.currentItem;
        if (page && page.openPath !== path)
            page.togglePlayer(path);
    }

    function openPreferences() {
        if (!(pageStack.currentItem && pageStack.currentItem.objectName === "preferencesPage"))
            pageStack.push(Qt.resolvedUrl("PreferencesPage.qml"));
    }

    Menu {
        id: appMenu
        LuneOSMenu.appMenuStyle: true

        MenuItem {
            text: "Preferences"
            onTriggered: appWindow.openPreferences()
        }
    }

    // While recording: a dashboard to see the time and stop from anywhere.
    Loader {
        active: recorder.active
        sourceComponent: RecordingDashboard {
            recorder: appWindow.recorder
            onOpenRequested: appWindow.raise()
        }
    }

    // Under the header: trouble, until dismissed.
    Item {
        width: appWindow.width
        height: statusNotice.visible ? statusNotice.height + Units.gu(2) : 0

        StatusNotice {
            id: statusNotice

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            visible: text !== ""
            text: appWindow.micBlocked
                  ? "The microphone is switched off with the privacy switch. Switch it back on to record."
                  : appWindow.notice
            onDismissed: appWindow.notice = ""
        }
    }
}
