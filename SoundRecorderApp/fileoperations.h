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

#ifndef FILEOPERATIONS_H
#define FILEOPERATIONS_H

#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QVariantList>

/*
 * The file work QML cannot do: list, rename and delete recordings.
 *
 * Everything is confined to one folder, rootPath: a path from QML that
 * points anywhere else (another folder, "..", a symlink out) is refused, so
 * a bug in the app cannot delete or rename a file that is not a recording.
 */
class FileOperations : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString rootPath READ rootPath WRITE setRootPath NOTIFY rootPathChanged)

public:
    explicit FileOperations(QObject *parent = nullptr);

    QString rootPath() const;
    void setRootPath(const QString &path);

    /// Creates rootPath (and its parents) if it is not there yet.
    Q_INVOKABLE bool ensureRoot() const;

    /// The files in rootPath with one of the extensions (".mp3", any case),
    /// as { path, name, size, modified } with modified in ms since the epoch.
    /// Hidden files and folders are left out.
    Q_INVOKABLE QVariantList list(const QStringList &extensions) const;

    /// Deletes a file in rootPath.
    Q_INVOKABLE bool remove(const QString &path) const;

    /// Gives a file in rootPath the name newBaseName, keeping its extension.
    /// Returns the new path, or "" when the name is not usable (empty, a
    /// path, "." or "..") or a file of that name already exists: a rename
    /// never replaces another recording.
    Q_INVOKABLE QString rename(const QString &path, const QString &newBaseName) const;

    Q_INVOKABLE bool exists(const QString &path) const;

    /// Free bytes on the file system that holds rootPath, -1 if unknown.
    Q_INVOKABLE double freeSpace() const;

    /// Is newBaseName usable as a file name as it stands?
    static bool isValidBaseName(const QString &newBaseName);

Q_SIGNALS:
    void rootPathChanged();

private:
    /// The canonical path of a file directly in rootPath, "" for anything else.
    QString confined(const QString &path) const;

    QString m_rootPath;
};

#endif // FILEOPERATIONS_H
