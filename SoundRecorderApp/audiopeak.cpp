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

#include "audiopeak.h"

#include <cmath>
#include <cstdint>
#include <cstring>

namespace {

template<typename T>
T sampleAt(const char *data, std::size_t index)
{
    T value;
    std::memcpy(&value, data + index * sizeof(T), sizeof(T));
    return value;
}

}

float AudioPeak::peak(const char *data, std::size_t bytes, QAudioFormat::SampleFormat format)
{
    if (data == nullptr)
        return 0.0f;

    float loudest = 0.0f;

    switch (format) {
    case QAudioFormat::UInt8: {
        for (std::size_t i = 0; i < bytes; ++i) {
            const int v = static_cast<int>(sampleAt<std::uint8_t>(data, i)) - 128;
            loudest = std::fmax(loudest, static_cast<float>(std::abs(v)) / 128.0f);
        }
        break;
    }
    case QAudioFormat::Int16: {
        const std::size_t count = bytes / sizeof(std::int16_t);
        for (std::size_t i = 0; i < count; ++i) {
            // As int: -32768 has no positive int16 counterpart.
            const int v = sampleAt<std::int16_t>(data, i);
            loudest = std::fmax(loudest, static_cast<float>(std::abs(v)) / 32768.0f);
        }
        break;
    }
    case QAudioFormat::Int32: {
        const std::size_t count = bytes / sizeof(std::int32_t);
        for (std::size_t i = 0; i < count; ++i) {
            // As int64: abs(INT32_MIN) overflows an int32.
            const std::int64_t v = sampleAt<std::int32_t>(data, i);
            loudest = std::fmax(loudest, static_cast<float>(static_cast<double>(v < 0 ? -v : v) / 2147483648.0));
        }
        break;
    }
    case QAudioFormat::Float: {
        const std::size_t count = bytes / sizeof(float);
        for (std::size_t i = 0; i < count; ++i) {
            const float v = sampleAt<float>(data, i);
            if (std::isfinite(v))
                loudest = std::fmax(loudest, std::fabs(v));
        }
        break;
    }
    default:
        return 0.0f;
    }

    return std::fmin(loudest, 1.0f);
}
