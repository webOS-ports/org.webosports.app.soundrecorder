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

.pragma library

/*
 * What the app knows about recordings that is not QML: names, formats,
 * times. No QML types in here, so tests/qml/tst_recordings.qml checks all
 * of it on the build host.
 */

/*
 * The formats offered. Only those Qt Multimedia really writes on LuneOS:
 * asking its GStreamer backend for Ogg Vorbis or Opus gives Ogg FLAC, and
 * AAC picks gst-droid's encoder, which fails on the devices tried (measured
 * on the mindphone, 2026-10-15). "key" is what the preferences store.
 */
var formats = [
    { key: "mp3",  label: "MP3",  ext: ".mp3",  mime: "audio/mpeg", lossless: false },
    { key: "flac", label: "FLAC", ext: ".flac", mime: "audio/flac", lossless: true },
    { key: "wav",  label: "WAV",  ext: ".wav",  mime: "audio/wav",  lossless: true }
];

function format(key) {
    for (var i = 0; i < formats.length; i++) {
        if (formats[i].key === key)
            return formats[i];
    }
    return formats[0];
}

// The files the list shows: everything the app can record, whatever the
// current setting, so changing the format does not hide older recordings.
var extensions = formats.map(function(f) { return f.ext; });

function formatForPath(path) {
    var ext = extensionOf(path);
    for (var i = 0; i < formats.length; i++) {
        if (formats[i].ext === ext)
            return formats[i];
    }
    return null;
}

function mimeForPath(path) {
    var f = formatForPath(path);
    return f ? f.mime : "application/octet-stream";
}

// ".mp3" for "/a/b/Talk.MP3": lower case, with the dot; "" without one.
function extensionOf(path) {
    var name = fileNameOf(path);
    var dot = name.lastIndexOf(".");
    return dot > 0 ? name.substring(dot).toLowerCase() : "";
}

function fileNameOf(path) {
    var s = String(path);
    return s.substring(s.lastIndexOf("/") + 1);
}

// The name the list shows: the file name without its extension.
function displayName(path) {
    var name = fileNameOf(path);
    var dot = name.lastIndexOf(".");
    return dot > 0 ? name.substring(0, dot) : name;
}

function directoryOf(path) {
    var s = String(path);
    var slash = s.lastIndexOf("/");
    return slash > 0 ? s.substring(0, slash) : (slash === 0 ? "/" : "");
}

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

/*
 * The name a new recording gets: "Recording 2026-10-15 06.30.12". Dots in
 * the time, because a colon is not allowed on a FAT card or when the file
 * is copied to Windows. The date first, so names sort by time.
 */
function defaultName(date) {
    return "Recording " + date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
            + " " + pad2(date.getHours()) + "." + pad2(date.getMinutes()) + "." + pad2(date.getSeconds());
}

/*
 * A name the user typed, made safe as a file name: no path separator, no
 * control characters, no leading dot (hidden) or trailing dots and spaces
 * (Windows drops them), at most 120 characters. "" when nothing is left.
 */
function sanitizeName(name) {
    var s = String(name === undefined || name === null ? "" : name);
    s = s.replace(/[\u0000-\u001f\u007f\/\\]/g, " ");
    s = s.replace(/\s+/g, " ").trim();
    s = s.replace(/^\.+/, "").replace(/[. ]+$/, "").trim();
    if (s.length > 120)
        s = s.substring(0, 120).replace(/[. ]+$/, "");
    return s;
}

/*
 * base, or "base (2)", "base (3)"... the first one not in taken (names
 * with their extension), so a recording never overwrites another.
 */
function uniqueName(base, ext, taken) {
    var lower = {};
    for (var i = 0; i < taken.length; i++)
        lower[String(taken[i]).toLowerCase()] = true;
    if (!lower[(base + ext).toLowerCase()])
        return base;
    for (var n = 2; n < 10000; n++) {
        var candidate = base + " (" + n + ")";
        if (!lower[(candidate + ext).toLowerCase()])
            return candidate;
    }
    return base + " " + Date.now();
}

/*
 * A length in milliseconds as a clock: "0:07", "12:34", "1:02:03".
 * The recording timer always shows minutes and seconds with two digits
 * ("00:07"), like the camera's.
 */
function formatDuration(ms, timer) {
    if (!(ms > 0))
        ms = 0;
    var total = Math.floor(ms / 1000);
    var h = Math.floor(total / 3600);
    var m = Math.floor(total / 60) % 60;
    var s = total % 60;
    if (h > 0)
        return h + ":" + pad2(m) + ":" + pad2(s);
    return (timer ? pad2(m) : "" + m) + ":" + pad2(s);
}

// "1.2 MB", "860 KB", "12 bytes".
function formatSize(bytes) {
    if (!(bytes > 0))
        return "0 bytes";
    if (bytes < 1024)
        return bytes + (bytes === 1 ? " byte" : " bytes");
    if (bytes < 1024 * 1024)
        return Math.round(bytes / 1024) + " KB";
    if (bytes < 1024 * 1024 * 1024)
        return (bytes / (1024 * 1024)).toFixed(1) + " MB";
    return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB";
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function clock(date, use24h) {
    if (use24h)
        return pad2(date.getHours()) + ":" + pad2(date.getMinutes());
    var h = date.getHours() % 12;
    return (h === 0 ? 12 : h) + ":" + pad2(date.getMinutes()) + (date.getHours() < 12 ? " AM" : " PM");
}

var monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/*
 * When a recording was made, as the list shows it: "Today 06:30",
 * "Yesterday 18:02", "Mon 12 Oct", and the year only when it is not this
 * year's.
 */
function formatWhen(date, now, use24h) {
    if (sameDay(date, now))
        return "Today " + clock(date, use24h);
    var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
    if (sameDay(date, yesterday))
        return "Yesterday " + clock(date, use24h);
    var s = date.getDate() + " " + monthNames[date.getMonth()];
    if (date.getFullYear() !== now.getFullYear())
        s += " " + date.getFullYear();
    return s;
}

// Does the search box's text match this recording? Every word must occur.
function matches(name, query) {
    var words = String(query).toLowerCase().split(/\s+/).filter(function(w) { return w !== ""; });
    var n = String(name).toLowerCase();
    for (var i = 0; i < words.length; i++) {
        if (n.indexOf(words[i]) < 0)
            return false;
    }
    return true;
}

// Newest first, then by name, for files as FileOperations.list() gives them.
function sortNewestFirst(files) {
    return files.slice().sort(function(a, b) {
        if (a.modified !== b.modified)
            return b.modified - a.modified;
        return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
    });
}

/*
 * The level meter's 0..1 from a peak sample value 0..1: in decibels over
 * the bottom 60 dB, which is how loud it sounds, not how big the number is.
 */
function meterLevel(peak) {
    if (!(peak > 0.001))
        return 0;
    var db = 20 * Math.log(Math.min(peak, 1)) / Math.LN10;
    return Math.max(0, Math.min(1, (db + 60) / 60));
}
