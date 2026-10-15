# Sound Recorder tests

## QML (`qml/`), on the build host

    tests/run-qml-tests.sh [path to luneos-components]

- `tst_recordings.qml`: `qml/js/Recordings.js` - names, formats (only
  those Qt can write offered, MP3 always, an unwritable stored one
  recording MP3), times, search, sorting, the meter's decibels.
- `tst_ui.qml`: the app itself, `qml/main.qml` and its pages, with
  luneos-components' desktop stand-ins (`test/imports`) and
  `qml/imports/SoundRecorderApp`, a QML stand-in for the C++ plugin over
  files held in memory. Empty list, order, search, the player opening in
  place, rename (cleaned names, never over another), delete, swipe to
  delete (long swipe asks, Cancel keeps, short swipe springs back), the "…"
  menu, the privacy switch and full storage refusing to record, the
  unfinished recording kept out of the list, preferences (offering the
  formats the recorder can write; mono and the quality reaching the
  recorder, no quality for lossless formats), and the layout at
  320x480, 480x800, 720x720 and 1024x768.

luneos-components needs its desktop build (`CONFIG+=desktop`), with the
LuneOS.Components plugin: its `image://artwork` provider draws the app's
buttons (`ArtworkImage`), and the test that they load fails without it. A
build of it made elsewhere can go ahead of the checkout's with
`tests/run-qml-tests.sh <luneos-components> -import <dir>`. The artwork
cache, like the preferences, goes to a throwaway directory. The style is
named by its module, `QT_QUICK_CONTROLS_STYLE=QtQuick.Controls.LuneOS`: Qt 6
takes a plain "LuneOS" for a module of that name and fails with "module
LuneOS is not installed".

## Unit tests (`unit/`), gtest

The plugin's C++: `FileOperations` (listing, rename that never replaces,
confinement to the folder against "..", symlinks and subfolders),
`AudioPeak::peak` (every sample format, full scale both ways, unaligned
buffers, partial samples), the meter's fall-back and the encoder ranks
(`EncoderRanks`: ours first, so a rank set from outside still wins).

There is no recipe sysroot with Qt Multimedia and googletest together, so
`host-sysroot.sh` puts one together from a build's sysroot components and
`host-toolchain.cmake` builds against it with the host's compiler and the
build's native Qt tools (moc must match the target Qt):

    tests/host-sysroot.sh <build TMPDIR> <sysroot>
    cmake -S . -B build/tests -G Ninja -DBUILD_TESTING=ON \
        -DCMAKE_TOOLCHAIN_FILE=tests/host-toolchain.cmake \
        -DTEST_SYSROOT=<sysroot> -DQT_HOST_PATH=<qtbase-native etc.>/usr
    ninja -C build/tests
    <sysroot>/usr/lib/ld-linux-x86-64.so.2 \
        --library-path <sysroot>/usr/lib:<sysroot>/usr/lib/pulseaudio build/tests/tests/soundrecorder-tests

The script's list of components is what Qt and its libraries needed on
2026-10-15; a later build may need another, from the same
`sysroots-components` directory. The tests were mutation-checked: rename without
`RENAME_NOREPLACE`, no confinement, ignoring negative samples, the wrong
full scale, a meter that never falls and ranks that would override one set
from outside each fail them; so do, in the QML tests, offering formats
without MP3, recording a stored format that cannot be written and a
Channels preference that does not reach the recorder.

## Sanitizers and valgrind

Host compilers with `-fsanitize=address,undefined` (GCC with
`-static-libasan -static-libubsan`, Clang) and `-fsanitize=thread
-static-libtsan`, against the same sysroot, run through its loader. TSan
re-executes itself to turn off address randomisation, which loses the
loader; run it under `setarch x86_64 -R`. Valgrind:

    valgrind --leak-check=full --errors-for-leak-kinds=definite \
        <sysroot>/usr/lib/ld-linux-x86-64.so.2 --library-path ... soundrecorder-tests

## Static analysis

    APP_SYSROOT=<sysroot> tests/static-analysis.sh

gcc `-fanalyzer` at -O0 and -O2, the clang analyzer with the alpha
checkers, clang-tidy, cppcheck (exhaustive, inconclusive), flawfinder, and
Coccinelle with `cocci/`. sparse parses C only.

## Six builds

    tests/build-matrix.sh <build TMPDIR> <x86-64 sysroot> <Qt host dir> <out dir>

GCC and Clang for armv7, aarch64 and x86-64, with `-Wall -Wextra
-Wpedantic -Wshadow -Wold-style-cast` and more; fails on any warning in the
app's code. armv7 GCC prints a `-Wpsabi` note (not a warning) from
libstdc++'s `std::map` header for `QVariantMap`.

## On a device

    tools/install.sh <build dir> <adb serial>
    tools/test-device.sh <adb serial> <name> [seconds]

Records in MP3, AAC, Ogg Vorbis, Opus (when offered: without an Opus
encoder the app records MP3 and the case is skipped), FLAC and WAV, in
mono (MP3, Opus), and in MP3 at Low and at Very high quality (Very high
must come out at least half again Low's bit rate), through the
`record`/`stop` launch actions,
pulls each file and checks with ffprobe/ffmpeg that it is that format, has
sound in it, and is as long as the app says. Screenshots and files go to
`build/test-output/device/<name>/`; the app's preferences are put back and
the test recordings deleted.

Passed on the mindphone (armv7, 480x800) with every case, with LuneOS's
Qt Multimedia patch 0006 and gst-plugins-base's Opus, and on the TouchPad
(armv7, 1024x768) with MP3, FLAC and WAV, 2026-10-15.
