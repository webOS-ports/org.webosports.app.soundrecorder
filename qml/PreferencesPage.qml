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
import LuneOS.Forms 1.0

import "js/Recordings.js" as Recordings

/*
 * How recordings are made: format, quality, which microphone and how
 * loud. They apply to the next recording.
 *
 * There is no mono/stereo choice: Qt Multimedia's GStreamer backend
 * records two channels whatever MediaRecorder.audioChannelCount says
 * (measured on the mindphone, 2026-10-15).
 */
AppPage {
    id: page

    objectName: "preferencesPage"
    title: "Preferences"

    readonly property var prefs: appWindow.prefs
    readonly property var recorder: appWindow.recorder

    Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight + Units.gu(2)
        clip: true

        ColumnLayout {
            id: content

            x: Units.gu(1)
            y: Units.gu(1)
            width: parent.width - Units.gu(2)
            spacing: Units.gu(1)

            FormGroup {
                Layout.fillWidth: true
                title: "Recording"

                LabelAndSelector {
                    label: "Format"
                    model: Recordings.formats.map(function(f) { return f.label; })
                    values: Recordings.formats.map(function(f) { return f.key; })
                    value: Recordings.format(page.prefs.format).key
                    onChosen: (v) => page.prefs.format = v
                }
                LabelAndSelector {
                    label: "Quality"
                    // Lossless formats have no quality to choose.
                    visible: !Recordings.format(page.prefs.format).lossless
                    model: ["Low", "Normal", "High", "Very high"]
                    values: [MediaRecorder.LowQuality, MediaRecorder.NormalQuality,
                             MediaRecorder.HighQuality, MediaRecorder.VeryHighQuality]
                    value: page.prefs.quality
                    onChosen: (v) => page.prefs.quality = v
                }
            }

            ExplanationText {
                Layout.fillWidth: true
                text: "MP3 is small and plays everywhere. FLAC and WAV keep every detail: FLAC at about half the size of WAV, WAV for software that knows nothing else."
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Microphone"

                LabelAndSelector {
                    label: "Input"
                    // The system's choice first; its id is "", which follows
                    // a headset being plugged in.
                    readonly property var devices: page.recorder.inputs
                    model: ["Default"].concat(devices.map(function(d) { return d.description; }))
                    values: [""].concat(devices.map(function(d) { return page.recorder.deviceIdString(d); }))
                    value: values.indexOf(page.prefs.inputId) >= 0 ? page.prefs.inputId : ""
                    onChosen: (v) => page.prefs.inputId = v
                }
                LabelAndSlider {
                    label: "Input level"
                    from: 0
                    to: 100
                    stepSize: 5
                    value: Math.round(page.prefs.inputVolume * 100)
                    format: function(v) { return Math.round(v) + "%"; }
                    onMoved: (v) => page.prefs.inputVolume = v / 100
                }
            }

            FormGroup {
                Layout.fillWidth: true
                title: "Storage"

                LabelAndValue {
                    label: "Folder"
                    value: appWindow.recordingsPath
                }
                LabelAndValue {
                    label: "Free"
                    value: {
                        var free = appWindow.fileOps.freeSpace();
                        return free >= 0 ? Recordings.formatSize(free) : "Unknown";
                    }
                }
            }
        }
    }
}
