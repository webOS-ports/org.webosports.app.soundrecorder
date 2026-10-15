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

/*
 * How long each recording is, by file name: written when a recording is
 * saved and when the player has read one. Kept here rather than probed for
 * each row of the list: FLAC from GStreamer's encoder carries no length in
 * its header, and opening every file to ask would be slow.
 */
Settings {
    location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
              + "/org.webosports.app.soundrecorder/preferences.ini"
    category: "durations"

    function durationOf(fileName) {
        return Number(value(fileName, 0)) || 0;
    }

    function setDuration(fileName, ms) {
        setValue(fileName, ms > 0 ? Math.round(ms) : 0);
    }

    function renameDuration(oldName, newName) {
        var ms = durationOf(oldName);
        if (ms > 0) {
            setValue(newName, ms);
            setValue(oldName, 0);
        }
    }
}
