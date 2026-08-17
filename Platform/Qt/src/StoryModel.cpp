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
    switch (role) {
    case IdRole:        return story.value("id");
    case TitleRole:     return story.value("title");
    case AsARole:       return story.value("asA");
    case IWantRole:     return story.value("iWant");
    case SoThatRole:    return story.value("soThat");
    case StatusRole:    return story.value("status");
    case ProfileRole:   return story.value("profileId");
    case CriteriaRole:  return story.value("criteria");
    case NotesRole:     return story.value("notes");
    case UpdatedAtRole: return story.value("updatedAt");
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
