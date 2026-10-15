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
import QtMultimedia

import "js/Recordings.js" as Recordings

/*
 * Records the microphone to a file: Qt Multimedia's CaptureSession with an
 * AudioInput and a MediaRecorder, and nothing else.
 *
 * The session lives in a Loader so it can be thrown away and made again:
 * once Qt's GStreamer pipeline has failed (an encoder that will not start),
 * every later recording in the same session fails too.
 */
Item {
    id: engine

    // What the next recording is made with (PreferencesModel).
    property string formatKey: "mp3"
    property int quality: MediaRecorder.NormalQuality
    // QAudioDevice.id as a string, "" for the system's default input.
    property string inputId: ""
    property real inputVolume: 1.0

    readonly property MediaRecorder mediaRecorder: session.item ? session.item.recorder : null
    readonly property bool recording: !!mediaRecorder && mediaRecorder.recorderState === MediaRecorder.RecordingState
    readonly property bool paused: !!mediaRecorder && mediaRecorder.recorderState === MediaRecorder.PausedState
    readonly property bool active: recording || paused
    // How long the current recording has run, in ms.
    readonly property real duration: mediaRecorder ? mediaRecorder.duration : 0

    // The file being written, and the last error in words ("" for none).
    property string currentPath: ""
    property string error: ""

    // A recording is finished and on disk.
    signal saved(string path, real durationMs)
    // A recording failed; what was written of it is at path (may be empty).
    signal failed(string path, string reason)

    readonly property var inputs: mediaDevices.audioInputs

    // QAudioDevice.id is a QByteArray, an ArrayBuffer in QML.
    function deviceIdString(device) {
        if (!device || !device.id)
            return "";
        var bytes = new Uint8Array(device.id);
        var s = "";
        for (var i = 0; i < bytes.length; i++)
            s += String.fromCharCode(bytes[i]);
        return s;
    }

    function inputDevice() {
        if (inputId !== "") {
            for (var i = 0; i < inputs.length; i++) {
                if (deviceIdString(inputs[i]) === inputId)
                    return inputs[i];
            }
        }
        return mediaDevices.defaultAudioInput;
    }

    /*
     * Starts recording to path (with its extension). Returns false when
     * the recorder is not ready; error says why.
     */
    function start(path) {
        if (active || !mediaRecorder)
            return false;
        error = "";
        lastDuration = 0;
        stopping = false;

        var f = Recordings.format(formatKey);
        var mf = mediaRecorder.mediaFormat;
        mf.fileFormat = f.key === "flac" ? MediaFormat.FLAC : f.key === "wav" ? MediaFormat.Wave : MediaFormat.MP3;
        mf.audioCodec = f.key === "flac" ? MediaFormat.FLAC : f.key === "wav" ? MediaFormat.Wave : MediaFormat.MP3;
        mf.videoCodec = MediaFormat.Unspecified;
        mediaRecorder.mediaFormat = mf;
        mediaRecorder.quality = quality;
        session.item.audioInput.device = inputDevice();
        session.item.audioInput.volume = inputVolume;

        currentPath = path;
        mediaRecorder.outputLocation = "file://" + path;
        mediaRecorder.record();
        return true;
    }

    function pause() {
        if (recording)
            mediaRecorder.pause();
    }

    function resume() {
        if (paused)
            mediaRecorder.record();
    }

    function stop() {
        if (!active)
            return;
        stopping = true;
        mediaRecorder.stop();
    }

    // Followed while recording: the recorder's duration is 0 again once it
    // has stopped, and saved() should say how long the recording was.
    property real lastDuration: 0
    property bool stopping: false

    function reset() {
        session.active = false;
        session.active = true;
    }

    MediaDevices {
        id: mediaDevices
    }

    Loader {
        id: session

        sourceComponent: CaptureSession {
            audioInput: AudioInput {}

            recorder: MediaRecorder {
                onDurationChanged: function(ms) { if (ms > 0) engine.lastDuration = ms; }

                onRecorderStateChanged: {
                    if (recorderState !== MediaRecorder.StoppedState || engine.currentPath === "")
                        return;
                    var path = engine.currentPath;
                    engine.currentPath = "";
                    if (engine.error === "")
                        engine.saved(path, engine.lastDuration);
                }

                onErrorOccurred: function(code, message) {
                    console.warn("Recorder: " + message);
                    engine.error = message || "Recording failed";
                    var path = engine.currentPath;
                    engine.currentPath = "";
                    engine.failed(path, engine.error);
                    // A failed pipeline stays failed: start again from scratch.
                    Qt.callLater(engine.reset);
                }
            }
        }
    }
}
