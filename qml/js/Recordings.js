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
.import LuneOS.Components 1.0 as LC

/*
 * What the app knows about recordings that is not QML: names, formats,
 * times. No QML types in here, so tests/qml/tst_recordings.qml checks all
 * of it on the build host. File names, folders, sizes, days and search are
 * LuneOS.Components' FileLists, as in the other apps.
 */

/*
 * The formats the app knows. "container" and "codec" are Qt Multimedia's
 * MediaFormat.FileFormat and MediaFormat.AudioCodec names; Qt says which it
 * can write on the device, and only those are offered (offered()). "key" is
 * what the preferences store.
 *
 * Measured on the mindphone, 2026-10-15: AAC needs libav's encoder ranked
 * up (SoundRecorderApp/encoderranks.h); Opus needs GStreamer's opusenc
 * (gst-plugins-base built with opus), without which Qt does not offer it
 * and neither does the app.
 */
var formats = [
    { key: "mp3",  label: "MP3",        ext: ".mp3",  mime: "audio/mpeg", lossless: false, container: "MP3",        codec: "MP3" },
    { key: "aac",  label: "AAC (M4A)",  ext: ".m4a",  mime: "audio/mp4",  lossless: false, container: "Mpeg4Audio", codec: "AAC" },
    { key: "ogg",  label: "Ogg Vorbis", ext: ".ogg",  mime: "audio/ogg",  lossless: false, container: "Ogg",        codec: "Vorbis" },
    { key: "opus", label: "Opus",       ext: ".opus", mime: "audio/ogg",  lossless: false, container: "Ogg",        codec: "Opus" },
    { key: "flac", label: "FLAC",       ext: ".flac", mime: "audio/flac", lossless: true,  container: "FLAC",       codec: "FLAC" },
    { key: "wav",  label: "WAV",        ext: ".wav",  mime: "audio/wav",  lossless: true,  container: "Wave",       codec: "Wave" }
];

function format(key) {
    for (var i = 0; i < formats.length; i++) {
        if (formats[i].key === key)
            return formats[i];
    }
    return formats[0];
}

/*
 * The formats to offer: those canEncode(container, codec) says can be
 * written. MP3 always, so there is something to record with.
 */
function offered(canEncode) {
    return formats.filter(function(f) {
        return f === formats[0] || canEncode(f.container, f.codec);
    });
}

// The format for a stored key, or MP3 when that one is not offered (here).
function chosen(key, offeredFormats) {
    for (var i = 0; i < offeredFormats.length; i++) {
        if (offeredFormats[i].key === key)
            return offeredFormats[i];
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
    var ext = LC.FileLists.extensionOf(path);
    return ext !== "" ? "." + ext : "";
}

/*
 * The name a new recording gets: "Recording 2026-10-15 06.30.12". Dots in
 * the time, because a colon is not allowed on a FAT card or when the file
 * is copied to Windows. The date first, so names sort by time.
 */
function defaultName(date) {
    var pad2 = LC.FileLists.pad2;
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
    var total = Math.floor((ms > 0 ? ms : 0) / 1000);
    if (timer && total < 3600)
        return LC.FileLists.pad2(Math.floor(total / 60)) + ":" + LC.FileLists.pad2(total % 60);
    return LC.FileLists.formatClock(ms);
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
