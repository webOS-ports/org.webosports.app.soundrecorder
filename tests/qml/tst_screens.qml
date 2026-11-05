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
import LuneOS.Forms 1.0

/*
 * Every screen of the app on one device's screen per run - the window is
 * the profile's display, with its grid unit (see tests/run-qml-tests.sh,
 * which runs this once per profile in PROFILES). Each screen is checked for
 * what breaks a layout - shown, not empty, inside the window - and saved as
 * build/test-output/ui/<profile>-<screen>.png, with the panel's notch and
 * rounded corners painted over it (PanelShape).
 */
TestCase {
    id: test
    name: "SoundRecorderScreens"
    when: windowShown

    property var app: null
    readonly property string root: "/test/Recordings"
    readonly property string shotDir: decodeURIComponent(Qt.resolvedUrl("../../build/test-output/ui").toString()
                                                         .replace(/^file:\/\//, ""))
    readonly property string profile: Settings.profileName

    Component {
        id: panelShape
        PanelShape {}
    }

    function init_data() {
        return [{ tag: profile + " " + Settings.displayWidth + "x" + Settings.displayHeight }];
    }

    function file(name, minutesAgo, size) {
        return { path: root + "/" + name, name: name, size: size || 1000,
                 modified: Date.now() - (minutesAgo || 0) * 60000 };
    }

    // Three recordings, as tools/screenshots.sh makes them on a device, and
    // one whose name is too long for any screen.
    function someFiles() {
        return [file("Lecture notes.mp3", 3, 145000), file("Interview with Anna.flac", 30, 1200000),
                file("Song idea.wav", 60 * 26, 1050000),
                file("A recording with a rather long name that has to be cut short somewhere.ogg", 60 * 24 * 9, 90000)];
    }

    function startApp(files) {
        var component = Qt.createComponent(Qt.resolvedUrl("../../qml/main.qml"));
        if (component.status !== Component.Ready)
            fail(component.errorString());
        app = component.createObject(null, { recordingsPath: root });
        verify(app !== null, "main.qml did not load");
        compare(app.width, Settings.displayWidth);
        compare(app.height, Settings.displayHeight);
        app.fileOps.files = files || [];
        app.durations.setDuration("Lecture notes.mp3", 9000);
        app.durations.setDuration("Interview with Anna.flac", 14000);
        app.durations.setDuration("Song idea.wav", 6000);
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

    function list() {
        return findChild(page(), "recordingsList");
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
        if (item.contentItem && item.contentItem !== item)
            return findChild(item.contentItem, objectName);
        return null;
    }

    function findButton(item, text) {
        if (!item)
            return null;
        if (item.text === text && item.visible && item.clicked !== undefined)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = findButton(kids[i], text);
            if (found)
                return found;
        }
        if (item.contentItem && item.contentItem !== item)
            return findButton(item.contentItem, text);
        return null;
    }

    function popupOf(item) {
        if (!item)
            return null;
        var objects = item.data || [];
        for (var i = 0; i < objects.length; i++) {
            var o = objects[i];
            if (o && typeof o.popup === "function" && typeof o.itemAt === "function")
                return o;
        }
        var kids = item.children || [];
        for (var j = 0; j < kids.length; j++) {
            var found = popupOf(kids[j]);
            if (found)
                return found;
        }
        return null;
    }

    // The open dialog among an item's objects that tells a recording's
    // details.
    function detailsDialogIn(item) {
        if (!item)
            return null;
        var objects = item.data || [];
        for (var i = 0; i < objects.length; i++) {
            var o = objects[i];
            if (o && o.dialogHeight !== undefined && String(o.message).indexOf("Recorded:") === 0)
                return o;
            var found = detailsDialogIn(o);
            if (found)
                return found;
        }
        return null;
    }

    function dialogOf(item) {
        while (item && (item.opened === undefined || item.dialogHeight === undefined))
            item = item.parent;
        return item;
    }

    function flickableIn(item) {
        if (!item)
            return null;
        if (item.contentHeight !== undefined && item.contentY !== undefined && item.flick !== undefined)
            return item;
        var kids = item.children || [];
        for (var i = 0; i < kids.length; i++) {
            var found = flickableIn(kids[i]);
            if (found)
                return found;
        }
        return null;
    }

    // Shown, not empty and inside the window, left to right; top to bottom
    // too unless it may be scrolled to.
    function onScreen(item, label, scrolls) {
        verify(item, "no " + label);
        verify(item.visible, label + " hidden");
        verify(item.width > 0 && item.height > 0, label + " has no size: " + item.width + "x" + item.height);
        var p = item.mapToItem(null, 0, 0);
        verify(p.x >= -0.5 && p.x + item.width <= app.width + 0.5,
               label + " off the side: x " + p.x + ", width " + item.width + " of " + app.width);
        if (!scrolls)
            verify(p.y >= -0.5 && p.y + item.height <= app.height + 0.5,
                   label + " runs off the bottom: y " + p.y + ", height " + item.height + " of " + app.height);
    }

    // A dialog or menu (a Popup), whole inside the window.
    function popupFits(popup, label) {
        verify(popup.opened, label + " not open");
        verify(popup.width > 0 && popup.height > 0, label + " has no size");
        var p = popup.parent.mapToItem(null, popup.x, popup.y);
        verify(p.x >= -0.5 && p.x + popup.width <= app.width + 0.5,
               label + " off the side: x " + p.x + ", width " + popup.width + " of " + app.width);
        verify(p.y >= -0.5 && p.y + popup.height <= app.height + 0.5,
               label + " off the top or bottom: y " + p.y + ", height " + popup.height + " of " + app.height);
    }

    // The list and the record bar: the screen everything starts from.
    function checkMain() {
        compare(page().title, "Sound Recorder");
        var button = findChild(page(), "recordButton");
        onScreen(button, "the record button");
        // Inside its bar, not cut off by what is under it.
        verify(button.y >= -0.5 && button.y + button.height <= button.parent.height + 0.5,
               "the record button (" + button.height + " high) overhangs its bar (" + button.parent.height + " high)");
        var l = list();
        onScreen(l, "the list");
        verify(l.height >= Units.gu(5), "no room for the list: " + l.height);
        verify(l.mapToItem(null, 0, 0).y >= app.header.height - 0.5, "list under the header");
        verify(l.contentWidth <= l.width + 0.5, "list wider than the window");
        var row = l.itemAtIndex(0);
        if (row)
            verify(row.width <= l.width + 0.5, "row wider than the list");
    }

    function shot(name) {
        wait(300);
        waitForRendering(app.contentItem);
        var shape = panelShape.createObject(app.contentItem);
        if (shape.shaped) {
            shape.requestPaint();
            tryVerify(function() { return shape.done; }, 3000, "panel shape painted");
            waitForRendering(app.contentItem);
        }
        var done = false;
        var saved = false;
        verify(app.contentItem.grabToImage(function(result) {
            saved = result.saveToFile(shotDir + "/" + profile + "-" + name + ".png");
            done = true;
        }), "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
        verify(saved, "could not save " + name + " in " + shotDir);
        shape.destroy();
    }

    function test_empty() {
        startApp([]);
        checkMain();
        compare(list().count, 0);
        shot("empty");
    }

    // The WCAG contrast ratio of two colours
    function contrast(a, b) {
        function lum(c) {
            function lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
        }
        var la = lum(a), lb = lum(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    function test_recordings() {
        startApp(someFiles());
        checkMain();
        compare(list().count, 4);
        for (var i = 0; i < list().count; i++)
            onScreen(findChild(list().itemAtIndex(i), "moreButton"), "row " + i + "'s … button", true);
        // The explanation, where it shows, readable on the foot of the
        // page's gradient it sits on
        var foot = page().footer;
        if (foot.visible) {
            onScreen(foot, "the explanation");
            var c = contrast(foot.color, Colors.pageGradientBottom);
            verify(c >= 3, "the explanation's " + foot.color + " on " + Colors.pageGradientBottom + ": contrast " + c.toFixed(2));
        }
        shot("recordings");
    }

    function test_search() {
        var many = someFiles();
        for (var i = 0; i < 6; i++)
            many.push(file("Take " + (i + 1) + ".mp3", 60 * 24 * (20 + i)));
        startApp(many);
        var search = findChild(page(), "searchField");
        tryVerify(function() { return search.visible; });
        onScreen(search, "the search field");
        checkMain();
        shot("search");
        search.text = "nothing like this";
        tryCompare(list(), "count", 0);
        shot("search-none-found");
    }

    function test_player() {
        startApp(someFiles());
        var row = list().itemAtIndex(1);
        mouseClick(row, row.width / 2, Units.gu(3));
        tryVerify(function() { return findButton(row, "Delete") !== null; });
        wait(400);
        onScreen(findChild(row, "playButton"), "the play button", true);
        onScreen(findChild(row, "seekSlider"), "the slider", true);
        // The stand-in's files are not there to play: the player's
        // complaint about that is not this screen.
        wait(300);
        app.notice = "";
        ["Rename", "Send", "Delete"].forEach(function(t) {
            var b = findButton(row, t);
            verify(b, "no " + t);
            onScreen(b, t, true);
        });
        // The player is in the list's view, not below it.
        var l = list();
        var top = row.mapToItem(l, 0, 0).y;
        verify(top + row.height <= l.height + 1 || top <= 1, "the player below the list's view");
        shot("player");
    }

    function test_menu() {
        startApp(someFiles());
        var more = findChild(list().itemAtIndex(0), "moreButton");
        mouseClick(more);
        var menu = popupOf(page());
        verify(menu, "no menu");
        tryCompare(menu, "opened", true);
        popupFits(menu, "the menu");
        // At the "…" button it was opened from: under it, right edges lined
        // up (on a touch screen there is no pointer for it to open at)
        var m = menu.parent.mapToItem(null, menu.x, menu.y);
        var b = more.mapToItem(null, 0, 0);
        verify(Math.abs(m.x + menu.width - (b.x + more.width)) <= 1 && Math.abs(m.y - (b.y + more.height)) <= 1,
               "the menu at " + m.x + "," + m.y + " (" + menu.width + " wide), not under the … button at "
               + b.x + "," + b.y + " (" + more.width + "x" + more.height + ")");
        shot("menu");
        menu.close();
    }

    function test_details() {
        startApp(someFiles());
        mouseClick(findChild(list().itemAtIndex(1), "moreButton"));
        var menu = popupOf(page());
        tryCompare(menu, "opened", true);
        for (var i = 0; i < menu.count; i++)
            if (menu.itemAt(i).text === "Details")
                mouseClick(menu.itemAt(i));
        tryCompare(menu, "opened", false);
        var dialog = null;
        tryVerify(function() {
            dialog = detailsDialogIn(page());
            return dialog !== null && dialog.opened;
        }, 2000, "the details dialog");
        popupFits(dialog, "the details");
        shot("details");
    }

    function test_rename_dialog() {
        startApp(someFiles());
        page().menuFile = page().shownFiles[0];
        page().askRename();
        var field = findChild(page(), "promptField");
        var dialog = dialogOf(field);
        tryCompare(dialog, "opened", true);
        popupFits(dialog, "the rename dialog");
        onScreen(field, "the name field");
        onScreen(findChild(page(), "promptAcceptButton"), "OK");
        onScreen(findChild(page(), "promptRejectButton"), "Cancel");
        shot("rename-dialog");
    }

    function test_delete_dialog() {
        startApp(someFiles());
        page().menuFile = page().shownFiles[1];
        page().askDelete();
        var accept = findChild(page(), "confirmAcceptButton");
        var dialog = dialogOf(accept);
        tryCompare(dialog, "opened", true);
        popupFits(dialog, "the delete dialog");
        onScreen(accept, "Delete");
        onScreen(findChild(page(), "confirmRejectButton"), "Cancel");
        shot("delete-dialog");
    }

    function test_swipe_delete() {
        startApp(someFiles());
        var row = list().itemAtIndex(0);
        mouseDrag(row, row.width * 0.2, Math.min(30, row.height / 2), row.width * 0.6, 0, Qt.LeftButton, Qt.NoModifier, 5);
        var del = findChild(row, "swipeDeleteButton");
        tryVerify(function() { return del.visible; }, 2000, "no Delete after a long swipe");
        wait(300);
        onScreen(del, "the swipe's Delete", true);
        onScreen(findChild(row, "swipeCancelButton"), "the swipe's Cancel", true);
        shot("swipe-delete");
    }

    function test_notice() {
        startApp(someFiles());
        app.fileOps.free = 1024 * 1024;
        verify(!app.startRecording());
        var close = findChild(app.contentItem, "noticeCloseButton");
        tryVerify(function() { return close && close.visible; });
        onScreen(close, "the notice's close key");
        checkMain();
        shot("notice");
    }

    function test_privacy_switch() {
        startApp(someFiles());
        app.micBlocked = true;
        tryCompare(findChild(page(), "recordButton"), "opacity", 0.4);
        onScreen(findChild(app.contentItem, "noticeCloseButton"), "the notice's close key");
        checkMain();
        shot("privacy-switch");
    }

    // The dashboard: the window the app opens while a recording runs.
    function dashboard() {
        function look(item, depth) {
            if (!item || depth > 8)
                return null;
            if (item.sourceComponent !== undefined && item.item && item.item.windowType === "_WEBOS_WINDOW_TYPE_FLOATING")
                return item.item;
            var objects = item.data || [];
            for (var i = 0; i < objects.length; i++) {
                var found = look(objects[i], depth + 1);
                if (found)
                    return found;
            }
            return null;
        }
        return look(app, 0) || look(app.contentItem, 0);
    }

    function shotOf(window, name) {
        wait(300);
        var done = false;
        var saved = false;
        verify(window.contentItem.grabToImage(function(result) {
            saved = result.saveToFile(shotDir + "/" + profile + "-" + name + ".png");
            done = true;
        }), "grab " + name);
        tryVerify(function() { return done; }, 5000, "saved " + name);
        verify(saved, "could not save " + name);
    }

    // A real recording, from the build host's own microphone, into
    // build/test-output/recordings (deleted after): the recorder is Qt
    // Multimedia's, with no stand-in. Skipped where the host has none.
    function test_recording() {
        var dir = decodeURIComponent(Qt.resolvedUrl("../../build/test-output/recordings").toString()
                                     .replace(/^file:\/\//, ""));
        startApp(someFiles());
        if (app.recorder.inputs.length === 0)
            skip("no microphone on this host");
        app.recordingsPath = dir;
        app.fileOps.rootPath = dir;
        verify(app.startRecording(), app.notice);
        tryVerify(function() { return app.recorder.active || app.recorder.error !== ""; }, 5000, "recording");
        if (!app.recorder.active)
            skip("the host's recorder did not start: " + app.recorder.error);
        wait(1200);
        var button = findChild(page(), "recordButton");
        onScreen(button, "the stop button");
        onScreen(findChild(page(), "pauseButton"), "the pause button");
        verify(button.y + button.height <= button.parent.height + 0.5, "the stop button overhangs its bar");
        if (page().listFitsWhileRecording)
            onScreen(list(), "the list under the recording");
        shot("recording");
        var dash = dashboard();
        verify(dash, "no dashboard");
        verify(dash.width > 0 && dash.width <= Settings.displayWidth && dash.height > 0, "dashboard " + dash.width + "x" + dash.height);
        shotOf(dash, "dashboard");
        app.recorder.pause();
        tryVerify(function() { return app.recorder.paused; }, 3000, "paused");
        shot("recording-paused");
        app.recorder.stop();
        tryVerify(function() { return !app.recorder.active; }, 5000, "stopped");
        wait(300);
    }

    function test_app_menu() {
        startApp(someFiles());
        app.appMenu.popup(0, 0);
        tryCompare(app.appMenu, "opened", true);
        popupFits(app.appMenu, "the app menu");
        shot("app-menu");
        app.appMenu.close();
    }

    function test_preferences() {
        startApp([]);
        app.openPreferences();
        tryCompare(app.pageStack, "busy", false);
        compare(page().objectName, "preferencesPage");
        var flick = flickableIn(page());
        verify(flick, "no Flickable");
        // contentWidth is -1 unless set: what is in it must fit as well.
        var r = flick.contentItem.childrenRect;
        verify(flick.contentWidth <= flick.width + 0.5 && r.width > 0 && r.x >= -0.5 && r.x + r.width <= flick.width + 0.5,
               "the preferences wider than the window: " + r.x + " + " + r.width + " of " + flick.width);
        onScreen(findChild(page(), "formatSelector"), "the format");
        onScreen(findChild(page(), "qualitySelector"), "the quality", true);
        onScreen(findChild(page(), "channelsSelector"), "the channels", true);
        shot("preferences");
        flick.contentY = Math.max(0, flick.contentHeight - flick.height);
        waitForRendering(app.contentItem);
        shot("preferences-end");
    }
}
