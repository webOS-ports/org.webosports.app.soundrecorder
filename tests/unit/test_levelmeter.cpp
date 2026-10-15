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

#include "levelmeter.h"

TEST(LevelMeter, LouderShowsAtOnce)
{
    EXPECT_DOUBLE_EQ(LevelMeter::follow(0.1, 0.8, 0.15), 0.8);
}

TEST(LevelMeter, QuieterFallsBackSlowly)
{
    EXPECT_DOUBLE_EQ(LevelMeter::follow(0.8, 0.0, 0.25), 0.6);
    // Never below the new sample.
    EXPECT_DOUBLE_EQ(LevelMeter::follow(0.8, 0.7, 0.25), 0.7);
}

TEST(LevelMeter, InputsAreClamped)
{
    EXPECT_DOUBLE_EQ(LevelMeter::follow(0.0, 3.0, 0.1), 1.0);
    EXPECT_DOUBLE_EQ(LevelMeter::follow(0.5, -1.0, 2.0), 0.0);
    EXPECT_DOUBLE_EQ(LevelMeter::follow(0.5, 0.0, -1.0), 0.5);
}

TEST(LevelMeter, InactiveByDefaultAndStopsCleanly)
{
    LevelMeter meter;
    EXPECT_FALSE(meter.active());
    EXPECT_DOUBLE_EQ(meter.peak(), 0.0);
    // Switching off what never started is harmless.
    meter.setActive(false);
    meter.setDeviceId(QStringLiteral("no-such-device"));
    EXPECT_EQ(meter.deviceId(), QStringLiteral("no-such-device"));
}
