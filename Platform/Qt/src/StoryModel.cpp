// SPDX-License-Identifier: MIT
#include "StoryModel.h"

namespace fsuserstories {

StoryModel::StoryModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int StoryModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_matches.size();
}

QVariant StoryModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_matches.size()) {
        return {};
    }
    const QVariantMap match = m_matches.at(index.row()).toMap();
    const QVariantMap story = match.value("story").toMap();
    const QVariantMap project = match.value("project").toMap();
    const QString actorId = story.value("actorId").toString();
    QString actorName;
    for (const QVariant &actorValue : project.value("actors").toList()) {
        const QVariantMap actor = actorValue.toMap();
        if (actor.value("id").toString() == actorId) {
            actorName = actor.value("name").toString();
            break;
        }
    }
    switch (role) {
    case IdRole:        return story.value("id");
    case TitleRole:     return story.value("title");
    case AsARole:       return actorName;
    case IWantRole:     return story.value("want");
    case SoThatRole:    return story.value("outcome");
    case StatusRole:    return story.value("status");
    case ProfileRole:   return actorId;
    case CriteriaRole:  return story.value("acceptanceCriteria");
    case NotesRole:     return story.value("notes");
    case UpdatedAtRole: return story.value("createdAt");
    case AttachmentsRole:return story.value("attachments");
    case NumberRole:     return story.value("number");
    }
    return {};
}

QHash<int, QByteArray> StoryModel::roleNames() const
{
    return {
        {IdRole,        "storyId"},
        {TitleRole,     "title"},
        {AsARole,       "asA"},
        {IWantRole,     "iWant"},
        {SoThatRole,    "soThat"},
        {StatusRole,    "status"},
        {ProfileRole,   "profileId"},
        {CriteriaRole,  "criteria"},
        {NotesRole,     "notes"},
        {UpdatedAtRole, "updatedAt"},
        {AttachmentsRole,"attachments"},
        {NumberRole,     "number"},
    };
}

void StoryModel::setMatches(const QVariantList &matches)
{
    beginResetModel();
    m_matches = matches;
    endResetModel();
    emit countChanged();
}

void StoryModel::reset()
{
    beginResetModel();
    m_matches.clear();
    endResetModel();
    emit countChanged();
}

} // namespace fsuserstories
