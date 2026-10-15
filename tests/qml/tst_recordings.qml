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
import QtTest

import "../../qml/js/Recordings.js" as Recordings

/*
 * qml/js/Recordings.js: names, formats and times. Runs on the build host:
 *
 *     QT_QPA_PLATFORM=offscreen qmltestrunner -input tests/qml
 */
TestCase {
    name: "Recordings"

    function test_formats() {
        compare(Recordings.formats.map(function(f) { return f.key; }),
                ["mp3", "aac", "ogg", "opus", "flac", "wav"]);
        compare(Recordings.format("flac").ext, ".flac");
        compare(Recordings.format("aac").ext, ".m4a");
        compare(Recordings.format("ogg").codec, "Vorbis");
        // An unknown or old setting falls back to the first, MP3.
        compare(Recordings.format("speex").key, "mp3");
        compare(Recordings.format(undefined).key, "mp3");
        compare(Recordings.extensions, [".mp3", ".m4a", ".ogg", ".opus", ".flac", ".wav"]);
    }

    // Only what Qt can write is offered, and MP3 always.
    function test_offered() {
        var asked = [];
        var offered = Recordings.offered(function(container, codec) {
            asked.push(container + "/" + codec);
            return codec !== "Opus" && codec !== "AAC";
        });
        compare(offered.map(function(f) { return f.key; }), ["mp3", "ogg", "flac", "wav"]);
        compare(asked, ["Mpeg4Audio/AAC", "Ogg/Vorbis", "Ogg/Opus", "FLAC/FLAC", "Wave/Wave"]);
        compare(Recordings.offered(function() { return false; }).map(function(f) { return f.key; }),
                ["mp3"]);
    }

    // A stored format that cannot be written here records MP3.
    function test_chosen() {
        var offered = [Recordings.format("mp3"), Recordings.format("ogg")];
        compare(Recordings.chosen("ogg", offered).key, "ogg");
        compare(Recordings.chosen("opus", offered).key, "mp3");
        compare(Recordings.chosen("speex", offered).key, "mp3");
        compare(Recordings.chosen("aac", []).key, "mp3");
    }

    function test_mime() {
        compare(Recordings.mimeForPath("/media/internal/Recordings/a.mp3"), "audio/mpeg");
        compare(Recordings.mimeForPath("/x/Talk.FLAC"), "audio/flac");
        compare(Recordings.mimeForPath("/x/b.wav"), "audio/wav");
        compare(Recordings.mimeForPath("/x/b.m4a"), "audio/mp4");
        compare(Recordings.mimeForPath("/x/b.ogg"), "audio/ogg");
        compare(Recordings.mimeForPath("/x/notes.txt"), "application/octet-stream");
        compare(Recordings.formatForPath("/x/noext"), null);
    }

    function test_paths() {
        compare(Recordings.extensionOf("/a/b/Talk.MP3"), ".mp3");
        compare(Recordings.extensionOf("/a/b.c/noext"), "");
        // A leading dot is a hidden file, not an extension.
        compare(Recordings.extensionOf("/a/.hidden"), "");
        compare(Recordings.fileNameOf("/a/b/c d.mp3"), "c d.mp3");
        compare(Recordings.fileNameOf("plain.wav"), "plain.wav");
        compare(Recordings.displayName("/a/Meeting 3.2.mp3"), "Meeting 3.2");
        compare(Recordings.displayName("/a/noext"), "noext");
        compare(Recordings.directoryOf("/media/internal/Recordings/x.mp3"), "/media/internal/Recordings");
        compare(Recordings.directoryOf("/x.mp3"), "/");
        compare(Recordings.directoryOf("x.mp3"), "");
    }

    function test_defaultName() {
        compare(Recordings.defaultName(new Date(2026, 9, 15, 6, 30, 2)), "Recording 2026-10-15 06.30.02");
        compare(Recordings.defaultName(new Date(2027, 0, 1, 23, 5, 59)), "Recording 2027-01-01 23.05.59");
        // Nothing a file system or Windows would refuse.
        verify(!/[:\/\\]/.test(Recordings.defaultName(new Date())));
    }

    function test_sanitizeName_data() {
        return [
            { tag: "plain", input: "Lecture 3", expected: "Lecture 3" },
            { tag: "trimmed", input: "  Lecture   3  ", expected: "Lecture 3" },
            { tag: "slash", input: "a/b\\c", expected: "a b c" },
            { tag: "control", input: "a\u0000b\nc\td", expected: "a b c d" },
            { tag: "hidden", input: "..secret", expected: "secret" },
            { tag: "trailing dots", input: "Notes...", expected: "Notes" },
            { tag: "parent", input: "..", expected: "" },
            { tag: "empty", input: "   ", expected: "" },
            { tag: "undefined", input: undefined, expected: "" },
            { tag: "unicode", input: "Tromsø – møte", expected: "Tromsø – møte" }
        ];
    }

    function test_sanitizeName(data) {
        compare(Recordings.sanitizeName(data.input), data.expected);
    }

    function test_sanitizeName_length() {
        var longName = new Array(200).join("x");
        compare(Recordings.sanitizeName(longName).length, 120);
        // Cutting must not leave a trailing dot or space behind.
        var dotted = new Array(120).join("a") + ". tail";
        verify(!/[. ]$/.test(Recordings.sanitizeName(dotted)));
    }

    function test_uniqueName() {
        compare(Recordings.uniqueName("Talk", ".mp3", []), "Talk");
        compare(Recordings.uniqueName("Talk", ".mp3", ["Talk.wav"]), "Talk");
        compare(Recordings.uniqueName("Talk", ".mp3", ["Talk.mp3"]), "Talk (2)");
        compare(Recordings.uniqueName("Talk", ".mp3", ["talk.MP3", "Talk (2).mp3"]), "Talk (3)");
    }

    function test_formatDuration() {
        compare(Recordings.formatDuration(0), "0:00");
        compare(Recordings.formatDuration(-5), "0:00");
        compare(Recordings.formatDuration(undefined), "0:00");
        compare(Recordings.formatDuration(7999), "0:07");
        compare(Recordings.formatDuration(754000), "12:34");
        compare(Recordings.formatDuration(3723000), "1:02:03");
        compare(Recordings.formatDuration(7000, true), "00:07");
        compare(Recordings.formatDuration(3723000, true), "1:02:03");
    }

    function test_formatSize() {
        compare(Recordings.formatSize(0), "0 bytes");
        compare(Recordings.formatSize(1), "1 byte");
        compare(Recordings.formatSize(1023), "1023 bytes");
        compare(Recordings.formatSize(880640), "860 KB");
        compare(Recordings.formatSize(1258291), "1.2 MB");
        compare(Recordings.formatSize(3 * 1024 * 1024 * 1024), "3.00 GB");
    }

    function test_formatWhen() {
        var now = new Date(2026, 9, 15, 9, 0, 0);
        compare(Recordings.formatWhen(new Date(2026, 9, 15, 6, 30), now, true), "Today 06:30");
        compare(Recordings.formatWhen(new Date(2026, 9, 15, 18, 5), now, false), "Today 6:05 PM");
        compare(Recordings.formatWhen(new Date(2026, 9, 15, 0, 5), now, false), "Today 12:05 AM");
        compare(Recordings.formatWhen(new Date(2026, 9, 14, 23, 59), now, true), "Yesterday 23:59");
        compare(Recordings.formatWhen(new Date(2026, 9, 12, 10, 0), now, true), "12 Oct");
        compare(Recordings.formatWhen(new Date(2025, 11, 31, 10, 0), now, true), "31 Dec 2025");
        // Yesterday across a month boundary.
        compare(Recordings.formatWhen(new Date(2026, 8, 30, 8, 0), new Date(2026, 9, 1, 8, 0), true), "Yesterday 08:00");
    }

    function test_matches() {
        verify(Recordings.matches("Lecture 3 physics", ""));
        verify(Recordings.matches("Lecture 3 physics", "LECTURE"));
        verify(Recordings.matches("Lecture 3 physics", "physics lec"));
        verify(!Recordings.matches("Lecture 3 physics", "chemistry"));
    }

    function test_sortNewestFirst() {
        var files = [{ name: "b", modified: 10 }, { name: "a", modified: 20 }, { name: "c", modified: 10 }];
        compare(Recordings.sortNewestFirst(files).map(function(f) { return f.name; }), ["a", "b", "c"]);
        // The input is left as it was.
        compare(files[0].name, "b");
    }

    function test_meterLevel() {
        compare(Recordings.meterLevel(0), 0);
        compare(Recordings.meterLevel(undefined), 0);
        compare(Recordings.meterLevel(1), 1);
        compare(Recordings.meterLevel(2), 1);
        // -20 dB is two thirds up a 60 dB meter.
        fuzzyCompare(Recordings.meterLevel(0.1), 2 / 3, 0.0001);
        fuzzyCompare(Recordings.meterLevel(0.001001), 0, 0.001);
    }
}
