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

#ifndef LEVELMETER_H
#define LEVELMETER_H

#include <QtCore/QObject>
#include <QtCore/QPointer>
#include <QtCore/QString>
#include <QtMultimedia/QAudioFormat>

#include <memory>

class QAudioSource;
class QIODevice;

/*
 * How loud the microphone is, for the meter while recording.
 *
 * Qt 6's MediaRecorder says nothing about levels (Qt 5's QAudioProbe is
 * gone), so this listens to the same input on a stream of its own, with
 * QAudioSource. PulseAudio hands both streams the same samples.
 *
 * peak is the loudest sample since the last update, 0..1, falling back
 * slowly so the meter does not flicker; QML turns it into decibels.
 */
class LevelMeter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString deviceId READ deviceId WRITE setDeviceId NOTIFY deviceIdChanged)
    Q_PROPERTY(qreal peak READ peak NOTIFY peakChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    explicit LevelMeter(QObject *parent = nullptr);
    ~LevelMeter() override;

    bool active() const;
    void setActive(bool active);

    /// QAudioDevice::id() of the input to listen to; "" for the default.
    QString deviceId() const;
    void setDeviceId(const QString &id);

    qreal peak() const;
    QString error() const;

    /// The meter's next value: a louder sample shows at once, a quieter one
    /// lets the meter fall by at most decay of its value per update.
    static qreal follow(qreal shown, qreal sample, qreal decay);

Q_SIGNALS:
    void activeChanged();
    void deviceIdChanged();
    void peakChanged();
    void errorChanged();

private:
    void start();
    void stop();
    void readAvailable();
    void setPeak(qreal peak);
    void setError(const QString &error);

    bool m_active = false;
    QString m_deviceId;
    qreal m_peak = 0.0;
    QString m_error;
    QAudioFormat::SampleFormat m_sampleFormat = QAudioFormat::Unknown;
    std::unique_ptr<QAudioSource> m_source;
    QPointer<QIODevice> m_io;
};

#endif // LEVELMETER_H
