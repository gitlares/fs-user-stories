// SPDX-License-Identifier: MIT
#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QString>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QUrl>

#include <functional>

namespace fsuserstories {

class CoreClient;
class StoryModel;

class WorkspaceController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    Q_PROPERTY(QString currentProjectId READ currentProjectId NOTIFY currentProjectChanged)
    Q_PROPERTY(QVariantMap currentProject READ currentProject NOTIFY currentProjectChanged)
    Q_PROPERTY(QVariantList currentActors READ currentActors NOTIFY currentProjectChanged)
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
    Q_PROPERTY(bool githubAuthorizationForRepositoryCreation READ githubAuthorizationForRepositoryCreation NOTIFY githubAuthorizationChanged)
    Q_PROPERTY(bool mcpServerActive READ mcpServerActive NOTIFY mcpServerStateChanged)
    Q_PROPERTY(QString mcpServerUrl READ mcpServerUrl CONSTANT)
    Q_PROPERTY(QVariantList pendingSyncConflicts READ pendingSyncConflicts NOTIFY pendingSyncConflictsChanged)
    Q_PROPERTY(QVariantList pendingImportStories READ pendingImportStories NOTIFY pendingImportStoriesChanged)

public:
    explicit WorkspaceController(QObject *parent = nullptr);

    /// Wires the controller to a CoreClient. The controller owns the client.
    void setCoreClient(std::unique_ptr<CoreClient> client, const QString &corePath);

    QVariantList projects() const { return m_projects; }
    QString currentProjectId() const { return m_currentProjectId; }
    QVariantMap currentProject() const { return m_currentProject; }
    QVariantList currentActors() const { return m_currentProject.value("actors").toList(); }
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
    bool githubAuthorizationForRepositoryCreation() const { return m_pendingGitHubCreation; }
    bool mcpServerActive() const { return m_mcpServerActive; }
    QString mcpServerUrl() const { return QStringLiteral("http://127.0.0.1:49231/mcp"); }
    QVariantList pendingSyncConflicts() const { return m_pendingSyncConflicts; }
    QVariantList pendingImportStories() const { return m_pendingImportStories; }
    void setMcpServerActive(bool active);

    Q_INVOKABLE void load();
    Q_INVOKABLE void createProject(const QString &name, const QString &prefix);
    Q_INVOKABLE void updateProject(const QString &name, const QString &prefix);
    Q_INVOKABLE void deleteProject(const QString &projectId);
    Q_INVOKABLE void openProject(const QString &projectId);
    Q_INVOKABLE void searchCurrent(const QString &query,
                                   const QString &statusFilter = QString(),
                                   const QString &profileFilter = QString());
    Q_INVOKABLE void refreshCurrent();
    Q_INVOKABLE void addActor(const QString &name, const QString &role);
    Q_INVOKABLE void updateActor(const QString &actorId,
                                 const QString &name,
                                 const QString &role);
    Q_INVOKABLE void deleteActor(const QString &actorId);

    Q_INVOKABLE void createStory(const QString &title,
                                 const QString &asA,
                                 const QString &iWant,
                                 const QString &soThat,
                                 const QString &acceptanceCriterion);
    Q_INVOKABLE void updateStory(const QString &storyId,
                                 const QString &title,
                                 const QString &actorId,
                                 const QString &want,
                                 const QString &outcome,
                                 const QVariantList &acceptanceCriteria);
    Q_INVOKABLE void duplicateStory(const QString &storyId, const QString &copyTitle);
    Q_INVOKABLE void setStoryStatus(const QString &storyId, const QString &status);
    Q_INVOKABLE void updateStoryNotes(const QString &storyId, const QString &notes);
    Q_INVOKABLE void toggleAcceptanceCriterion(const QString &storyId,
                                               const QString &criterionId);
    Q_INVOKABLE void addAcceptanceCriterion(const QString &storyId, const QString &text);
    Q_INVOKABLE void deleteAcceptanceCriterion(const QString &storyId,
                                               const QString &criterionId);
    Q_INVOKABLE void importAttachments(const QString &storyId,
                                       const QVariantList &sourceFiles);
    Q_INVOKABLE void chooseAttachments(const QString &storyId);
    Q_INVOKABLE void removeAttachment(const QString &storyId,
                                      const QString &attachmentId);
    Q_INVOKABLE void openAttachment(const QString &storyId,
                                    const QString &attachmentId);
    Q_INVOKABLE void deleteStory(const QString &storyId);

    Q_INVOKABLE void synchronize();
    Q_INVOKABLE bool resolveSynchronization(const QVariantList &resolutions);
    Q_INVOKABLE void initializeRepository();
    Q_INVOKABLE void connectRepository(const QString &remoteUrl);
    Q_INVOKABLE bool createPrivateGitHubRepository();
    Q_INVOKABLE bool finishGitHubRepositoryCreation();
    Q_INVOKABLE bool inviteGitHubCollaborator(const QString &username);
    Q_INVOKABLE QString createInvitation();
    Q_INVOKABLE void exportMarkdown(const QUrl &targetFile);
    Q_INVOKABLE void exportMarkdownSelection(const QUrl &targetFile,
                                             const QString &scope,
                                             const QVariantList &storyIds);
    Q_INVOKABLE void importMarkdown(const QUrl &sourceFile);
    Q_INVOKABLE bool prepareMarkdownImport(const QUrl &sourceFile);
    Q_INVOKABLE bool applyPreparedMarkdownImport(const QVariantList &storyIds);
    Q_INVOKABLE void cancelPreparedMarkdownImport();
    Q_INVOKABLE void copyMcpServerUrl();

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
    void pendingSyncConflictsChanged();
    void pendingImportStoriesChanged();
    void githubAuthorizationChanged();
    void mcpServerStateChanged();

private:
    void setBusy(bool busy);
    void setError(const QString &message);
    QVariantMap runCommand(const QVariantMap &command);
    void applyProject(const QVariantMap &project);
    bool applyCurrentOperation(QVariantMap operation);
    bool currentProjectHasRemote() const;
    void scheduleAutomaticSynchronization();
    void runAutomaticSynchronization();
    void synchronizeCurrentProject(bool announceCompletion,
                                   std::function<void(bool)> completion = {});
    QString attachmentRelativePath(const QString &storyId,
                                   const QString &attachmentId) const;
    bool revealAttachment(const QString &relativePath);
    bool joinInvitationRemote(const QString &remoteUrl,
                              const QString &accessToken = QString());
    bool createPrivateGitHubRepositoryWithToken(const QString &accessToken);
    bool finishGitHubAuthorization(QString *accessToken);

    std::unique_ptr<CoreClient> m_client;
    QString m_corePath;
    QString m_databasePath;
    QString m_attachmentsRoot;
    QString m_repositoriesRoot;
    QVariantList m_projects;
    QString m_currentProjectId;
    QVariantMap m_currentProject;
    QVariantList m_pendingSyncConflicts;
    QVariantList m_pendingImportStories;
    QString m_pendingImportPath;
    QVariantMap m_pendingAuthorization;
    QString m_pendingRemoteUrl;
    bool m_pendingGitHubCreation = false;
    QString m_accessToken;
    StoryModel *m_storyModel = nullptr;
    bool m_busy = false;
    bool m_mcpServerActive = false;
    QString m_lastError;
    QTimer m_autoSyncTimer;
    QTimer m_remoteRefreshTimer;
    QElapsedTimer m_localChangeWindow;
};

} // namespace fsuserstories
