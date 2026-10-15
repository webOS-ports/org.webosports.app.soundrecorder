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
import QtTest

import LunaNext.Common 0.1

import "../../qml/js/Recordings.js" as Recordings

/*
 * The app itself - qml/main.qml with its pages - on the build host, with
 * luneos-components' desktop stand-ins for the bus and the window and
 * tests/qml/imports for the app's C++ plugin. Run by tests/run-qml-tests.sh.
 */
TestCase {
    id: test
    name: "SoundRecorderUi"
    when: windowShown

    property var app: null
    readonly property string root: "/test/Recordings"

    function file(name, minutesAgo, size) {
        return { path: root + "/" + name, name: name, size: size || 1000,
                 modified: Date.now() - (minutesAgo || 0) * 60000 };
    }

    function createApp(files, width, height) {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        app = component.createObject(null, { recordingsPath: root });
        verify(app !== null, "main.qml did not load");
        if (width) {
            app.width = width;
            app.height = height;
        }
        app.fileOps.files = files || [];
        app.recordingsRevision++;
        waitForRendering(app.contentItem);
        return app;
    }

    function cleanup() {
        if (app) {
            app.destroy();
            app = null;
        }
    }

    function page() {
        return app.pageStack.currentItem;
    }

    function findChild(item, objectName) {
        if (!item)
            return null;
        if (item.objectName === objectName)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findChild(kids[i], objectName);
            if (found)
                return found;
        }
        // Delegates of a ListView live in its contentItem.
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function list() {
        return findChild(page(), "recordingsList");
    }

    function test_empty_list_says_how_to_start() {
        createApp([]);
        compare(page().title, "Sound Recorder");
        compare(list().count, 0);
        verify(findChild(page(), "recordButton").visible);
        // The pause button only shows while recording.
        verify(!findChild(page(), "pauseButton").visible);
    }

    function test_vector_buttons_load_at_their_size() {
        createApp([]);
        var button = findChild(page(), "recordButton");
        var image = button.children[0];
        tryCompare(image, "status", Image.Ready);
        verify(/record\.svg$/.test(image.source.toString()), image.source);
        // Rendered at the size shown, not scaled from a bitmap.
        compare(image.sourceSize.width, Math.ceil(button.width));
        var bezel = button.parent.children[0];
        tryCompare(bezel, "status", Image.Ready);
        verify(/bezel\.svg$/.test(bezel.source.toString()), bezel.source);
    }

    function test_recordings_newest_first() {
        createApp([file("Old.mp3", 120, 2048), file("New.flac", 1, 4096), file("notes.txt", 0)]);
        compare(list().count, 2, "only the recordings, not notes.txt");
        compare(page().shownFiles[0].name, "New.flac");
        compare(page().shownFiles[1].name, "Old.mp3");
    }

    function test_search_shows_once_there_are_six() {
        createApp([file("a.mp3", 1), file("b.mp3", 2)]);
        verify(!findChild(page(), "searchField").visible);
        var many = [];
        for (var i = 0; i < 6; i++)
            many.push(file("Lecture " + i + ".mp3", i));
        many.push(file("Interview.mp3", 10));
        app.fileOps.files = many;
        app.recordingsRevision++;
        var search = findChild(page(), "searchField");
        tryVerify(function() { return search.visible; });
        search.text = "interv";
        tryCompare(list(), "count", 1);
        compare(page().shownFiles[0].name, "Interview.mp3");
        search.text = "nothing like this";
        tryCompare(list(), "count", 0);
    }

    function test_list_follows_files_changed_elsewhere() {
        createApp([file("A.mp3", 1)]);
        compare(list().count, 1);
        // Deleted behind the app's back, then the app becomes active again.
        app.fileOps.files = [];
        app.recordingsRevision++;
        tryCompare(list(), "count", 0);
    }

    function test_tapping_a_recording_opens_and_closes_its_player() {
        createApp([file("Talk.mp3", 1)]);
        var row = list().itemAtIndex(0);
        verify(row);
        var closedHeight = row.height;
        mouseClick(row, row.width / 2, closedHeight / 2);
        compare(page().openPath, root + "/Talk.mp3");
        tryVerify(function() { return row.height > closedHeight * 2; });
        verify(findChild(row, "playButton").visible);
        mouseClick(row, row.width / 2, closedHeight / 2);
        compare(page().openPath, "");
        tryCompare(row, "height", closedHeight);
    }

    function test_rename_cleans_the_name_and_keeps_the_extension() {
        createApp([file("Recording 1.mp3", 1)]);
        page().renameFile(page().files[0], "  Lecture/3  ");
        compare(app.fileOps.files[0].name, "Lecture 3.mp3");
        compare(app.notice, "");
    }

    function test_rename_never_replaces_another_recording() {
        createApp([file("A.mp3", 1), file("B.mp3", 2)]);
        var a = page().files.filter(function(f) { return f.name === "A.mp3"; })[0];
        page().renameFile(a, "B");
        verify(app.fileOps.files.some(function(f) { return f.name === "A.mp3"; }), "A was renamed over B");
        verify(app.notice.indexOf("already a recording") >= 0, app.notice);
    }

    function test_rename_to_nothing_does_nothing() {
        createApp([file("A.mp3", 1)]);
        page().renameFile(page().files[0], " ... ");
        compare(app.fileOps.files[0].name, "A.mp3");
        verify(app.fileOps.calls.every(function(c) { return c.indexOf("rename") !== 0; }));
    }

    function test_delete_removes_the_file_and_its_length() {
        createApp([file("A.mp3", 1), file("B.mp3", 2)]);
        app.durations.setDuration("A.mp3", 5000);
        var a = page().files.filter(function(f) { return f.name === "A.mp3"; })[0];
        page().removeFile(a);
        compare(app.fileOps.files.length, 1);
        compare(list().count, 1);
        compare(app.durations.durationOf("A.mp3"), 0);
    }

    function test_recording_in_progress_is_not_listed() {
        createApp([file("Done.mp3", 5), file("Now.mp3", 0, 0)]);
        compare(list().count, 2);
        app.recorder.currentPath = root + "/Now.mp3";
        tryCompare(list(), "count", 1);
        compare(page().shownFiles[0].name, "Done.mp3");
        app.recorder.currentPath = "";
    }

    function test_privacy_switch_blocks_recording() {
        createApp([]);
        app.micBlocked = true;
        var button = findChild(page(), "recordButton");
        tryCompare(button, "opacity", 0.4);
        verify(!app.startRecording());
        verify(app.recorder.active === false);
        // The notice says why.
        verify(app.notice.indexOf("privacy switch") >= 0, app.notice);
    }

    function test_no_recording_when_storage_is_full() {
        createApp([]);
        app.fileOps.free = 1024 * 1024;
        verify(!app.startRecording());
        verify(app.notice.indexOf("free space") >= 0, app.notice);
    }

    function swipeRow(row, fraction) {
        mouseDrag(row, row.width * 0.2, row.height / 2 > 30 ? 30 : row.height / 2, row.width * fraction, 0, Qt.LeftButton, Qt.NoModifier, 5);
    }

    function test_swipe_far_asks_then_deletes() {
        createApp([file("A.mp3", 1), file("B.mp3", 2)]);
        var row = list().itemAtIndex(0);
        swipeRow(row, 0.6);
        var del = findChild(row, "swipeDeleteButton");
        tryVerify(function() { return del.visible; }, 2000, "no Delete after a long swipe");
        compare(app.fileOps.files.length, 2, "deleted before confirming");
        mouseClick(del);
        compare(app.fileOps.files.length, 1);
        compare(app.fileOps.files[0].name, "B.mp3");
        tryCompare(list(), "count", 1);
    }

    function test_swipe_then_cancel_keeps_it() {
        createApp([file("A.mp3", 1)]);
        var row = list().itemAtIndex(0);
        swipeRow(row, -0.6);
        var cancel = findChild(row, "swipeCancelButton");
        tryVerify(function() { return cancel.visible; }, 2000);
        mouseClick(cancel);
        compare(app.fileOps.files.length, 1);
        tryVerify(function() { return !cancel.visible; });
    }

    function test_short_swipe_springs_back() {
        createApp([file("A.mp3", 1)]);
        var row = list().itemAtIndex(0);
        swipeRow(row, 0.15);
        wait(300);
        verify(!findChild(row, "swipeDeleteButton").visible);
        compare(app.fileOps.files.length, 1);
    }

    function test_more_button_opens_the_menu() {
        createApp([file("A.mp3", 1)]);
        var row = list().itemAtIndex(0);
        mouseClick(findChild(row, "moreButton"));
        compare(page().menuFile.name, "A.mp3");
        // Tapping "…" is not tapping the row: no player opens.
        compare(page().openPath, "");
    }

    function test_target_opens_that_recordings_player() {
        createApp([file("A.mp3", 1), file("B.mp3", 2)]);
        app.openRecording("file://" + root + "/B.mp3");
        compare(page().openPath, root + "/B.mp3");
        // Asking again keeps it open rather than closing it.
        app.openRecording(root + "/B.mp3");
        compare(page().openPath, root + "/B.mp3");
    }

    function test_target_outside_the_folder_is_refused() {
        createApp([file("A.mp3", 1)]);
        app.openRecording("/etc/passwd");
        compare(page().openPath, "");
        verify(app.notice.indexOf("own recordings") >= 0, app.notice);
        app.openRecording(root + "/missing.mp3");
        compare(page().openPath, "");
    }

    function test_preferences_page() {
        createApp([]);
        app.openPreferences();
        tryCompare(app.pageStack, "busy", false);
        compare(app.pageStack.currentItem.objectName, "preferencesPage");
        // Asking again does not stack a second one.
        app.openPreferences();
        compare(app.pageStack.depth, 2);
    }

    // In grid units, as the device sizes things: the Q25's square while its
    // recording dashboard takes a row is about 50 high, a phone about 70.
    function test_list_gives_way_to_recording_on_a_short_screen_data() {
        return [
            { tag: "short (Q25 while recording)", w: 65, h: 50, fits: false },
            { tag: "phone", w: 45, h: 72, fits: true },
            { tag: "tablet", w: 100, h: 72, fits: true }
        ];
    }

    function test_list_gives_way_to_recording_on_a_short_screen(data) {
        createApp([file("A.mp3", 1)], Units.gu(data.w), Units.gu(data.h));
        compare(page().listFitsWhileRecording, data.fits);
    }

    function test_layout_fits_data() {
        return [
            { tag: "phone 480x800", w: 480, h: 800 },
            { tag: "Q25 720x720", w: 720, h: 720 },
            { tag: "small 320x480", w: 320, h: 480 },
            { tag: "tablet 1024x768", w: 1024, h: 768 }
        ];
    }

    function test_layout_fits(data) {
        createApp([file("A recording with a rather long name that has to be cut short somewhere.mp3", 1)], data.w, data.h);
        var button = findChild(page(), "recordButton");
        var p = button.mapToItem(null, 0, 0);
        verify(p.y + button.height <= app.height + 0.5, "record button below the window: " + (p.y + button.height));
        verify(p.x >= 0 && p.x + button.width <= app.width + 0.5, "record button off the side");
        var l = list();
        var lp = l.mapToItem(null, 0, 0);
        verify(l.height >= 40, "no room for the list: " + l.height);
        verify(lp.y >= app.header.height - 0.5, "list under the header");
        var row = l.itemAtIndex(0);
        verify(row.width <= l.width + 0.5, "row wider than the list");
    }
}
