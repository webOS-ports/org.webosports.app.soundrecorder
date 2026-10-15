# The buttons as vectors

The record, stop and round buttons and the bezel behind the record button
are the legacy webOS camera's (`reference/`, from org.webosports.app.camera).
The app uses them redrawn as SVG (`qml/images/*.svg`), so they stay sharp
and smooth at any size, and the icons are rendered from them.

    tools/vectorize/build-artwork.sh [build dir]

builds the two tools, redraws every SVG from its spec, prints how close
each comes to its bitmap, renders the icons and puts 4x and 8x renders of
each button in `<build dir>/scaled`. It needs Qt 6 with Qt SVG
(development files) and python3 with Pillow.

## How they are drawn

`vectorfit` builds each button the way it was drawn: a stack of discs,
rings, half discs and rings cut at the gloss line, and rectangles, each
with a gradient (vertical, horizontal or radial). The specs in `specs/` say
which shapes and where; the colours are not written down anywhere but
solved for.

- **Inner shapes go underneath** the ring around them. Shapes that only
  meet are both anti-aliased along the seam and the seam comes out light;
  this was the largest single error (31 dB with shapes meeting, 39 dB
  with them stacked).
- **Smooth stays smooth.** A soft shadow is one gradient, never a stack of
  steps: the stop face's inner shadow is a radial gradient with its centre
  moved down; the stop square's shadow (offset down) and the pressed one's
  glow are a "glow" - a strip along each side and a quarter disc at each
  corner sharing one profile that fades to nothing, smoothed so it has no
  shoulder. The thin rings at the rims are the originals' rim lines.
- **The colours are the originals'.** The pressed stop is the camera's dark
  red (about 181, 29, 0) and the unpressed one its orange (about 231, 79,
  45), measured to within a few levels.
- **Colours are solved, not picked.** With the shapes fixed, what Qt draws
  is linear in one layer's stop colours (opacities held) and in its stop
  opacities (colours held), so each layer is solved by least squares
  against the bitmap, in turn, round after round. Qt interpolates gradients
  in straight colour, not premultiplied (measured: red at full opacity to
  blue at none gives (127, 0, 127) at half opacity), which is why colours
  and opacities are solved separately.
- **The geometry is searched** around the measured values - centres,
  radii, the gloss line, the rectangles - solving the colours again each
  time. `vectorfit <spec> --freeze` writes the result back into the spec,
  so `build-artwork.sh` gives the same SVG again in a second.

Everything is rendered with QSvgRenderer, the renderer QML uses for SVG on
the device.

## How close they are

`svgcheck compare <svg> <png> [x y w h]` compares premultiplied RGBA (what
is seen once drawn). At 1x, 2026-10-15:

| SVG | PSNR | largest difference | within 2 levels | within 4 |
|---|---|---|---|---|
| bezel | 60.7 dB | 10 | 99.2% | 99.8% |
| stop-pressed | 43.7 dB | 19 | 77.7% | 92.3% |
| stop | 43.2 dB | 22 | 75.5% | 89.6% |
| round-button-pressed | 44.6 dB | 16 | 82.3% | 92.3% |
| record | 42.1 dB | 29 | 75.0% | 89.3% |
| record-pressed | 41.8 dB | 30 | 73.2% | 87.4% |
| round-button | 40.9 dB | 23 | 75.5% | 90.8% |

The fills, the shading and the shadows match to a level or two. What is
left is on anti-aliased edges - the dot's rim, the button's rim lines:
the bitmaps' edges were anti-aliased by the program they were drawn in,
and a vector edge drawn by Qt cannot repeat that bit for bit. Matching
those pixels exactly would take squares for pixels, which would no longer
be smooth when scaled up.

## Checks

The tools are C++ for the build host (x86-64), checked as the app's own
C++ is, except for the cross builds: they never run on a device.

- **Tests:** `tests/run-tests.sh <build dir>`. svgcheck must match a render
  of an SVG with that SVG exactly. vectorfit must give back two known
  designs (`tests/known-*.svg`, rendered and fitted with the same shapes):
  a translucent button whose stops change opacity, and a glow. A frozen
  spec must give the same SVG again. Mutation-checked: writing stops
  premultiplied (Qt interpolates straight colour) fails the button, glow
  corners turned the wrong way fail the glow.
- **Builds:** GCC and Clang, warning-clean with `-Wall -Wextra -Wpedantic
  -Wshadow -Wold-style-cast -Wcast-align -Wformat=2 -Wconversion
  -Wsign-conversion`.
- **Static analysis:** `static-analysis.sh` - gcc `-fanalyzer` at -O0 and
  -O2, the clang analyzer with the alpha checkers, clang-tidy, cppcheck
  (exhaustive, inconclusive), flawfinder and Coccinelle. sparse parses C
  only.
- **Sanitizers:** ASan+UBSan (GCC and Clang) and TSan, on the tests and on
  real specs. Run TSan with `QT_QPA_PLATFORM=offscreen` and
  `TSAN_OPTIONS=suppressions=tests/tsan.supp`: the build host's Qt is not
  built with TSan and its own threads (the raster engine's pool) show as
  races and leaks inside Qt; the file says why each entry is there and
  suppresses nothing with a frame in the tools.
- **valgrind** memcheck: svgcheck render and compare, vectorfit on a test
  design and on the bezel.
