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

#include "levelmeter.h"
#include "audiopeak.h"

#include <QtCore/QIODevice>
#include <QtMultimedia/QAudioDevice>
#include <QtMultimedia/QAudioSource>
#include <QtMultimedia/QMediaDevices>

#include <algorithm>

LevelMeter::LevelMeter(QObject *parent)
    : QObject(parent)
{
}

LevelMeter::~LevelMeter()
{
    stop();
}

bool LevelMeter::active() const
{
    return m_active;
}

void LevelMeter::setActive(bool active)
{
    if (active == m_active)
        return;
    m_active = active;
    if (m_active)
        start();
    else
        stop();
    Q_EMIT activeChanged();
}

QString LevelMeter::deviceId() const
{
    return m_deviceId;
}

void LevelMeter::setDeviceId(const QString &id)
{
    if (id == m_deviceId)
        return;
    m_deviceId = id;
    Q_EMIT deviceIdChanged();
    if (m_active) {
        stop();
        start();
    }
}

qreal LevelMeter::peak() const
{
    return m_peak;
}

QString LevelMeter::error() const
{
    return m_error;
}

qreal LevelMeter::follow(qreal shown, qreal sample, qreal decay)
{
    sample = std::clamp(sample, 0.0, 1.0);
    if (sample >= shown)
        return sample;
    return std::max(sample, shown * (1.0 - std::clamp(decay, 0.0, 1.0)));
}

void LevelMeter::start()
{
    QAudioDevice device = QMediaDevices::defaultAudioInput();
    if (!m_deviceId.isEmpty()) {
        const QList<QAudioDevice> inputs = QMediaDevices::audioInputs();
        const auto chosen = std::find_if(inputs.cbegin(), inputs.cend(), [this](const QAudioDevice &input) {
            return QString::fromUtf8(input.id()) == m_deviceId;
        });
        if (chosen != inputs.cend())
            device = *chosen;
    }
    if (device.isNull()) {
        setError(QStringLiteral("No microphone"));
        return;
    }

    // The input's own format, not a cheaper one: on the TouchPad's droid
    // source a second stream at another rate starves the recording (it
    // came out empty), while one in the source's format sits alongside.
    const QAudioFormat format = device.preferredFormat();

    m_sampleFormat = format.sampleFormat();
    m_source = std::make_unique<QAudioSource>(device, format);
    // About 20 updates a second.
    m_source->setBufferSize(format.bytesForDuration(50000));
    m_io = m_source->start();
    if (!m_io) {
        m_source.reset();
        setError(QStringLiteral("Could not listen to the microphone"));
        return;
    }
    connect(m_io.data(), &QIODevice::readyRead, this, &LevelMeter::readAvailable);
    setError(QString());
}

void LevelMeter::stop()
{
    if (m_io)
        disconnect(m_io.data(), nullptr, this, nullptr);
    if (m_source)
        m_source->stop();
    m_source.reset();
    m_io.clear();
    setPeak(0.0);
}

void LevelMeter::readAvailable()
{
    if (!m_io)
        return;
    const QByteArray data = m_io->readAll();
    if (data.isEmpty())
        return;
    const float sample = AudioPeak::peak(data.constData(), static_cast<std::size_t>(data.size()), m_sampleFormat);
    setPeak(follow(m_peak, sample, 0.15));
}

void LevelMeter::setPeak(qreal peak)
{
    if (qFuzzyCompare(1.0 + peak, 1.0 + m_peak))
        return;
    m_peak = peak;
    Q_EMIT peakChanged();
}

void LevelMeter::setError(const QString &error)
{
    if (error == m_error)
        return;
    m_error = error;
    Q_EMIT errorChanged();
}
