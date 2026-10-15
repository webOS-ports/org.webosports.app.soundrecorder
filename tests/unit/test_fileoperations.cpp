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

#include "fileoperations.h"

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QFileInfo>
#include <QtCore/QTemporaryDir>

namespace {

bool writeFile(const QString &path, const QByteArray &content)
{
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    return f.write(content) == content.size();
}

QByteArray readFile(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return QByteArray();
    return f.readAll();
}

class FileOperationsTest : public ::testing::Test
{
protected:
    void SetUp() override
    {
        ASSERT_TRUE(m_dir.isValid());
        m_root = m_dir.path() + QStringLiteral("/Recordings");
        m_ops.setRootPath(m_root);
        ASSERT_TRUE(m_ops.ensureRoot());
    }

    QString inRoot(const QString &name) const { return m_root + QLatin1Char('/') + name; }

    QTemporaryDir m_dir;
    QString m_root;
    FileOperations m_ops;
};

}

TEST_F(FileOperationsTest, EnsureRootCreatesParents)
{
    FileOperations ops;
    EXPECT_FALSE(ops.ensureRoot());
    ops.setRootPath(m_dir.path() + QStringLiteral("/a/b/c"));
    EXPECT_TRUE(ops.ensureRoot());
    EXPECT_TRUE(QFileInfo(m_dir.path() + QStringLiteral("/a/b/c")).isDir());
}

TEST_F(FileOperationsTest, ListFiltersByExtensionAnyCase)
{
    ASSERT_TRUE(writeFile(inRoot(QStringLiteral("a.mp3")), "1"));
    ASSERT_TRUE(writeFile(inRoot(QStringLiteral("B.WAV")), "22"));
    ASSERT_TRUE(writeFile(inRoot(QStringLiteral("notes.txt")), "x"));
    ASSERT_TRUE(writeFile(inRoot(QStringLiteral(".hidden.mp3")), "x"));
    ASSERT_TRUE(writeFile(inRoot(QStringLiteral("noext")), "x"));
    ASSERT_TRUE(QDir(m_root).mkdir(QStringLiteral("folder.mp3")));

    const QVariantList files = m_ops.list({QStringLiteral(".mp3"), QStringLiteral(".wav")});
    ASSERT_EQ(files.size(), 2);
    QStringList names;
    for (const QVariant &v : files)
        names << v.toMap().value(QStringLiteral("name")).toString();
    names.sort();
    EXPECT_EQ(names, (QStringList{QStringLiteral("B.WAV"), QStringLiteral("a.mp3")}));

    for (const QVariant &v : files) {
        const QVariantMap m = v.toMap();
        EXPECT_TRUE(m.value(QStringLiteral("path")).toString().startsWith(m_root));
        EXPECT_GT(m.value(QStringLiteral("modified")).toDouble(), 0.0);
        if (m.value(QStringLiteral("name")) == QStringLiteral("B.WAV")) {
            EXPECT_DOUBLE_EQ(m.value(QStringLiteral("size")).toDouble(), 2.0);
        }
    }
}

TEST_F(FileOperationsTest, ListWithoutRootIsEmpty)
{
    FileOperations ops;
    EXPECT_TRUE(ops.list({QStringLiteral(".mp3")}).isEmpty());
}

TEST_F(FileOperationsTest, RemoveDeletesARecording)
{
    const QString file = inRoot(QStringLiteral("a.mp3"));
    ASSERT_TRUE(writeFile(file, "1"));
    EXPECT_TRUE(m_ops.exists(file));
    EXPECT_TRUE(m_ops.remove(file));
    EXPECT_FALSE(QFileInfo::exists(file));
    EXPECT_FALSE(m_ops.remove(file));
}

TEST_F(FileOperationsTest, RemoveRefusesFilesOutsideTheFolder)
{
    const QString outside = m_dir.path() + QStringLiteral("/keep.mp3");
    ASSERT_TRUE(writeFile(outside, "keep"));
    EXPECT_FALSE(m_ops.remove(outside));
    // Through "..".
    EXPECT_FALSE(m_ops.remove(m_root + QStringLiteral("/../keep.mp3")));
    // Through a symlink inside the folder pointing out of it.
    ASSERT_TRUE(QFile::link(outside, inRoot(QStringLiteral("link.mp3"))));
    EXPECT_FALSE(m_ops.remove(inRoot(QStringLiteral("link.mp3"))));
    // A subfolder is not the folder either.
    ASSERT_TRUE(QDir(m_root).mkdir(QStringLiteral("sub")));
    ASSERT_TRUE(writeFile(inRoot(QStringLiteral("sub/x.mp3")), "x"));
    EXPECT_FALSE(m_ops.remove(inRoot(QStringLiteral("sub/x.mp3"))));
    // Not a file at all.
    EXPECT_FALSE(m_ops.remove(m_root));
    EXPECT_FALSE(m_ops.remove(QString()));

    EXPECT_EQ(readFile(outside), QByteArray("keep"));
    EXPECT_TRUE(QFileInfo::exists(inRoot(QStringLiteral("sub/x.mp3"))));
}

TEST_F(FileOperationsTest, RenameKeepsTheExtension)
{
    const QString file = inRoot(QStringLiteral("Recording 1.mp3"));
    ASSERT_TRUE(writeFile(file, "audio"));
    const QString renamed = m_ops.rename(file, QStringLiteral("Lecture – Tromsø"));
    EXPECT_EQ(renamed, inRoot(QStringLiteral("Lecture – Tromsø.mp3")));
    EXPECT_FALSE(QFileInfo::exists(file));
    EXPECT_EQ(readFile(renamed), QByteArray("audio"));
}

TEST_F(FileOperationsTest, RenameNeverReplacesAnotherRecording)
{
    const QString a = inRoot(QStringLiteral("a.mp3"));
    const QString b = inRoot(QStringLiteral("b.mp3"));
    ASSERT_TRUE(writeFile(a, "A"));
    ASSERT_TRUE(writeFile(b, "B"));
    EXPECT_TRUE(m_ops.rename(a, QStringLiteral("b")).isEmpty());
    EXPECT_EQ(readFile(a), QByteArray("A"));
    EXPECT_EQ(readFile(b), QByteArray("B"));
}

TEST_F(FileOperationsTest, RenameToItselfIsFine)
{
    const QString a = inRoot(QStringLiteral("a.wav"));
    ASSERT_TRUE(writeFile(a, "A"));
    EXPECT_EQ(m_ops.rename(a, QStringLiteral("a")), a);
    EXPECT_EQ(readFile(a), QByteArray("A"));
}

TEST_F(FileOperationsTest, RenameRefusesUnusableNames)
{
    const QString a = inRoot(QStringLiteral("a.mp3"));
    ASSERT_TRUE(writeFile(a, "A"));
    for (const QString &name : {QString(), QStringLiteral("."), QStringLiteral(".."), QStringLiteral(".hidden"),
                                QStringLiteral("../escape"), QStringLiteral("sub/dir"), QStringLiteral("back\\slash"),
                                QStringLiteral("new\nline"), QString(201, QLatin1Char('x'))}) {
        EXPECT_TRUE(m_ops.rename(a, name).isEmpty()) << name.toStdString();
    }
    EXPECT_EQ(readFile(a), QByteArray("A"));
    EXPECT_FALSE(QFileInfo::exists(m_dir.path() + QStringLiteral("/escape.mp3")));
}

TEST_F(FileOperationsTest, RenameRefusesFilesOutsideTheFolder)
{
    const QString outside = m_dir.path() + QStringLiteral("/keep.mp3");
    ASSERT_TRUE(writeFile(outside, "keep"));
    EXPECT_TRUE(m_ops.rename(outside, QStringLiteral("moved")).isEmpty());
    EXPECT_TRUE(QFileInfo::exists(outside));
}

TEST_F(FileOperationsTest, ValidBaseNames)
{
    EXPECT_TRUE(FileOperations::isValidBaseName(QStringLiteral("Recording 2026-10-15 06.30.02")));
    EXPECT_TRUE(FileOperations::isValidBaseName(QStringLiteral("a.b")));
    EXPECT_FALSE(FileOperations::isValidBaseName(QStringLiteral("tab\there")));
    EXPECT_FALSE(FileOperations::isValidBaseName(QString(QChar(0x7f))));
}

TEST_F(FileOperationsTest, FreeSpaceIsKnownForTheFolder)
{
    EXPECT_GT(m_ops.freeSpace(), 0.0);
    FileOperations ops;
    EXPECT_DOUBLE_EQ(ops.freeSpace(), -1.0);
}

TEST_F(FileOperationsTest, RootPathSignalsOnlyOnChange)
{
    int changes = 0;
    QObject::connect(&m_ops, &FileOperations::rootPathChanged, [&changes]() { ++changes; });
    m_ops.setRootPath(m_root);
    EXPECT_EQ(changes, 0);
    m_ops.setRootPath(m_root + QStringLiteral("2"));
    EXPECT_EQ(changes, 1);
}
