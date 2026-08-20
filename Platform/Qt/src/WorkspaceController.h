// SPDX-License-Identifier: MIT
#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QUrl>

namespace fsuserstories {

class CoreClient;
class StoryModel;

class WorkspaceController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    Q_PROPERTY(QString currentProjectId READ currentProjectId NOTIFY currentProjectChanged)
    Q_PROPERTY(QObject* currentStoryModel READ currentStoryModel CONSTANT)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString coreBinaryPath READ coreBinaryPath CONSTANT)
    Q_PROPERTY(QString databasePath READ databasePath CONSTANT)
    Q_PROPERTY(QString attachmentsRoot READ attachmentsRoot CONSTANT)
    Q_PROPERTY(QString repositoriesRoot READ repositoriesRoot CONSTANT)
    Q_PROPERTY(QString githubAuthorizationCode READ githubAuthorizationCode NOTIFY githubAuthorizationChanged)
    Q_PROPERTY(QString githubAuthorizationUrl READ githubAuthorizationUrl NOTIFY githubAuthorizationChanged)
    Q_PROPERTY(bool githubAuthorizationPending READ githubAuthorizationPending NOTIFY githubAuthorizationChanged)

public:
    explicit WorkspaceController(QObject *parent = nullptr);

    /// Wires the controller to a CoreClient. The controller owns the client.
    void setCoreClient(std::unique_ptr<CoreClient> client, const QString &corePath);

    QVariantList projects() const { return m_projects; }
    QString currentProjectId() const { return m_currentProjectId; }
    QObject *currentStoryModel() const;
    bool busy() const { return m_busy; }
    QString lastError() const { return m_lastError; }
    QString coreBinaryPath() const;
    QString databasePath() const { return m_databasePath; }
    QString attachmentsRoot() const { return m_attachmentsRoot; }
    QString repositoriesRoot() const { return m_repositoriesRoot; }
    QString githubAuthorizationCode() const;
    QString githubAuthorizationUrl() const;
    bool githubAuthorizationPending() const { return !m_pendingAuthorization.isEmpty(); }

    Q_INVOKABLE void load();
    Q_INVOKABLE void createProject(const QString &name, const QString &prefix);
    Q_INVOKABLE void deleteProject(const QString &projectId);
    Q_INVOKABLE void openProject(const QString &projectId);
    Q_INVOKABLE void searchCurrent(const QString &query,
                                   const QString &statusFilter = QString(),
                                   const QString &profileFilter = QString());
    Q_INVOKABLE void refreshCurrent();
    Q_INVOKABLE void addActor(const QString &name, const QString &role);

    Q_INVOKABLE void createStory(const QString &title,
                                 const QString &asA,
                                 const QString &iWant,
                                 const QString &soThat,
                                 const QString &acceptanceCriterion);
    Q_INVOKABLE void updateStory(const QString &storyId,
                                 const QVariantMap &fields);
    Q_INVOKABLE void deleteStory(const QString &storyId);

    Q_INVOKABLE void synchronize();
    Q_INVOKABLE void exportMarkdown(const QUrl &targetFile);
    Q_INVOKABLE void importMarkdown(const QUrl &sourceFile);

    /// Decodes an invitation code and imports its shared Git repository.
    /// Returns true only after the project has been cloned and stored locally.
    Q_INVOKABLE bool acceptInvitation(const QString &invitationToken);
    Q_INVOKABLE bool finishInvitationAuthorization();
    Q_INVOKABLE void cancelInvitationAuthorization();

signals:
    void projectsChanged();
    void currentProjectChanged();
    void busyChanged();
    void lastErrorChanged();
    void info(const QString &message);
    void syncConflicts(const QVariantList &conflicts);
    void githubAuthorizationChanged();

private:
    void setBusy(bool busy);
    void setError(const QString &message);
    QVariantMap runCommand(const QVariantMap &command);
    void applyProject(const QVariantMap &project);
    bool joinInvitationRemote(const QString &remoteUrl,
                              const QString &accessToken = QString());

    std::unique_ptr<CoreClient> m_client;
    QString m_corePath;
    QString m_databasePath;
    QString m_attachmentsRoot;
    QString m_repositoriesRoot;
    QVariantList m_projects;
    QString m_currentProjectId;
    QVariantMap m_currentProject;
    QVariantMap m_pendingAuthorization;
    QString m_pendingRemoteUrl;
    QString m_accessToken;
    StoryModel *m_storyModel = nullptr;
    bool m_busy = false;
    QString m_lastError;
};

} // namespace fsuserstories
