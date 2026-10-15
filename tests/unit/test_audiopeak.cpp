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

#include "audiopeak.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

namespace {

template<typename T>
std::vector<char> bytesOf(const std::vector<T> &samples)
{
    std::vector<char> bytes(samples.size() * sizeof(T));
    if (!samples.empty())
        std::memcpy(bytes.data(), samples.data(), bytes.size());
    return bytes;
}

}

TEST(AudioPeak, SilenceIsZero)
{
    const auto bytes = bytesOf<std::int16_t>({0, 0, 0, 0});
    EXPECT_FLOAT_EQ(AudioPeak::peak(bytes.data(), bytes.size(), QAudioFormat::Int16), 0.0f);
}

TEST(AudioPeak, Int16TakesTheLoudestEitherSign)
{
    const auto bytes = bytesOf<std::int16_t>({100, -16384, 8192, 0});
    EXPECT_FLOAT_EQ(AudioPeak::peak(bytes.data(), bytes.size(), QAudioFormat::Int16), 0.5f);
}

TEST(AudioPeak, Int16FullScaleBothWays)
{
    // -32768 is full scale; 32767 is one step short of it.
    const auto low = bytesOf<std::int16_t>({std::numeric_limits<std::int16_t>::min()});
    EXPECT_FLOAT_EQ(AudioPeak::peak(low.data(), low.size(), QAudioFormat::Int16), 1.0f);
    const auto high = bytesOf<std::int16_t>({std::numeric_limits<std::int16_t>::max()});
    EXPECT_NEAR(AudioPeak::peak(high.data(), high.size(), QAudioFormat::Int16), 1.0f, 1e-4f);
}

TEST(AudioPeak, Int32MinimumDoesNotOverflow)
{
    const auto bytes = bytesOf<std::int32_t>({std::numeric_limits<std::int32_t>::min(), 5});
    EXPECT_FLOAT_EQ(AudioPeak::peak(bytes.data(), bytes.size(), QAudioFormat::Int32), 1.0f);
    const auto quarter = bytesOf<std::int32_t>({-536870912});
    EXPECT_FLOAT_EQ(AudioPeak::peak(quarter.data(), quarter.size(), QAudioFormat::Int32), 0.25f);
}

TEST(AudioPeak, UInt8IsCentredOn128)
{
    const auto silent = bytesOf<std::uint8_t>({128, 128});
    EXPECT_FLOAT_EQ(AudioPeak::peak(silent.data(), silent.size(), QAudioFormat::UInt8), 0.0f);
    const auto loud = bytesOf<std::uint8_t>({128, 0, 192});
    EXPECT_FLOAT_EQ(AudioPeak::peak(loud.data(), loud.size(), QAudioFormat::UInt8), 1.0f);
}

TEST(AudioPeak, FloatIsClampedAndIgnoresNaN)
{
    const auto bytes = bytesOf<float>({0.25f, -0.75f, std::numeric_limits<float>::quiet_NaN()});
    EXPECT_FLOAT_EQ(AudioPeak::peak(bytes.data(), bytes.size(), QAudioFormat::Float), 0.75f);
    const auto over = bytesOf<float>({1.5f, std::numeric_limits<float>::infinity()});
    EXPECT_FLOAT_EQ(AudioPeak::peak(over.data(), over.size(), QAudioFormat::Float), 1.0f);
}

TEST(AudioPeak, TrailingPartialSampleIsIgnored)
{
    // Three bytes: one Int16 sample and half of the next, which is loud.
    std::vector<char> bytes = bytesOf<std::int16_t>({16384, -32768});
    bytes.resize(3);
    EXPECT_FLOAT_EQ(AudioPeak::peak(bytes.data(), bytes.size(), QAudioFormat::Int16), 0.5f);
}

TEST(AudioPeak, UnalignedBufferIsRead)
{
    // QAudioSource does not promise alignment: start one byte in.
    std::vector<char> bytes(1 + 2 * sizeof(std::int32_t));
    const std::int32_t samples[2] = {0, -1073741824};
    std::memcpy(bytes.data() + 1, samples, sizeof(samples));
    EXPECT_FLOAT_EQ(AudioPeak::peak(bytes.data() + 1, sizeof(samples), QAudioFormat::Int32), 0.5f);
}

TEST(AudioPeak, NothingToReadIsZero)
{
    EXPECT_FLOAT_EQ(AudioPeak::peak(nullptr, 16, QAudioFormat::Int16), 0.0f);
    const char one = 0x7f;
    EXPECT_FLOAT_EQ(AudioPeak::peak(&one, 0, QAudioFormat::Int16), 0.0f);
    EXPECT_FLOAT_EQ(AudioPeak::peak(&one, 1, QAudioFormat::Unknown), 0.0f);
}
