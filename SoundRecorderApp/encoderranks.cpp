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

#include "encoderranks.h"

#include <QtCore/QtGlobal>

namespace EncoderRanks {

const char ranks[] = "droidaenc:NONE,avenc_aac:PRIMARY";

QByteArray merged(const QByteArray &existing)
{
    const QByteArray rest = existing.trimmed();
    if (rest.isEmpty())
        return QByteArray(ranks);
    return QByteArray(ranks) + ',' + rest;
}

void apply()
{
    qputenv("GST_PLUGIN_FEATURE_RANK", merged(qgetenv("GST_PLUGIN_FEATURE_RANK")));
}

}
