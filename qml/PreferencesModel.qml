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

import QtCore
import QtMultimedia

/*
 * The app's preferences. Every property here is saved; how long each
 * recording is lives in DurationStore.
 */
Settings {
    id: prefs

    // Not a QSettings organisation/application pair: the QML runner is
    // shared by every QML app, so the file is named explicitly (as Camera).
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
              + "/org.webosports.app.soundrecorder/preferences.ini"
    category: "recording"

    property string format: "mp3"
    property int quality: MediaRecorder.NormalQuality
    // 2 for stereo, 1 for mono.
    property int channels: 2
    property string inputId: ""
    property real inputVolume: 1.0
    // Off by default: the screen is what uses the battery.
    property bool keepScreenOn: false
}
