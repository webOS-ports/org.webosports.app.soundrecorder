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

#ifndef ENCODERRANKS_H
#define ENCODERRANKS_H

#include <QtCore/QByteArray>

namespace EncoderRanks {

/*
 * Which AAC encoder GStreamer picks for the app, as GST_PLUGIN_FEATURE_RANK
 * entries. gst-droid's droidaenc ranks above everything (primary + 1) and
 * fails to start ("Could not configure supporting library"), and libav's
 * avenc_aac, which works, is ranked none, so Qt Multimedia does not even
 * offer AAC without gst-droid. Lowered and raised for this app only.
 */
extern const char ranks[];

/*
 * The value for GST_PLUGIN_FEATURE_RANK: ours, then whatever was set
 * already. GStreamer applies the entries in order, so a rank set from
 * outside still wins.
 */
QByteArray merged(const QByteArray &existing);

/*
 * Sets GST_PLUGIN_FEATURE_RANK for this process. GStreamer reads it once,
 * when it starts, so this has to run before Qt Multimedia starts it: the
 * plugin calls it when it is loaded, before any recorder exists.
 */
void apply();

}

#endif // ENCODERRANKS_H
