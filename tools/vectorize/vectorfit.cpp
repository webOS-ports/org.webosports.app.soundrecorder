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

/*
 * vectorfit <spec.json> [--freeze]
 *
 * Redraws a button bitmap (the legacy camera's) as SVG that Qt renders
 * like the original, and that stays smooth at any size.
 *
 * The picture is a stack of layers, bottom first, the way it was drawn:
 * discs, rings, their upper or lower halves (cut at the gloss line),
 * rectangles, each filled with a gradient - vertical (lit from above),
 * horizontal (a shadow beside something) or radial (a bevel's profile, a
 * shadow; an inner shadow lit from above is a radial gradient whose centre
 * is moved down). An inner shape goes on underneath
 * the ring around it rather than meeting it edge to edge: two shapes that
 * only meet are both anti-aliased along the seam and the seam comes out too
 * light, at every size.
 *
 * Qt interpolates a gradient's colours and its opacity separately (in
 * straight, not premultiplied, colour - measured: red at full opacity to
 * blue at none gives (127, 0, 127) at half opacity), multiplies by the
 * anti-aliased coverage and composites "over". So with the other layers
 * held, what Qt draws is linear in one layer's stop colours once its stop
 * opacities are fixed, and linear in the opacities once the colours are.
 * Each layer is solved by least squares against the original, colours and
 * opacities in turn, layer after layer and round after round, with a little
 * smoothing between neighbour stops. Then the geometry - centre, radii, the gloss line, the
 * shadow - is refined by searching around the measured values, solving
 * again each time. Everything is rendered with QSvgRenderer, as QML draws
 * SVG on the device.
 *
 * spec.json:
 *   { "png": "...", "crop": [x, y, w, h], "out": "x.svg",
 *     "cx": 60, "cy": 60, "split": 60, "stops": 16, "smooth": 0.02, "rounds": 12,
 *     "layers": [
 *       { "shape": "disc", "r": 60, "cx": 60, "cy": 64, "fill": "radial", "stops": 24, "hole": 48 },
 *       { "shape": "disc", "r": 48, "half": "top" },
 *       { "shape": "ring", "ri": 41, "r": 48, "fill": "radial" },
 *       { "shape": "rect", "x": .., "y": .., "w": .., "h": .., "rx": 1 },
 *       { "shape": "glow", "x": .., "y": .., "w": .., "h": .., "d": 8, "fade": true } ],
 *     "refine": ["cx", "cy", "split", "radii", "centres", "rects"], "passes": 4 }
 *
 * A layer without cx/cy is centred on the spec's; "half" cuts it at
 * "split"; "hole" punches a disc of that radius out of it; "fade" makes its
 * last stop fully transparent, so a soft shadow has no edge; "smooth"
 * multiplies the smoothing between its stops (a glow's profile must not
 * get a shoulder). Paths are
 * relative to the spec. --freeze writes the refined geometry back into the
 * spec with "passes" 0, so it gives the same SVG again in a second.
 */

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QTextStream>
#include <QtGui/QGuiApplication>
#include <QtGui/QImage>
#include <QtGui/QPainter>
#include <QtSvg/QSvgRenderer>

#include <algorithm>
#include <iterator>
#include <numeric>
#include <array>
#include <cmath>
#include <vector>

namespace {

// Index into a row-major n x n matrix, and a non-negative int as a size.
inline size_t at(long i, long j, long n)
{
    return static_cast<size_t>(i * n + j);
}

inline size_t sz(long v)
{
    return static_cast<size_t>(v);
}

struct Layer {
    QString shape = QStringLiteral("disc");  // disc, ring, rect
    QString half;                            // "", "top", "bottom"
    bool ownCentre = false;
    double cx = 0, cy = 0, r = 0, ri = 0, hole = 0;
    double x = 0, y = 0, w = 0, h = 0, rx = 0;
    double d = 0;  // glow: how far it reaches out from the rectangle
    bool radial = false;
    bool horizontal = false;  // a linear gradient across x instead of down y
    bool fade = false;        // the last stop fully transparent: no edge
    double smooth = 1.0;      // times the spec's smoothing between stops
    int stops = 16;
};

struct Spec {
    double cx = 0, cy = 0, split = 0;
    std::vector<Layer> layers;
};

int g_width = 0, g_height = 0;
double g_smooth = 0.02;
int g_rounds = 12;
QImage g_original;  // premultiplied, crop size

QString num(double v)
{
    return QString::number(v, 'f', 4);
}

QString circlePath(double cx, double cy, double r)
{
    return QStringLiteral("M%1,%2 A%3,%3 0 1,1 %4,%2 A%3,%3 0 1,1 %1,%2 Z")
        .arg(num(cx - r), num(cy), num(r), num(cx + r));
}

QString rectPath(double x, double y, double w, double h, double rx)
{
    if (rx <= 0)
        return QStringLiteral("M%1,%2 H%3 V%4 H%1 Z").arg(num(x), num(y), num(x + w), num(y + h));
    const double k = std::min({rx, w / 2, h / 2});
    return QStringLiteral("M%1,%2 H%3 A%5,%5 0 0,1 %4,%6 V%7 A%5,%5 0 0,1 %3,%8 H%1 A%5,%5 0 0,1 %9,%7 V%6 A%5,%5 0 0,1 %1,%2 Z")
        .arg(num(x + k), num(y), num(x + w - k), num(x + w), num(k), num(y + k), num(y + h - k), num(y + h), num(x));
}

// The part of a disc (ri 0) or ring above (top) or below the line y = s.
QString halfPath(double cx, double cy, double ri, double ro, double s, bool top)
{
    const double d = s - cy;
    const double xo = std::sqrt(std::max(0.0, ro * ro - d * d));
    const bool hole = ri > std::fabs(d);
    const double xi = hole ? std::sqrt(ri * ri - d * d) : 0.0;
    const int large = top ? (d > 0 ? 1 : 0) : (d < 0 ? 1 : 0);
    QString p;
    if (top) {
        p = QStringLiteral("M%1,%2 A%3,%3 0 %4,1 %5,%2 ").arg(num(cx - xo), num(s), num(ro)).arg(large).arg(num(cx + xo));
        if (hole)
            p += QStringLiteral("L%1,%2 A%3,%3 0 %4,0 %5,%2 ").arg(num(cx + xi), num(s), num(ri)).arg(large).arg(num(cx - xi));
    } else {
        p = QStringLiteral("M%1,%2 A%3,%3 0 %4,1 %5,%2 ").arg(num(cx + xo), num(s), num(ro)).arg(large).arg(num(cx - xo));
        if (hole)
            p += QStringLiteral("L%1,%2 A%3,%3 0 %4,0 %5,%2 ").arg(num(cx - xi), num(s), num(ri)).arg(large).arg(num(cx + xi));
    }
    return p + QStringLiteral("Z");
}

void centreOf(const Spec &s, const Layer &l, double &x, double &y)
{
    x = l.ownCentre ? l.cx : s.cx;
    y = l.ownCentre ? l.cy : s.cy;
}

QString pathOf(const Spec &s, const Layer &l)
{
    if (l.shape == QLatin1String("rect"))
        return rectPath(l.x, l.y, l.w, l.h, l.rx);
    double cx, cy;
    centreOf(s, l, cx, cy);
    const double ri = l.shape == QLatin1String("ring") ? l.ri : 0.0;
    QString p;
    if (!l.half.isEmpty())
        p = halfPath(cx, cy, ri, l.r, s.split, l.half == QLatin1String("top"));
    else {
        p = circlePath(cx, cy, l.r);
        if (ri > 0)
            p += QStringLiteral(" ") + circlePath(cx, cy, ri);
    }
    if (l.hole > 0)
        p += QStringLiteral(" ") + circlePath(s.cx, s.cy, l.hole);
    return p;
}

// Where a layer's gradient runs: y0..y1 for vertical, radius 0..r with
// the stops from t0 for radial.
void gradientSpan(const Spec &s, const Layer &l, double &a, double &b, double &t0)
{
    t0 = 0;
    if (l.radial) {
        a = 0;
        b = l.r;
        const double inner = std::max(l.shape == QLatin1String("ring") ? l.ri : 0.0, l.hole);
        t0 = std::clamp(inner / l.r - 0.04, 0.0, 1.0);
        return;
    }
    if (l.shape == QLatin1String("glow")) {
        a = 0;
        b = 1;
        return;
    }
    if (l.shape == QLatin1String("rect")) {
        a = l.horizontal ? l.x : l.y;
        b = l.horizontal ? l.x + l.w : l.y + l.h;
        return;
    }
    double cx, cy;
    centreOf(s, l, cx, cy);
    a = cy - l.r;
    b = cy + l.r;
    if (l.half == QLatin1String("top"))
        b = s.split;
    else if (l.half == QLatin1String("bottom"))
        a = s.split;
}

double offsetOf(double t0, int j, int stops)
{
    return t0 + (1.0 - t0) * static_cast<double>(j) / (stops - 1);
}

QString gradientXml(const Spec &s, const Layer &l, const QString &id, const std::vector<QString> &stopXml)
{
    double a, b, t0;
    gradientSpan(s, l, a, b, t0);
    QString x;
    if (l.radial) {
        double cx, cy;
        centreOf(s, l, cx, cy);
        x = QStringLiteral("<radialGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" cx=\"%2\" cy=\"%3\" r=\"%4\">")
                .arg(id, num(cx), num(cy), num(l.r));
    } else if (l.horizontal) {
        x = QStringLiteral("<linearGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" x1=\"%2\" y1=\"0\" x2=\"%3\" y2=\"0\">")
                .arg(id, num(a), num(b));
    } else {
        x = QStringLiteral("<linearGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"%2\" x2=\"0\" y2=\"%3\">")
                .arg(id, num(a), num(b));
    }
    x = std::accumulate(stopXml.begin(), stopXml.end(), x);
    return x + (l.radial ? QStringLiteral("</radialGradient>") : QStringLiteral("</linearGradient>"));
}

QString svgHeader()
{
    return QStringLiteral("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.2\" baseProfile=\"tiny\" "
                          "width=\"%1\" height=\"%2\" viewBox=\"0 0 %1 %2\">").arg(g_width).arg(g_height);
}

std::vector<float> renderFloat(const QString &svg)
{
    QSvgRenderer renderer(svg.toUtf8());
    QImage image(g_width, g_height, QImage::Format_RGBA32FPx4_Premultiplied);
    image.fill(Qt::transparent);
    {
        QPainter p(&image);
        p.setRenderHint(QPainter::Antialiasing);
        renderer.render(&p, QRectF(0, 0, g_width, g_height));
    }
    std::vector<float> v(sz(g_width) * sz(g_height) * 4);
    for (int y = 0; y < g_height; ++y) {
        const float *line = reinterpret_cast<const float *>(image.constScanLine(y));
        const long row = static_cast<long>(g_width) * 4;
        std::copy(line, line + row, v.begin() + static_cast<long>(y) * row);
    }
    return v;
}

QImage renderImage(const QString &svg, int w, int h)
{
    QSvgRenderer renderer(svg.toUtf8());
    QImage image(w, h, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    renderer.render(&p, QRectF(0, 0, w, h));
    return image;
}

using Stop = std::array<double, 4>;  // straight colour and opacity, 0..1

QString stopXml(double offset, const Stop &st)
{
    const double a = std::clamp(st[3], 0.0, 1.0);
    auto ch = [](double v) { return std::clamp(static_cast<int>(std::lround(v * 255.0)), 0, 255); };
    return QStringLiteral("<stop offset=\"%1\" stop-color=\"#%2%3%4\" stop-opacity=\"%5\"/>")
        .arg(num(offset)).arg(ch(st[0]), 2, 16, QLatin1Char('0')).arg(ch(st[1]), 2, 16, QLatin1Char('0'))
        .arg(ch(st[2]), 2, 16, QLatin1Char('0')).arg(QString::number(a, 'f', 4));
}

/*
 * A layer's gradients (into defs) and paths (returned). Most layers are one
 * path; a glow - a rectangle's soft shadow or halo - is eight that share
 * one profile: a strip along each side with a gradient running outwards and
 * a quarter disc at each corner with a radial one, so it fades the same way
 * all round without a blur filter (SVG Tiny has none). The pieces meet on
 * the rectangle's lines, whole pixels, so no seam is anti-aliased.
 */
QString piecesXml(const Spec &s, const Layer &l, const QString &id, const std::vector<QString> &stopXml, QString &defs)
{
    if (l.shape != QLatin1String("glow")) {
        defs += gradientXml(s, l, id, stopXml);
        return QStringLiteral("<path fill-rule=\"evenodd\" fill=\"url(#%1)\" d=\"%2\"/>").arg(id, pathOf(s, l));
    }
    const QString stops = std::accumulate(stopXml.begin(), stopXml.end(), QString());
    const double x0 = l.x, y0 = l.y, x1 = l.x + l.w, y1 = l.y + l.h, d = l.d;
    QString body;
    int n = 0;
    auto linear = [&](double ax, double ay, double bx, double by, const QString &path) {
        const QString gid = QStringLiteral("%1-%2").arg(id).arg(n++);
        defs += QStringLiteral("<linearGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" x1=\"%2\" y1=\"%3\" x2=\"%4\" y2=\"%5\">")
                    .arg(gid, num(ax), num(ay), num(bx), num(by)) + stops + QStringLiteral("</linearGradient>");
        body += QStringLiteral("<path fill=\"url(#%1)\" d=\"%2\"/>").arg(gid, path);
    };
    auto corner = [&](double cx, double cy, double sx, double sy) {
        const QString gid = QStringLiteral("%1-%2").arg(id).arg(n++);
        defs += QStringLiteral("<radialGradient id=\"%1\" gradientUnits=\"userSpaceOnUse\" cx=\"%2\" cy=\"%3\" r=\"%4\">")
                    .arg(gid, num(cx), num(cy), num(d)) + stops + QStringLiteral("</radialGradient>");
        const int sweep = (sx * sy > 0) ? 1 : 0;
        body += QStringLiteral("<path fill=\"url(#%1)\" d=\"M%2,%3 L%4,%3 A%6,%6 0 0,%7 %2,%5 Z\"/>")
                    .arg(gid, num(cx), num(cy), num(cx + sx * d), num(cy + sy * d), num(d)).arg(sweep);
    };
    linear(0, y0, 0, y0 - d, rectPath(x0, y0 - d, l.w, d, 0));
    linear(0, y1, 0, y1 + d, rectPath(x0, y1, l.w, d, 0));
    linear(x0, 0, x0 - d, 0, rectPath(x0 - d, y0, d, l.h, 0));
    linear(x1, 0, x1 + d, 0, rectPath(x1, y0, d, l.h, 0));
    corner(x0, y0, -1, -1);
    corner(x1, y0, 1, -1);
    corner(x0, y1, -1, 1);
    corner(x1, y1, 1, 1);
    return body;
}

QString layerXml(const Spec &s, size_t i, const std::vector<Stop> &stops, QString &defs)
{
    const Layer &l = s.layers[i];
    double a, b, t0;
    gradientSpan(s, l, a, b, t0);
    std::vector<QString> sx;
    sx.reserve(sz(l.stops));
    for (int j = 0; j < l.stops; ++j)
        sx.push_back(stopXml(offsetOf(t0, j, l.stops), stops[static_cast<size_t>(j)]));
    return piecesXml(s, l, QStringLiteral("g%1").arg(i), sx, defs);
}

QString svgOf(const Spec &s, const std::vector<std::vector<Stop>> &stops, long only = -1)
{
    QString defs, body;
    for (size_t i = 0; i < s.layers.size(); ++i)
        if (only < 0 || static_cast<size_t>(only) == i)
            body += layerXml(s, i, stops[i], defs);
    return svgHeader() + QStringLiteral("<defs>") + defs + QStringLiteral("</defs>") + body + QStringLiteral("</svg>");
}

std::vector<float> basisOf(const Spec &s, const Layer &l, int j)
{
    double a, b, t0;
    gradientSpan(s, l, a, b, t0);
    std::vector<QString> sx;
    sx.reserve(sz(l.stops));
    for (int k = 0; k < l.stops; ++k)
        sx.push_back(QStringLiteral("<stop offset=\"%1\" stop-color=\"#ffffff\" stop-opacity=\"%2\"/>")
                         .arg(num(offsetOf(t0, k, l.stops))).arg(k == j ? 1 : 0));
    QString defs;
    const QString body = piecesXml(s, l, QStringLiteral("g"), sx, defs);
    const QString svg = svgHeader() + QStringLiteral("<defs>") + defs + QStringLiteral("</defs>") + body + QStringLiteral("</svg>");
    const std::vector<float> rgba = renderFloat(svg);
    std::vector<float> w(sz(g_width) * sz(g_height));
    for (size_t p = 0; p < w.size(); ++p)
        w[p] = rgba[p * 4 + 3];
    return w;
}

bool cholesky(std::vector<double> &a, int n)
{
    for (int j = 0; j < n; ++j) {
        double d = a[at(j, j, n)];
        for (int k = 0; k < j; ++k)
            d -= a[at(j, k, n)] * a[at(j, k, n)];
        if (d <= 0)
            return false;
        d = std::sqrt(d);
        a[at(j, j, n)] = d;
        for (int i = j + 1; i < n; ++i) {
            double t = a[at(i, j, n)];
            for (int k = 0; k < j; ++k)
                t -= a[at(i, k, n)] * a[at(j, k, n)];
            a[at(i, j, n)] = t / d;
        }
    }
    return true;
}

void solve(const std::vector<double> &l, int n, std::vector<double> &b)
{
    for (int i = 0; i < n; ++i) {
        double t = b[static_cast<size_t>(i)];
        for (int k = 0; k < i; ++k)
            t -= l[at(i, k, n)] * b[static_cast<size_t>(k)];
        b[static_cast<size_t>(i)] = t / l[at(i, i, n)];
    }
    for (int i = n - 1; i >= 0; --i) {
        double t = b[static_cast<size_t>(i)];
        for (int k = i + 1; k < n; ++k)
            t -= l[at(k, i, n)] * b[static_cast<size_t>(k)];
        b[static_cast<size_t>(i)] = t / l[at(i, i, n)];
    }
}

void legalise(Stop &st)
{
    std::transform(st.begin(), st.end(), st.begin(), [](double v) { return std::clamp(v, 0.0, 1.0); });
}

// Solves the normal equations (with smoothing between neighbour stops and
// a small ridge) for "width" unknowns per stop; false if singular.
bool solveSmoothed(std::vector<double> &ata, std::vector<double> &atb, int stops, int width, double weight = 1.0)
{
    const int m = stops * width;
    const double w = g_smooth * weight;
    for (int j = 0; j + 1 < stops; ++j)
        for (int c = 0; c < width; ++c) {
            const int a = j * width + c, b = a + width;
            ata[at(a, a, m)] += w;
            ata[at(b, b, m)] += w;
            ata[at(a, b, m)] -= w;
            ata[at(b, a, m)] -= w;
        }
    for (int k = 0; k < m; ++k)
        ata[at(k, k, m)] += 1e-5;
    if (!cholesky(ata, m))
        return false;
    solve(ata, m, atb);
    return true;
}

// Composites premultiplied images, src over dst, in place.
void over(std::vector<double> &dst, const std::vector<float> &src)
{
    for (size_t p = 0; p < dst.size() / 4; ++p) {
        const double k = 1.0 - src[p * 4 + 3];
        for (int c = 0; c < 4; ++c)
            dst[p * 4 + static_cast<size_t>(c)] = src[p * 4 + static_cast<size_t>(c)] + dst[p * 4 + static_cast<size_t>(c)] * k;
    }
}

struct Fit {
    std::vector<std::vector<Stop>> stops;
    bool ok = false;
};

Fit fit(const Spec &s)
{
    const size_t n = s.layers.size();
    const size_t pixels = sz(g_width) * sz(g_height);
    Fit f;
    f.stops.resize(n);
    std::vector<std::vector<std::vector<float>>> basis(n);
    for (size_t i = 0; i < n; ++i) {
        for (int j = 0; j < s.layers[i].stops; ++j)
            basis[i].push_back(basisOf(s, s.layers[i], j));
        f.stops[i].assign(static_cast<size_t>(s.layers[i].stops), {0, 0, 0, 0});
    }
    std::vector<double> orig(pixels * 4);
    for (size_t p = 0; p < pixels; ++p) {
        const QRgb o = g_original.pixel(static_cast<int>(p % sz(g_width)), static_cast<int>(p / sz(g_width)));
        orig[p * 4] = qRed(o) / 255.0;
        orig[p * 4 + 1] = qGreen(o) / 255.0;
        orig[p * 4 + 2] = qBlue(o) / 255.0;
        orig[p * 4 + 3] = qAlpha(o) / 255.0;
    }
    std::vector<std::vector<float>> images(n, std::vector<float>(pixels * 4, 0.0f));
    const int rounds = n > 1 ? g_rounds : 1;
    for (int round = 0; round < rounds; ++round) {
        for (size_t i = 0; i < n; ++i) {
            // Below: everything under layer i; above: everything over it,
            // as one image (premultiplied, so "over" is associative).
            std::vector<double> below(pixels * 4, 0.0), above(pixels * 4, 0.0);
            for (size_t k = 0; k < i; ++k)
                over(below, images[k]);
            for (size_t k = i + 1; k < n; ++k)
                over(above, images[k]);
            // final = A + (1 - aA) (L + (1 - aL) B), with L's alpha
            // aL = cov * sum_j w_j a_j and colour L_c = aL * sum_j w_j c_j
            // (w_j: the stop weights where the pixel is, B_j = cov w_j).
            const Layer &l = s.layers[i];
            const int k = l.stops;
            std::vector<Stop> &st = f.stops[i];
            if (round == 0) {
                // A start: the layer solved as if Qt interpolated in
                // premultiplied colour (right where the opacity is even),
                // turned into straight colour.
                const int m = k * 4;
                std::vector<double> ata(sz(m) * sz(m), 0.0), atb(static_cast<size_t>(m), 0.0);
                std::vector<std::pair<int, double>> nz, row;
                for (size_t p = 0; p < pixels; ++p) {
                    nz.clear();
                    for (int j = 0; j < k; ++j) {
                        const float b = basis[i][static_cast<size_t>(j)][p];
                        if (b > 1e-6f)
                            nz.push_back({j, b});
                    }
                    if (nz.empty())
                        continue;
                    const double keep = 1.0 - above[p * 4 + 3];
                    for (int c = 0; c < 4; ++c) {
                        row.clear();
                        const double bc = below[p * 4 + static_cast<size_t>(c)];
                        for (const auto &e : nz) {
                            if (c < 3) {
                                row.push_back({e.first * 4 + c, keep * e.second});
                                row.push_back({e.first * 4 + 3, -keep * e.second * bc});
                            } else {
                                row.push_back({e.first * 4 + 3, keep * e.second * (1.0 - bc)});
                            }
                        }
                        const double t = orig[p * 4 + static_cast<size_t>(c)] - above[p * 4 + static_cast<size_t>(c)] - keep * bc;
                        for (const auto &x : row) {
                            for (const auto &y : row)
                                ata[at(x.first, y.first, m)] += x.second * y.second;
                            atb[static_cast<size_t>(x.first)] += x.second * t;
                        }
                    }
                }
                if (!solveSmoothed(ata, atb, k, 4, l.smooth))
                    return Fit();
                for (int j = 0; j < k; ++j) {
                    const double alpha = std::clamp(atb[sz(j) * 4 + 3], 0.0, 1.0);
                    for (int c = 0; c < 3; ++c)
                        st[static_cast<size_t>(j)][static_cast<size_t>(c)] =
                            alpha > 1e-3 ? atb[sz(j) * 4 + sz(c)] / alpha : 0.0;
                    st[static_cast<size_t>(j)][3] = alpha;
                    legalise(st[static_cast<size_t>(j)]);
                }
            }
            for (int inner = 0; inner < 3; ++inner) {
                // Colours, opacities held: final_c - A_c - keep (1 - aL) B_c = keep * sum_j (aL w_j) c_j.
                {
                    std::vector<double> ata(sz(k) * sz(k), 0.0);
                    std::vector<std::vector<double>> atb(3, std::vector<double>(static_cast<size_t>(k), 0.0));
                    std::vector<std::pair<int, double>> nz;
                    for (size_t p = 0; p < pixels; ++p) {
                        nz.clear();
                        double cov = 0, a = 0;
                        for (int j = 0; j < k; ++j) {
                            const float b = basis[i][static_cast<size_t>(j)][p];
                            if (b > 1e-6f) {
                                nz.push_back({j, b});
                                cov += b;
                                a += b * st[static_cast<size_t>(j)][3];
                            }
                        }
                        if (nz.empty() || a < 1e-4)
                            continue;
                        const double keep = 1.0 - above[p * 4 + 3];
                        for (auto &e : nz)
                            e.second = keep * a * e.second / cov;
                        for (const auto &x : nz) {
                            for (const auto &y : nz)
                                ata[at(x.first, y.first, k)] += x.second * y.second;
                            for (int c = 0; c < 3; ++c) {
                                const double t = orig[p * 4 + static_cast<size_t>(c)] - above[p * 4 + static_cast<size_t>(c)]
                                                 - keep * (1.0 - a) * below[p * 4 + static_cast<size_t>(c)];
                                atb[static_cast<size_t>(c)][static_cast<size_t>(x.first)] += x.second * t;
                            }
                        }
                    }
                    std::vector<double> l0 = ata;
                    for (int c = 0; c < 3; ++c) {
                        std::vector<double> m = l0;
                        if (!solveSmoothed(m, atb[static_cast<size_t>(c)], k, 1, l.smooth))
                            return Fit();
                        for (int j = 0; j < k; ++j)
                            st[static_cast<size_t>(j)][static_cast<size_t>(c)] = atb[static_cast<size_t>(c)][static_cast<size_t>(j)];
                    }
                    for (Stop &x : st)
                        legalise(x);
                }
                // Opacities, colours held: final_c - A_c - keep B_c = keep * sum_j B_j (S_c - B_c) a_j,
                // final_a - A_a - keep B_a = keep * sum_j B_j (1 - B_a) a_j, S the interpolated colour.
                {
                    std::vector<double> ata(sz(k) * sz(k), 0.0), atb(static_cast<size_t>(k), 0.0);
                    std::vector<std::pair<int, double>> nz;
                    for (size_t p = 0; p < pixels; ++p) {
                        nz.clear();
                        double cov = 0;
                        double sc[3] = {0, 0, 0};
                        for (int j = 0; j < k; ++j) {
                            const float b = basis[i][static_cast<size_t>(j)][p];
                            if (b > 1e-6f) {
                                nz.push_back({j, b});
                                cov += b;
                                for (int c = 0; c < 3; ++c)
                                    sc[c] += b * st[static_cast<size_t>(j)][static_cast<size_t>(c)];
                            }
                        }
                        if (nz.empty())
                            continue;
                        std::transform(std::begin(sc), std::end(sc), std::begin(sc), [cov](double v) { return v / cov; });
                        const double keep = 1.0 - above[p * 4 + 3];
                        for (int c = 0; c < 4; ++c) {
                            const double bc = below[p * 4 + static_cast<size_t>(c)];
                            const double factor = c < 3 ? sc[c] - bc : 1.0 - bc;
                            const double t = orig[p * 4 + static_cast<size_t>(c)] - above[p * 4 + static_cast<size_t>(c)] - keep * bc;
                            for (const auto &x : nz) {
                                const double vx = keep * x.second * factor;
                                for (const auto &y : nz)
                                    ata[at(x.first, y.first, k)] += vx * keep * y.second * factor;
                                atb[static_cast<size_t>(x.first)] += vx * t;
                            }
                        }
                    }
                    if (l.fade)  // pinned to transparent
                        ata[at(k - 1, (k - 1), k)] += 1e6;
                    if (!solveSmoothed(ata, atb, k, 1, l.smooth))
                        return Fit();
                    for (int j = 0; j < k; ++j)
                        st[static_cast<size_t>(j)][3] = atb[static_cast<size_t>(j)];
                    if (l.fade)
                        st[static_cast<size_t>(k - 1)][3] = 0.0;
                    for (Stop &x : st)
                        legalise(x);
                }
            }
            images[i] = renderFloat(svgOf(s, f.stops, static_cast<long>(i)));
        }
    }
    f.ok = true;
    return f;
}

struct Score {
    double mse = 1e30;
    int largest = 255;
    double within2 = 0;
};

Score score(const QString &svg)
{
    const QImage d = renderImage(svg, g_width, g_height);
    Score sc;
    double sq = 0;
    long long ok = 0;
    sc.largest = 0;
    for (int y = 0; y < g_height; ++y) {
        for (int x = 0; x < g_width; ++x) {
            const QRgb o = g_original.pixel(x, y), p = d.pixel(x, y);
            const int e[4] = {std::abs(qRed(o) - qRed(p)), std::abs(qGreen(o) - qGreen(p)),
                              std::abs(qBlue(o) - qBlue(p)), std::abs(qAlpha(o) - qAlpha(p))};
            const int m = std::max({e[0], e[1], e[2], e[3]});
            sc.largest = std::max(sc.largest, m);
            ok += m <= 2;
            sq += (e[0] * e[0] + e[1] * e[1] + e[2] * e[2] + e[3] * e[3]) / 4.0;
        }
    }
    sc.mse = sq / (static_cast<double>(g_width) * g_height);
    sc.within2 = 100.0 * static_cast<double>(ok) / (static_cast<double>(g_width) * g_height);
    return sc;
}

double evaluate(const Spec &s, Fit *keep = nullptr)
{
    // Shapes the search has made degenerate: no radius, or a ring with
    // no width.
    for (const Layer &l : s.layers) {
        const bool round = l.shape != QLatin1String("rect") && l.shape != QLatin1String("glow");
        if ((round && l.r <= 0.05) || (l.shape == QLatin1String("ring") && l.ri >= l.r - 0.05))
            return 1e30;
    }
    Fit f = fit(s);
    if (!f.ok)
        return 1e30;
    const double e = score(svgOf(s, f.stops)).mse;
    if (keep)
        *keep = f;
    return e;
}

} // namespace

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QTextStream out(stdout);
    const bool freeze = argc == 3 && QByteArray(argv[2]) == "--freeze";
    if (argc != 2 && !freeze) {
        QTextStream(stderr) << "usage: vectorfit <spec.json> [--freeze]\n";
        return 2;
    }
    const QString specPath = QString::fromLocal8Bit(argv[1]);
    QFile file(specPath);
    if (!file.open(QIODevice::ReadOnly))
        return 2;
    QJsonObject spec = QJsonDocument::fromJson(file.readAll()).object();
    file.close();
    const QDir specDir = QFileInfo(specPath).absoluteDir();

    QImage png(specDir.absoluteFilePath(spec.value(QStringLiteral("png")).toString()));
    if (png.isNull())
        return 2;
    const QJsonArray crop = spec.value(QStringLiteral("crop")).toArray();
    const QRect rect = crop.size() == 4 ? QRect(crop[0].toInt(), crop[1].toInt(), crop[2].toInt(), crop[3].toInt()) : png.rect();
    g_original = png.copy(rect).convertToFormat(QImage::Format_ARGB32_Premultiplied);
    g_width = g_original.width();
    g_height = g_original.height();
    g_smooth = spec.value(QStringLiteral("smooth")).toDouble(0.02);
    g_rounds = spec.value(QStringLiteral("rounds")).toInt(12);
    const int defaultStops = spec.value(QStringLiteral("stops")).toInt(16);

    Spec s;
    s.cx = spec.value(QStringLiteral("cx")).toDouble();
    s.cy = spec.value(QStringLiteral("cy")).toDouble();
    s.split = spec.value(QStringLiteral("split")).toDouble(s.cy);
    for (const QJsonValue v : spec.value(QStringLiteral("layers")).toArray()) {
        const QJsonObject o = v.toObject();
        Layer l;
        l.shape = o.value(QStringLiteral("shape")).toString(QStringLiteral("disc"));
        l.half = o.value(QStringLiteral("half")).toString();
        l.ownCentre = o.contains(QStringLiteral("cx")) || o.contains(QStringLiteral("cy"));
        l.cx = o.value(QStringLiteral("cx")).toDouble(s.cx);
        l.cy = o.value(QStringLiteral("cy")).toDouble(s.cy);
        l.r = o.value(QStringLiteral("r")).toDouble();
        l.ri = o.value(QStringLiteral("ri")).toDouble();
        l.hole = o.value(QStringLiteral("hole")).toDouble();
        l.x = o.value(QStringLiteral("x")).toDouble();
        l.y = o.value(QStringLiteral("y")).toDouble();
        l.w = o.value(QStringLiteral("w")).toDouble();
        l.h = o.value(QStringLiteral("h")).toDouble();
        l.rx = o.value(QStringLiteral("rx")).toDouble();
        l.d = o.value(QStringLiteral("d")).toDouble();
        l.radial = o.value(QStringLiteral("fill")).toString() == QLatin1String("radial");
        l.horizontal = o.value(QStringLiteral("fill")).toString() == QLatin1String("horizontal");
        l.fade = o.value(QStringLiteral("fade")).toBool(false);
        l.smooth = o.value(QStringLiteral("smooth")).toDouble(1.0);
        l.stops = o.value(QStringLiteral("stops")).toInt(defaultStops);
        s.layers.push_back(l);
    }
    if (s.layers.empty())
        return 2;

    Fit best;
    double bestErr = evaluate(s, &best);
    out << "start mse " << bestErr << "\n";
    out.flush();

    QStringList refine;
    for (const QJsonValue v : spec.value(QStringLiteral("refine")).toArray())
        refine << v.toString();
    std::vector<double *> params;
    if (refine.contains(QStringLiteral("cx"))) params.push_back(&s.cx);
    if (refine.contains(QStringLiteral("cy"))) params.push_back(&s.cy);
    if (refine.contains(QStringLiteral("split"))) params.push_back(&s.split);
    for (Layer &l : s.layers) {
        if (refine.contains(QStringLiteral("radii")) && l.shape != QLatin1String("rect")) {
            params.push_back(&l.r);
            if (l.shape == QLatin1String("ring")) params.push_back(&l.ri);
        }
        if (refine.contains(QStringLiteral("centres")) && l.ownCentre) {
            params.push_back(&l.cx);
            params.push_back(&l.cy);
        }
        if (refine.contains(QStringLiteral("rects")) && l.shape == QLatin1String("glow")) {
            params.push_back(&l.x);
            params.push_back(&l.y);
            params.push_back(&l.w);
            params.push_back(&l.h);
            params.push_back(&l.d);
        }
        if (refine.contains(QStringLiteral("rects")) && l.shape == QLatin1String("rect")) {
            params.push_back(&l.x);
            params.push_back(&l.y);
            params.push_back(&l.w);
            params.push_back(&l.h);
            params.push_back(&l.rx);
        }
    }
    const int passes = spec.value(QStringLiteral("passes")).toInt(0);
    double step = spec.value(QStringLiteral("step")).toDouble(0.25);
    for (int pass = 0; pass < passes; ++pass, step /= 2) {
        for (double *p : params) {
            for (int dir : {-1, 1}) {
                for (;;) {
                    const double old = *p;
                    *p = old + dir * step;
                    Fit f;
                    const double e = evaluate(s, &f);
                    if (e + 1e-9 < bestErr) {
                        bestErr = e;
                        best = f;
                    } else {
                        *p = old;
                        break;
                    }
                }
            }
        }
        out << "pass " << pass << " step " << step << " mse " << bestErr << "\n";
        out.flush();
    }

    const QString svg = svgOf(s, best.stops);
    const Score sc = score(svg);
    QFile o(specDir.absoluteFilePath(spec.value(QStringLiteral("out")).toString()));
    if (!o.open(QIODevice::WriteOnly))
        return 3;
    o.write(svg.toUtf8());
    out << "geometry cx " << s.cx << " cy " << s.cy << " split " << s.split << "\n";
    for (const Layer &l : s.layers) {
        out << "  " << l.shape << (l.half.isEmpty() ? QString() : QStringLiteral(" ") + l.half);
        if (l.shape == QLatin1String("glow"))
            out << " " << l.x << "," << l.y << " " << l.w << "x" << l.h << " d " << l.d;
        else if (l.shape == QLatin1String("rect"))
            out << " " << l.x << "," << l.y << " " << l.w << "x" << l.h << " rx " << l.rx;
        else
            out << " r " << l.r << (l.shape == QLatin1String("ring") ? QStringLiteral(" ri %1").arg(l.ri) : QString())
                << (l.ownCentre ? QStringLiteral(" at %1,%2").arg(l.cx).arg(l.cy) : QString());
        out << "\n";
    }
    if (freeze) {
        spec.insert(QStringLiteral("cx"), s.cx);
        spec.insert(QStringLiteral("cy"), s.cy);
        spec.insert(QStringLiteral("split"), s.split);
        QJsonArray layers = spec.value(QStringLiteral("layers")).toArray();
        for (int i = 0; i < layers.size(); ++i) {
            QJsonObject lo = layers[i].toObject();
            const Layer &l = s.layers[static_cast<size_t>(i)];
            auto put = [&lo](const char *k, double v) { lo.insert(QLatin1String(k), std::round(v * 10000.0) / 10000.0); };
            if (l.shape == QLatin1String("glow")) {
                put("x", l.x); put("y", l.y); put("w", l.w); put("h", l.h); put("d", l.d);
            } else if (l.shape == QLatin1String("rect")) {
                put("x", l.x); put("y", l.y); put("w", l.w); put("h", l.h); put("rx", l.rx);
            } else {
                put("r", l.r);
                if (l.shape == QLatin1String("ring")) put("ri", l.ri);
                if (l.ownCentre) { put("cx", l.cx); put("cy", l.cy); }
            }
            layers[i] = lo;
        }
        spec.insert(QStringLiteral("layers"), layers);
        spec.insert(QStringLiteral("passes"), 0);
        QFile w(specPath);
        if (w.open(QIODevice::WriteOnly))
            w.write(QJsonDocument(spec).toJson());
    }
    out << "result max " << sc.largest << " within2 " << sc.within2 << "% PSNR "
        << (sc.mse > 0 ? 10.0 * std::log10(255.0 * 255.0 / sc.mse) : 99.0) << " dB, " << svg.size() << " bytes\n";
    return 0;
}
