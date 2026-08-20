// SPDX-License-Identifier: MIT
#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QVariantMap>

namespace fsuserstories {

class StoryModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        AsARole,
        IWantRole,
        SoThatRole,
        StatusRole,
        ProfileRole,
        CriteriaRole,
        NotesRole,
        UpdatedAtRole,
        AttachmentsRole,
        NumberRole,
    };

    explicit StoryModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setMatches(const QVariantList &matches);
    void reset();

signals:
    void countChanged();

private:
    QVariantList m_matches;
};

} // namespace fsuserstories
