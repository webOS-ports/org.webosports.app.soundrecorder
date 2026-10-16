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

#include <gtest/gtest.h>

#include "encoderranks.h"

#include <QtCore/QtGlobal>

namespace {

TEST(EncoderRanks, AloneWhenNothingIsSet)
{
    EXPECT_EQ(EncoderRanks::merged(QByteArray()), QByteArray("droidaenc:NONE,avenc_aac:PRIMARY"));
    EXPECT_EQ(EncoderRanks::merged("  "), QByteArray("droidaenc:NONE,avenc_aac:PRIMARY"));
}

// GStreamer applies the entries in order: what was set from outside goes
// last, so it still wins.
TEST(EncoderRanks, OursFirstThenWhatWasSet)
{
    EXPECT_EQ(EncoderRanks::merged("avenc_aac:NONE"),
              QByteArray("droidaenc:NONE,avenc_aac:PRIMARY,avenc_aac:NONE"));
}

TEST(EncoderRanks, ApplySetsTheEnvironment)
{
    qputenv("GST_PLUGIN_FEATURE_RANK", "foo:MARGINAL");
    EncoderRanks::apply();
    EXPECT_EQ(qgetenv("GST_PLUGIN_FEATURE_RANK"),
              QByteArray("droidaenc:NONE,avenc_aac:PRIMARY,foo:MARGINAL"));
    qunsetenv("GST_PLUGIN_FEATURE_RANK");
    EncoderRanks::apply();
    EXPECT_EQ(qgetenv("GST_PLUGIN_FEATURE_RANK"), QByteArray("droidaenc:NONE,avenc_aac:PRIMARY"));
    qunsetenv("GST_PLUGIN_FEATURE_RANK");
}

}
