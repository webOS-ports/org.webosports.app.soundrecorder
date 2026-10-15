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

#include "fileoperations.h"

#include <QtCore/QDateTime>
#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QStorageInfo>

#include <algorithm>
#include <cerrno>
#include <cstdio>   // renameat2, RENAME_NOREPLACE (glibc 2.28)
#include <fcntl.h>  // AT_FDCWD
#include <unistd.h>

FileOperations::FileOperations(QObject *parent)
    : QObject(parent)
{
}

QString FileOperations::rootPath() const
{
    return m_rootPath;
}

void FileOperations::setRootPath(const QString &path)
{
    if (path == m_rootPath)
        return;
    m_rootPath = path;
    Q_EMIT rootPathChanged();
}

bool FileOperations::ensureRoot() const
{
    if (m_rootPath.isEmpty())
        return false;
    return QDir().mkpath(m_rootPath);
}

QString FileOperations::confined(const QString &path) const
{
    if (m_rootPath.isEmpty() || path.isEmpty())
        return QString();

    const QString root = QFileInfo(m_rootPath).canonicalFilePath();
    const QFileInfo info(path);
    // canonicalFilePath() resolves "..", "." and symlinks, and is empty
    // for a file that does not exist.
    QString file = info.canonicalFilePath();
    if (root.isEmpty() || file.isEmpty() || !info.isFile())
        return QString();
    if (QFileInfo(file).absolutePath() != root)
        return QString();
    return file;
}

QVariantList FileOperations::list(const QStringList &extensions) const
{
    QVariantList result;
    if (m_rootPath.isEmpty())
        return result;

    QStringList wanted;
    wanted.reserve(extensions.size());
    for (const QString &ext : extensions)
        wanted << ext.toLower();

    const QDir dir(m_rootPath);
    const QFileInfoList entries = dir.entryInfoList(QDir::Files | QDir::Readable, QDir::Name);
    for (const QFileInfo &info : entries) {
        const QString name = info.fileName();
        if (name.startsWith(QLatin1Char('.')))
            continue;
        const qsizetype dot = name.lastIndexOf(QLatin1Char('.'));
        if (dot <= 0 || !wanted.contains(name.mid(dot).toLower()))
            continue;

        QVariantMap entry;
        entry.insert(QStringLiteral("path"), info.absoluteFilePath());
        entry.insert(QStringLiteral("name"), name);
        entry.insert(QStringLiteral("size"), static_cast<double>(info.size()));
        entry.insert(QStringLiteral("modified"),
                     static_cast<double>(info.lastModified().toMSecsSinceEpoch()));
        result.append(entry);
    }
    return result;
}

bool FileOperations::remove(const QString &path) const
{
    const QString file = confined(path);
    if (file.isEmpty())
        return false;
    return QFile::remove(file);
}

bool FileOperations::isValidBaseName(const QString &newBaseName)
{
    if (newBaseName.isEmpty() || newBaseName.size() > 200)
        return false;
    if (newBaseName == QLatin1String(".") || newBaseName == QLatin1String(".."))
        return false;
    if (newBaseName.startsWith(QLatin1Char('.')))
        return false;
    return std::none_of(newBaseName.cbegin(), newBaseName.cend(), [](QChar c) {
        return c == QLatin1Char('/') || c == QLatin1Char('\\') || c.unicode() < 0x20 || c.unicode() == 0x7f;
    });
}

QString FileOperations::rename(const QString &path, const QString &newBaseName) const
{
    QString file = confined(path);
    if (file.isEmpty() || !isValidBaseName(newBaseName))
        return QString();

    const QFileInfo info(file);
    const QString name = info.fileName();
    const qsizetype dot = name.lastIndexOf(QLatin1Char('.'));
    const QString ext = dot > 0 ? name.mid(dot) : QString();
    QString target = info.absolutePath() + QLatin1Char('/') + newBaseName + ext;

    if (target == file)
        return file;

    const QByteArray from = QFile::encodeName(file);
    const QByteArray to = QFile::encodeName(target);

    // RENAME_NOREPLACE: the check that the name is free and the rename are
    // one step, so nothing can appear under that name in between.
    if (::renameat2(AT_FDCWD, from.constData(), AT_FDCWD, to.constData(), RENAME_NOREPLACE) == 0)
        return target;
    if (errno != EINVAL && errno != ENOSYS)
        return QString();

    // A file system without RENAME_NOREPLACE (vfat on older kernels): a
    // hard link fails if the name is taken, also in one step. vfat has no
    // hard links either; there the check and the rename are two steps,
    // which is the best that can be done.
    if (::link(from.constData(), to.constData()) == 0) {
        if (::unlink(from.constData()) == 0)
            return target;
        // Both names exist now; take the new one back.
        (void)::unlink(to.constData());
        return QString();
    }
    if (errno == EEXIST)
        return QString();
    if (QFileInfo::exists(target))
        return QString();
    return QFile::rename(file, target) ? target : QString();
}

bool FileOperations::exists(const QString &path) const
{
    return !confined(path).isEmpty();
}

double FileOperations::freeSpace() const
{
    if (m_rootPath.isEmpty())
        return -1;
    const QStorageInfo storage(m_rootPath);
    if (!storage.isValid() || !storage.isReady())
        return -1;
    return static_cast<double>(storage.bytesAvailable());
}
