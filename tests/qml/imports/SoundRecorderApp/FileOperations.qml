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

/*
 * Stand-in for the app's C++ FileOperations in the UI tests: the same
 * calls, over a list of files held in memory that a test fills and reads.
 * The real one is tested in tests/unit/test_fileoperations.cpp.
 */
QtObject {
    property string rootPath
    // { path, name, size, modified }
    property var files: []
    property real free: 1e10
    property var calls: []

    function _log(call) { calls = calls.concat([call]); }
    function _ext(name) { var d = name.lastIndexOf("."); return d > 0 ? name.substring(d).toLowerCase() : ""; }

    function ensureRoot() { _log("ensureRoot"); return rootPath !== ""; }
    function list(extensions) {
        _log("list");
        return files.filter(function(f) { return extensions.indexOf(_ext(f.name)) >= 0; });
    }
    function remove(path) {
        _log("remove " + path);
        var before = files.length;
        files = files.filter(function(f) { return f.path !== path; });
        return files.length < before;
    }
    function rename(path, newBaseName) {
        _log("rename " + path + " -> " + newBaseName);
        var f = files.filter(function(x) { return x.path === path; })[0];
        if (!f || newBaseName === "" || newBaseName.indexOf("/") >= 0)
            return "";
        var name = newBaseName + _ext(f.name);
        if (files.some(function(x) { return x.name.toLowerCase() === name.toLowerCase() && x.path !== path; }))
            return "";
        var target = rootPath + "/" + name;
        files = files.map(function(x) {
            return x.path === path ? { path: target, name: name, size: x.size, modified: x.modified } : x;
        });
        return target;
    }
    function exists(path) { return files.some(function(f) { return f.path === path; }); }
    function freeSpace() { return free; }
}
