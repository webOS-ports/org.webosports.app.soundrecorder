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

#include "plugin.h"
#include "fileoperations.h"
#include "levelmeter.h"

#include <QtQml/QtQml>

void SoundRecorderAppPlugin::registerTypes(const char *uri)
{
    Q_ASSERT(uri == QLatin1String("SoundRecorderApp"));

    // @uri SoundRecorderApp
    qmlRegisterType<FileOperations>(uri, 1, 0, "FileOperations");
    qmlRegisterType<LevelMeter>(uri, 1, 0, "LevelMeter");
}
