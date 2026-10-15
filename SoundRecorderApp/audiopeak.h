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

#ifndef AUDIOPEAK_H
#define AUDIOPEAK_H

#include <QtMultimedia/QAudioFormat>

#include <cstddef>

namespace AudioPeak {

/*
 * The loudest sample in a buffer of raw audio, 0..1 of full scale, whatever
 * the channel count. A trailing partial sample is ignored, and so is an
 * unknown format (0). Samples are read with memcpy: QAudioSource gives no
 * alignment guarantee for its buffers.
 */
float peak(const char *data, std::size_t bytes, QAudioFormat::SampleFormat format);

}

#endif // AUDIOPEAK_H
