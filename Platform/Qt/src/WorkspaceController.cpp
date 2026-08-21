// SPDX-License-Identifier: MIT
#include "WorkspaceController.h"
#include "CoreClient.h"
#include "CorePaths.h"
#include "CredentialStore.h"
#include "StoryModel.h"

#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QDir>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QClipboard>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>
#include <utility>

Q_LOGGING_CATEGORY(lcWorkspace, "fsuserstories.workspace")

namespace fsuserstories {

namespace {
constexpr auto kGitHubOAuthClientId = "Ov23liEDQnlgdtJTGCUt";
constexpr int kAutoSyncDebounceMs = 3'000;
constexpr int kAutoSyncMaximumDelayMs = 15'000;
constexpr int kRemoteRefreshMs = 30'000;
}

WorkspaceController::WorkspaceController(QObject *parent)
    : QObject(parent)
    , m_storyModel(new StoryModel(this))
    , m_databasePath(CorePaths::defaultDatabasePath())
    , m_attachmentsRoot(CorePaths::defaultAttachmentsRoot())
    , m_repositoriesRoot(CorePaths::defaultRepositoriesRoot())
{
    // Make sure the data roots exist before the first core call.
    QFileInfo::exists(m_databasePath); // touch file path awareness

    m_autoSyncTimer.setSingleShot(true);
    connect(&m_autoSyncTimer, &QTimer::timeout, this,
            &WorkspaceController::runAutomaticSynchronization);
    m_remoteRefreshTimer.setInterval(kRemoteRefreshMs);
    connect(&m_remoteRefreshTimer, &QTimer::timeout, this,
            &WorkspaceController::runAutomaticSynchronization);
    m_remoteRefreshTimer.start();
}

void WorkspaceController::setCoreClient(std::unique_ptr<CoreClient> client,
                                       const QString &corePath)
{
    m_client = std::move(client);
    m_corePath = corePath;
}

QObject *WorkspaceController::currentStoryModel() const
{
    return m_storyModel;
}

QString WorkspaceController::coreBinaryPath() const
{
    return m_corePath;
}

QString WorkspaceController::githubAuthorizationCode() const
{
    return m_pendingAuthorization.value("userCode").toString();
}

QString WorkspaceController::githubAuthorizationUrl() const
{
    return m_pendingAuthorization.value("verificationUrl").toString();
}

void WorkspaceController::load()
{
    if (!m_client) {
        setError(QStringLiteral("Core not configured."));
        return;
    }
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "load_workspace"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
    });
    setBusy(false);

    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    m_projects = reply.value("result").toMap().value("projects").toList();
    emit projectsChanged();
    if (!m_currentProjectId.isEmpty()) {
        openProject(m_currentProjectId);
    }
}

void WorkspaceController::createProject(const QString &name, const QString &prefix)
{
    if (!m_client) {
        return;
    }
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "create_stored_project"},
        {"database_path", m_databasePath},
        {"name", name},
        {"prefix", prefix},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (!project.isEmpty()) {
        applyProject(project);
    }
    load();
    scheduleAutomaticSynchronization();
}

void WorkspaceController::updateProject(const QString &name, const QString &prefix)
{
    applyCurrentOperation({
        {"operation", "update_project"},
        {"name", name},
        {"prefix", prefix},
    });
}

void WorkspaceController::deleteProject(const QString &projectId)
{
    if (!m_client) {
        return;
    }
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "delete_stored_project"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"repositories_root", m_repositoriesRoot},
        {"project_id", projectId},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    if (m_currentProjectId == projectId) {
        m_currentProjectId.clear();
        m_currentProject.clear();
        m_storyModel->reset();
        emit currentProjectChanged();
    }
    load();
}

void WorkspaceController::openProject(const QString &projectId)
{
    if (!m_client) {
        return;
    }
    for (const QVariant &p : std::as_const(m_projects)) {
        const QVariantMap project = p.toMap();
        if (project.value("id").toString() == projectId) {
            m_currentProject = project;
            m_currentProjectId = projectId;
            emit currentProjectChanged();
            refreshCurrent();
            return;
        }
    }
}

void WorkspaceController::searchCurrent(const QString &query,
                                        const QString &statusFilter,
                                        const QString &profileFilter)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    QVariantMap searchQuery{
        {"text", query},
        {"projectId", m_currentProjectId},
    };
    const QString normalizedStatus = statusFilter.trimmed().toLower();
    if (normalizedStatus == QLatin1String("active") ||
        normalizedStatus == QLatin1String("draft") ||
        normalizedStatus == QLatin1String("done")) {
        searchQuery.insert("status", normalizedStatus);
    }
    if (!profileFilter.isEmpty() && profileFilter != QLatin1String("all")) {
        searchQuery.insert("actorId", profileFilter);
    }

    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "search_workspace"},
        {"database_path", m_databasePath},
        {"query", searchQuery},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    const QVariantList matches = reply.value("result").toMap().value("matches").toList();
    m_storyModel->setMatches(matches);
}

void WorkspaceController::refreshCurrent()
{
    searchCurrent({}, {}, {});
}

void WorkspaceController::addActor(const QString &name, const QString &role)
{
    applyCurrentOperation({
        {"operation", "add_actor"},
        {"name", name},
        {"role", role},
    });
}

void WorkspaceController::updateActor(const QString &actorId,
                                      const QString &name,
                                      const QString &role)
{
    applyCurrentOperation({
        {"operation", "update_actor"},
        {"actor_id", actorId},
        {"name", name},
        {"role", role},
    });
}

void WorkspaceController::deleteActor(const QString &actorId)
{
    applyCurrentOperation({
        {"operation", "delete_actor"},
        {"actor_id", actorId},
    });
}

void WorkspaceController::createStory(const QString &title,
                                      const QString &asA,
                                      const QString &iWant,
                                      const QString &soThat,
                                      const QString &acceptanceCriterion)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }

    setError({});
    QString actorId;
    const QString actorName = asA.trimmed();
    for (const QVariant &actorValue : m_currentProject.value("actors").toList()) {
        const QVariantMap actor = actorValue.toMap();
        if (actor.value("name").toString().compare(actorName, Qt::CaseInsensitive) == 0) {
            actorId = actor.value("id").toString();
            break;
        }
    }
    if (actorId.isEmpty()) {
        addActor(actorName, QString());
        if (!m_lastError.isEmpty()) {
            return;
        }
        for (const QVariant &actorValue : m_currentProject.value("actors").toList()) {
            const QVariantMap actor = actorValue.toMap();
            if (actor.value("name").toString().compare(actorName, Qt::CaseInsensitive) == 0) {
                actorId = actor.value("id").toString();
                break;
            }
        }
    }
    if (actorId.isEmpty()) {
        setError(tr("The profile could not be created."));
        return;
    }

    QVariantMap command{
        {"command", "apply_stored_workspace_command"},
        {"database_path", m_databasePath},
        {"project_id", m_currentProjectId},
        {"operation", "add_story"},
        {"title", title},
        {"actor_id", actorId},
        {"want", iWant},
        {"outcome", soThat},
        {"acceptance_criteria", QVariantList{
            QVariantMap{{"id", QString()},
                        {"text", acceptanceCriterion},
                        {"isMet", false}}
        }},
    };
    setBusy(true);
    const QVariantMap reply = runCommand(command);
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (!project.isEmpty()) {
        m_currentProject = project;
        applyProject(project);
    }
    refreshCurrent();
    scheduleAutomaticSynchronization();
}

void WorkspaceController::updateStory(const QString &storyId,
                                      const QString &title,
                                      const QString &actorId,
                                      const QString &want,
                                      const QString &outcome,
                                      const QVariantList &acceptanceCriteria)
{
    applyCurrentOperation({
        {"operation", "update_story"},
        {"story_id", storyId},
        {"title", title},
        {"actor_id", actorId},
        {"want", want},
        {"outcome", outcome},
        {"acceptance_criteria", acceptanceCriteria},
    });
}

void WorkspaceController::duplicateStory(const QString &storyId, const QString &copyTitle)
{
    applyCurrentOperation({
        {"operation", "duplicate_story"},
        {"story_id", storyId},
        {"copy_title", copyTitle},
    });
}

void WorkspaceController::setStoryStatus(const QString &storyId, const QString &status)
{
    applyCurrentOperation({
        {"operation", "set_story_status"},
        {"story_id", storyId},
        {"status", status},
    });
}

void WorkspaceController::updateStoryNotes(const QString &storyId, const QString &notes)
{
    applyCurrentOperation({
        {"operation", "update_story_notes"},
        {"story_id", storyId},
        {"notes", notes},
    });
}

void WorkspaceController::toggleAcceptanceCriterion(const QString &storyId,
                                                    const QString &criterionId)
{
    applyCurrentOperation({
        {"operation", "toggle_acceptance_criterion"},
        {"story_id", storyId},
        {"criterion_id", criterionId},
    });
}

void WorkspaceController::addAcceptanceCriterion(const QString &storyId,
                                                 const QString &text)
{
    applyCurrentOperation({
        {"operation", "add_acceptance_criterion"},
        {"story_id", storyId},
        {"text", text},
    });
}

void WorkspaceController::deleteAcceptanceCriterion(const QString &storyId,
                                                    const QString &criterionId)
{
    applyCurrentOperation({
        {"operation", "delete_acceptance_criterion"},
        {"story_id", storyId},
        {"criterion_id", criterionId},
    });
}

void WorkspaceController::importAttachments(const QString &storyId,
                                            const QVariantList &sourceFiles)
{
    if (!m_client || m_currentProjectId.isEmpty() || sourceFiles.isEmpty()) {
        return;
    }
    QVariantList sourcePaths;
    for (const QVariant &sourceFile : sourceFiles) {
        const QString rawValue = sourceFile.toString();
        const QUrl url = QUrl::fromEncoded(rawValue.toUtf8());
        QString path = url.isLocalFile() ? url.toLocalFile() : rawValue;
#ifdef Q_OS_WIN
        if (path.size() > 2 && path.at(0) == u'/' && path.at(2) == u':') {
            path.remove(0, 1);
        }
#endif
        path = QDir::toNativeSeparators(path);
        if (!path.isEmpty()) {
            sourcePaths.append(path);
        }
    }
    if (sourcePaths.isEmpty()) {
        setError(tr("The dropped files did not contain a usable local path."));
        return;
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "import_stored_attachments"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"story_id", storyId},
        {"source_paths", sourcePaths},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    applyProject(reply.value("result").toMap().value("project").toMap());
    refreshCurrent();
    scheduleAutomaticSynchronization();
}

void WorkspaceController::chooseAttachments(const QString &storyId)
{
    if (storyId.isEmpty()) {
        return;
    }
    const QStringList files = QFileDialog::getOpenFileNames(
        nullptr,
        tr("Add Attachments"),
        QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation),
        tr("All Files (*)"));
    if (files.isEmpty()) {
        return;
    }
    QVariantList urls;
    urls.reserve(files.size());
    for (const QString &file : files) {
        urls.append(QUrl::fromLocalFile(file));
    }
    importAttachments(storyId, urls);
}

void WorkspaceController::removeAttachment(const QString &storyId,
                                           const QString &attachmentId)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "remove_stored_attachment"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"story_id", storyId},
        {"attachment_id", attachmentId},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    applyProject(reply.value("result").toMap().value("project").toMap());
    refreshCurrent();
    scheduleAutomaticSynchronization();
}

QString WorkspaceController::attachmentRelativePath(const QString &storyId,
                                                    const QString &attachmentId) const
{
    for (const QVariant &storyValue : m_currentProject.value("stories").toList()) {
        const QVariantMap story = storyValue.toMap();
        if (story.value("id").toString() != storyId) {
            continue;
        }
        for (const QVariant &attachmentValue : story.value("attachments").toList()) {
            const QVariantMap attachment = attachmentValue.toMap();
            if (attachment.value("id").toString() == attachmentId) {
                return attachment.value("relativePath").toString();
            }
        }
    }
    return {};
}

bool WorkspaceController::revealAttachment(const QString &relativePath)
{
    const QString root = QDir(m_attachmentsRoot).canonicalPath();
    const QString path = QFileInfo(QDir(m_attachmentsRoot).filePath(relativePath)).canonicalFilePath();
    if (path.isEmpty() || root.isEmpty() ||
        !(path == root || path.startsWith(root + QDir::separator()))) {
        return false;
    }
#ifdef Q_OS_WIN
    if (!QProcess::startDetached(QStringLiteral("explorer.exe"),
                                 {QStringLiteral("/select,%1")
                                      .arg(QDir::toNativeSeparators(path))})) {
        setError(tr("The attachment could not be shown in File Explorer."));
        return false;
    }
#elif defined(Q_OS_MACOS)
    if (!QProcess::startDetached(QStringLiteral("open"), {QStringLiteral("-R"), path})) {
        setError(tr("The attachment could not be shown in Finder."));
        return false;
    }
#else
    if (!QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(path).absolutePath()))) {
        setError(tr("The attachment folder could not be opened."));
        return false;
    }
#endif
    return true;
}

void WorkspaceController::openAttachment(const QString &storyId,
                                         const QString &attachmentId)
{
    setError({});
    QString relativePath = attachmentRelativePath(storyId, attachmentId);
    if (!relativePath.isEmpty() && revealAttachment(relativePath)) {
        return;
    }

    if (currentProjectHasRemote()) {
        synchronizeCurrentProject(false, [this, storyId, attachmentId](bool succeeded) {
            if (!succeeded) {
                return;
            }
            const QString restoredPath = attachmentRelativePath(storyId, attachmentId);
            if (!restoredPath.isEmpty() && revealAttachment(restoredPath)) {
                return;
            }
            setError(tr("The attachment could not be restored from the shared repository."));
        });
        return;
    }
    setError(tr("The attachment could not be restored from the shared repository."));
}

void WorkspaceController::deleteStory(const QString &storyId)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "delete_stored_story"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"story_id", storyId},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (!project.isEmpty()) {
        applyProject(project);
    }
    refreshCurrent();
    scheduleAutomaticSynchronization();
}

void WorkspaceController::synchronize()
{
    m_autoSyncTimer.stop();
    m_localChangeWindow.invalidate();
    synchronizeCurrentProject(true);
}

void WorkspaceController::synchronizeCurrentProject(bool announceCompletion,
                                                    std::function<void(bool)> completion)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        if (completion) {
            completion(false);
        }
        return;
    }
    if (m_accessToken.isEmpty()) {
        m_accessToken = CredentialStore::readGitHubToken();
    }
    setBusy(true);
    const QVariantMap command = {
        {"command", "synchronize_stored_project"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"access_token", m_accessToken.isEmpty() ? QVariant() : QVariant(m_accessToken)},
    };
    m_client->executeAsync(
        command,
        [this, announceCompletion, completion](const QVariantMap &reply) {
            setBusy(false);
            if (!reply.value("ok").toBool()) {
                const QVariantMap errorValue = reply.value("error").toMap();
                if (errorValue.value("code").toString() == QLatin1String("sync_conflicts")) {
                    const QVariantList conflicts =
                        errorValue.value("details").toMap().value("conflicts").toList();
                    m_pendingSyncConflicts = conflicts;
                    emit pendingSyncConflictsChanged();
                    emit syncConflicts(conflicts);
                } else {
                    setError(errorValue.value("message").toString());
                }
                if (completion) {
                    completion(false);
                }
                return;
            }
            if (!m_pendingSyncConflicts.isEmpty()) {
                m_pendingSyncConflicts.clear();
                emit pendingSyncConflictsChanged();
            }
            const QVariantMap project = reply.value("result").toMap().value("project").toMap();
            if (!project.isEmpty()) {
                applyProject(project);
            }
            if (announceCompletion) {
                emit info(tr("Project synchronized."));
            }
            refreshCurrent();
            if (completion) {
                completion(true);
            }
        },
        [this, completion](const QString &message) {
            setBusy(false);
            setError(message);
            if (completion) {
                completion(false);
            }
        }
    );
}

bool WorkspaceController::resolveSynchronization(const QVariantList &resolutions)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        setError(tr("Open the conflicted project first."));
        return false;
    }
    if (m_pendingSyncConflicts.isEmpty()
        || resolutions.size() != m_pendingSyncConflicts.size()) {
        setError(tr("Choose your version or the shared version for every conflict."));
        return false;
    }
    if (m_accessToken.isEmpty()) {
        m_accessToken = CredentialStore::readGitHubToken();
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "resolve_stored_project_synchronization"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"resolutions", resolutions},
        {"access_token", m_accessToken.isEmpty() ? QVariant() : QVariant(m_accessToken)},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return false;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (!project.isEmpty()) {
        applyProject(project);
    }
    m_pendingSyncConflicts.clear();
    emit pendingSyncConflictsChanged();
    emit info(tr("Synchronization conflicts resolved."));
    refreshCurrent();
    return true;
}

void WorkspaceController::initializeRepository()
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        setError(tr("Open a project before enabling Git."));
        return;
    }
    const QString repositoryPath =
        QDir(m_repositoriesRoot).filePath(m_currentProjectId);
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "initialize_stored_project_repository"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"repository_path", repositoryPath},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (!project.isEmpty()) {
        applyProject(project);
    }
    emit info(tr("Local Git repository initialized."));
}

void WorkspaceController::connectRepository(const QString &remoteUrl)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        setError(tr("Open a project before connecting a repository."));
        return;
    }
    if (m_currentProject.value("gitRepository").toMap().isEmpty()) {
        initializeRepository();
        if (!m_lastError.isEmpty()) {
            return;
        }
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "connect_stored_project_repository"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"remote_url", remoteUrl.trimmed()},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (!project.isEmpty()) {
        applyProject(project);
    }
    emit info(tr("Remote repository connected."));
    scheduleAutomaticSynchronization();
}

bool WorkspaceController::createPrivateGitHubRepository()
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        setError(tr("Open a project before creating its GitHub repository."));
        return false;
    }
    if (!m_currentProject.value("gitRepository").toMap().value("remoteUrl").toString().isEmpty()) {
        setError(tr("This project already has a remote repository."));
        return false;
    }
    if (m_currentProject.value("gitRepository").toMap().isEmpty()) {
        initializeRepository();
        if (!m_lastError.isEmpty()) {
            return false;
        }
    }
    if (m_accessToken.isEmpty()) {
        m_accessToken = CredentialStore::readGitHubToken();
    }
    if (!m_accessToken.isEmpty()) {
        return createPrivateGitHubRepositoryWithToken(m_accessToken);
    }

    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "github_begin_authorization"},
        {"client_id", QString::fromLatin1(kGitHubOAuthClientId)},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return false;
    }
    m_pendingAuthorization = reply.value("result").toMap();
    m_pendingGitHubCreation = true;
    if (githubAuthorizationCode().isEmpty() || githubAuthorizationUrl().isEmpty()) {
        cancelInvitationAuthorization();
        setError(tr("GitHub returned an incomplete authorization response."));
        return false;
    }
    emit githubAuthorizationChanged();
    QGuiApplication::clipboard()->setText(githubAuthorizationCode());
    QDesktopServices::openUrl(QUrl(githubAuthorizationUrl()));
    emit info(tr("The GitHub code was copied. Authorize it in the browser, then choose Continue."));
    return false;
}

bool WorkspaceController::finishGitHubRepositoryCreation()
{
    if (!m_pendingGitHubCreation) {
        setError(tr("Start GitHub repository creation first."));
        return false;
    }
    QString accessToken;
    if (!finishGitHubAuthorization(&accessToken)) {
        return false;
    }
    cancelInvitationAuthorization();
    return createPrivateGitHubRepositoryWithToken(accessToken);
}

bool WorkspaceController::createPrivateGitHubRepositoryWithToken(const QString &accessToken)
{
    setError({});
    setBusy(true);
    const QVariantMap createReply = runCommand({
        {"command", "github_create_private_repository"},
        {"name", m_currentProject.value("name").toString()},
        {"access_token", accessToken},
    });
    setBusy(false);
    if (!createReply.value("ok").toBool()) {
        setError(createReply.value("error").toMap().value("message").toString());
        return false;
    }
    const QVariantMap repository = createReply.value("result").toMap();
    const QString cloneUrl = repository.value("cloneUrl").toString();
    if (cloneUrl.isEmpty()) {
        setError(tr("GitHub created the repository but returned no clone URL."));
        return false;
    }
    connectRepository(cloneUrl);
    if (!m_lastError.isEmpty()) {
        return false;
    }
    synchronize();
    if (!m_lastError.isEmpty()) {
        return false;
    }
    emit info(tr("Private GitHub repository created and synchronized."));
    return true;
}

bool WorkspaceController::inviteGitHubCollaborator(const QString &username)
{
    const QString collaborator = username.trimmed();
    const QString remoteUrl = m_currentProject.value("gitRepository").toMap()
                                  .value("remoteUrl").toString();
    if (collaborator.isEmpty() || remoteUrl.isEmpty()) {
        setError(tr("Enter a GitHub username after connecting the repository."));
        return false;
    }
    if (m_accessToken.isEmpty()) {
        m_accessToken = CredentialStore::readGitHubToken();
    }
    if (m_accessToken.isEmpty()) {
        setError(tr("Authorize GitHub by creating the private repository in this app first."));
        return false;
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "github_invite_collaborator"},
        {"username", collaborator},
        {"repository_url", remoteUrl},
        {"access_token", m_accessToken},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return false;
    }
    emit info(tr("GitHub invitation sent to %1.").arg(collaborator));
    return true;
}

QString WorkspaceController::createInvitation()
{
    const QVariantMap repository = m_currentProject.value("gitRepository").toMap();
    const QString remoteUrl = repository.value("remoteUrl").toString();
    if (m_currentProjectId.isEmpty() || remoteUrl.isEmpty()) {
        setError(tr("Connect and synchronize a remote repository first."));
        return {};
    }
    setError({});
    const QVariantMap reply = runCommand({
        {"command", "create_invitation"},
        {"project_id", m_currentProjectId},
        {"project_name", m_currentProject.value("name").toString()},
        {"remote_url", remoteUrl},
        {"default_branch", repository.value("defaultBranch").toString()},
    });
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return {};
    }
    const QString invitation = reply.value("result").toMap().value("invitation").toString();
    if (!invitation.isEmpty()) {
        QGuiApplication::clipboard()->setText(invitation);
        emit info(tr("Invitation code copied to the clipboard."));
    }
    return invitation;
}

bool WorkspaceController::acceptInvitation(const QString &invitationToken)
{
    if (!m_client) {
        setError(tr("The application core is not available."));
        return false;
    }

    const QString invitation = invitationToken.trimmed();
    if (invitation.isEmpty()) {
        setError(tr("Enter an invitation code."));
        return false;
    }

    setError({});
    setBusy(true);

    const QVariantMap invitationReply = runCommand({
        {"command", "read_invitation"},
        {"invitation", invitation},
    });
    if (!invitationReply.value("ok").toBool()) {
        setBusy(false);
        setError(invitationReply.value("error").toMap().value("message").toString());
        return false;
    }

    const QVariantMap invitationData = invitationReply.value("result").toMap();
    const QString remoteUrl = invitationData.value("remoteUrl").toString().trimmed();
    if (remoteUrl.isEmpty()) {
        setBusy(false);
        setError(tr("The invitation code does not contain a repository address."));
        return false;
    }

    const QVariantMap githubReply = runCommand({
        {"command", "remote_uses_github"},
        {"remote_url", remoteUrl},
    });
    if (!githubReply.value("ok").toBool()) {
        setBusy(false);
        setError(githubReply.value("error").toMap().value("message").toString());
        return false;
    }

    const bool usesGitHub =
        githubReply.value("result").toMap().value("usesGitHub").toBool();
    if (usesGitHub && m_accessToken.isEmpty()) {
        m_accessToken = CredentialStore::readGitHubToken();
    }
    if (!usesGitHub || !m_accessToken.isEmpty()) {
        setBusy(false);
        return joinInvitationRemote(remoteUrl, m_accessToken);
    }

    const QVariantMap authorizationReply = runCommand({
        {"command", "github_begin_authorization"},
        {"client_id", QString::fromLatin1(kGitHubOAuthClientId)},
    });
    setBusy(false);
    if (!authorizationReply.value("ok").toBool()) {
        setError(authorizationReply.value("error").toMap().value("message").toString());
        return false;
    }

    m_pendingAuthorization = authorizationReply.value("result").toMap();
    m_pendingRemoteUrl = remoteUrl;
    if (githubAuthorizationCode().isEmpty() || githubAuthorizationUrl().isEmpty()) {
        cancelInvitationAuthorization();
        setError(tr("GitHub returned an incomplete authorization response."));
        return false;
    }
    emit githubAuthorizationChanged();
    QGuiApplication::clipboard()->setText(githubAuthorizationCode());
    emit info(tr("The GitHub code was copied. Choose Open GitHub, authorize it, then Continue."));
    return false;
}

bool WorkspaceController::finishInvitationAuthorization()
{
    if (m_pendingGitHubCreation) {
        setError(tr("Continue GitHub repository creation from Share & Sync."));
        return false;
    }
    if (m_pendingAuthorization.isEmpty() || m_pendingRemoteUrl.isEmpty()) {
        setError(tr("Start the invitation again to authorize GitHub."));
        return false;
    }

    QString accessToken;
    if (!finishGitHubAuthorization(&accessToken)) {
        return false;
    }
    const QString remoteUrl = m_pendingRemoteUrl;
    cancelInvitationAuthorization();
    return joinInvitationRemote(remoteUrl, accessToken);
}

bool WorkspaceController::finishGitHubAuthorization(QString *accessToken)
{
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "github_finish_authorization"},
        {"client_id", QString::fromLatin1(kGitHubOAuthClientId)},
        {"authorization", m_pendingAuthorization},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return false;
    }
    const QString token = reply.value("result").toMap().value("accessToken").toString();
    if (token.isEmpty()) {
        setError(tr("GitHub authorized the app but returned no access token."));
        return false;
    }
    m_accessToken = token;
    QString credentialError;
    if (!CredentialStore::writeGitHubToken(token, &credentialError)) {
        emit info(tr("GitHub was authorized, but the token could not be saved securely: %1")
                  .arg(credentialError));
    }
    if (accessToken) {
        *accessToken = token;
    }
    return true;
}

void WorkspaceController::cancelInvitationAuthorization()
{
    if (m_pendingAuthorization.isEmpty() && m_pendingRemoteUrl.isEmpty()) {
        return;
    }
    m_pendingAuthorization.clear();
    m_pendingRemoteUrl.clear();
    m_pendingGitHubCreation = false;
    emit githubAuthorizationChanged();
}

bool WorkspaceController::joinInvitationRemote(const QString &remoteUrl,
                                               const QString &accessToken)
{
    setBusy(true);
    QVariantMap joinCommand{
        {"command", "join_stored_project"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"repositories_root", m_repositoriesRoot},
        {"remote_url", remoteUrl},
    };
    if (!accessToken.isEmpty()) {
        joinCommand.insert("access_token", accessToken);
    }
    const QVariantMap joinReply = runCommand(joinCommand);
    setBusy(false);
    if (!joinReply.value("ok").toBool()) {
        setError(joinReply.value("error").toMap().value("message").toString());
        return false;
    }

    const QVariantMap project = joinReply.value("result").toMap().value("project").toMap();
    if (project.isEmpty()) {
        setError(tr("The shared project was cloned but the core returned no project data."));
        return false;
    }

    applyProject(project);
    m_currentProjectId = project.value("id").toString();
    m_currentProject = project;
    emit currentProjectChanged();
    refreshCurrent();
    emit info(tr("Shared project joined."));
    return true;
}

void WorkspaceController::exportMarkdown(const QUrl &targetFile)
{
    exportMarkdownSelection(targetFile, QStringLiteral("all"), {});
}

void WorkspaceController::exportMarkdownSelection(const QUrl &targetFile,
                                                  const QString &scope,
                                                  const QVariantList &storyIds)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    const QString path = targetFile.isLocalFile() ? targetFile.toLocalFile() : targetFile.toString();
    QVariantList portableStories;
    const QString prefix = m_currentProject.value("prefix").toString();
    for (const QVariant &storyValue : m_currentProject.value("stories").toList()) {
        const QVariantMap story = storyValue.toMap();
        const QString storyId = story.value("id").toString();
        const QString status = story.value("status").toString();
        if ((scope == QLatin1String("active") && status != QLatin1String("active"))
            || (scope == QLatin1String("draft") && status != QLatin1String("draft"))
            || (scope == QLatin1String("done") && status != QLatin1String("done"))
            || (scope == QLatin1String("selected") && !storyIds.contains(storyId))) {
            continue;
        }
        const QString actorId = story.value("actorId").toString();
        QVariantMap actor;
        for (const QVariant &actorValue : m_currentProject.value("actors").toList()) {
            if (actorValue.toMap().value("id").toString() == actorId) {
                actor = actorValue.toMap();
                break;
            }
        }
        portableStories.append(QVariantMap{
            {"id", story.value("id")},
            {"originalReference", QStringLiteral("%1-%2").arg(prefix).arg(story.value("number").toInt())},
            {"title", story.value("title")},
            {"profileName", actor.value("name", tr("Unknown actor"))},
            {"profileDescription", actor.value("role")},
            {"want", story.value("want")},
            {"outcome", story.value("outcome")},
            {"notes", story.value("notes")},
            {"acceptanceCriteria", story.value("acceptanceCriteria")},
            {"status", story.value("status")},
            {"createdAt", story.value("createdAt")},
        });
    }
    if (portableStories.isEmpty()) {
        setError(tr("There are no stories to export."));
        return;
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "export_markdown"},
        {"document", QVariantMap{
            {"projectName", m_currentProject.value("name")},
            {"projectPrefix", prefix},
            {"stories", portableStories},
        }},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        setError(tr("The export file could not be written: %1").arg(file.errorString()));
        return;
    }
    file.write(reply.value("result").toMap().value("markdown").toString().toUtf8());
    emit info(tr("Exported to %1").arg(path));
}

void WorkspaceController::importMarkdown(const QUrl &sourceFile)
{
    if (!prepareMarkdownImport(sourceFile)) {
        return;
    }
    QVariantList storyIds;
    for (const QVariant &story : std::as_const(m_pendingImportStories)) {
        storyIds.append(story.toMap().value("id"));
    }
    applyPreparedMarkdownImport(storyIds);
}

bool WorkspaceController::prepareMarkdownImport(const QUrl &sourceFile)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return false;
    }
    const QString path = sourceFile.isLocalFile() ? sourceFile.toLocalFile() : sourceFile.toString();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        setError(tr("The import file could not be read: %1").arg(file.errorString()));
        return false;
    }
    setError({});
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "import_markdown"},
        {"markdown", QString::fromUtf8(file.readAll())},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return false;
    }
    m_pendingImportStories = reply.value("result").toMap().value("stories").toList();
    m_pendingImportPath = path;
    emit pendingImportStoriesChanged();
    return !m_pendingImportStories.isEmpty();
}

bool WorkspaceController::applyPreparedMarkdownImport(const QVariantList &storyIds)
{
    QVariantList stories;
    for (const QVariant &storyValue : std::as_const(m_pendingImportStories)) {
        const QVariantMap story = storyValue.toMap();
        if (storyIds.contains(story.value("id"))) {
            stories.append(story);
        }
    }
    if (stories.isEmpty()) {
        setError(tr("Select at least one story to import."));
        return false;
    }
    if (!applyCurrentOperation({
            {"operation", "import_stories"},
            {"stories", stories},
            {"imported_profile_name", tr("Imported Profile")},
        })) {
        return false;
    }
    const QString path = m_pendingImportPath;
    cancelPreparedMarkdownImport();
    emit info(tr("Imported from %1").arg(path));
    return true;
}

void WorkspaceController::cancelPreparedMarkdownImport()
{
    if (m_pendingImportStories.isEmpty() && m_pendingImportPath.isEmpty()) {
        return;
    }
    m_pendingImportStories.clear();
    m_pendingImportPath.clear();
    emit pendingImportStoriesChanged();
}

void WorkspaceController::setMcpServerActive(bool active)
{
    if (m_mcpServerActive == active) {
        return;
    }
    m_mcpServerActive = active;
    emit mcpServerStateChanged();
}

void WorkspaceController::copyMcpServerUrl()
{
    QGuiApplication::clipboard()->setText(mcpServerUrl());
    emit info(tr("MCP URL copied."));
}

void WorkspaceController::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

void WorkspaceController::setError(const QString &message)
{
    if (message == m_lastError) {
        return;
    }
    m_lastError = message;
    emit lastErrorChanged();
    if (!message.isEmpty()) {
        qCWarning(lcWorkspace) << message;
    }
}

QVariantMap WorkspaceController::runCommand(const QVariantMap &command)
{
    if (!m_client) {
        return QVariantMap{
            {"ok", false},
            {"error", QVariantMap{
                {"code", "no_core"},
                {"message", "Core client is not configured."}}}};
    }
    return m_client->execute(command);
}

void WorkspaceController::applyProject(const QVariantMap &project)
{
    const bool isCurrent = project.value("id").toString() == m_currentProjectId;
    if (isCurrent) {
        m_currentProject = project;
    }
    for (int i = 0; i < m_projects.size(); ++i) {
        if (m_projects[i].toMap().value("id").toString() == project.value("id").toString()) {
            m_projects[i] = project;
            emit projectsChanged();
            if (isCurrent) {
                emit currentProjectChanged();
            }
            return;
        }
    }
    m_projects.append(project);
    emit projectsChanged();
    if (isCurrent) {
        emit currentProjectChanged();
    }
}

bool WorkspaceController::applyCurrentOperation(QVariantMap operation)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        setError(tr("Open a project first."));
        return false;
    }
    setError({});
    operation.insert("command", "apply_stored_workspace_command");
    operation.insert("database_path", m_databasePath);
    operation.insert("project_id", m_currentProjectId);
    setBusy(true);
    const QVariantMap reply = runCommand(operation);
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return false;
    }
    const QVariantMap project = reply.value("result").toMap().value("project").toMap();
    if (project.isEmpty()) {
        setError(tr("The core did not return the updated project."));
        return false;
    }
    applyProject(project);
    refreshCurrent();
    scheduleAutomaticSynchronization();
    return true;
}

bool WorkspaceController::currentProjectHasRemote() const
{
    return !m_currentProject.value("gitRepository").toMap()
                .value("remoteUrl").toString().trimmed().isEmpty();
}

void WorkspaceController::scheduleAutomaticSynchronization()
{
    // Local-only projects must stay local until the user explicitly connects
    // a repository. This also prevents pointless background core calls.
    if (!currentProjectHasRemote()) {
        return;
    }

    if (!m_localChangeWindow.isValid()) {
        m_localChangeWindow.start();
    }
    const int remaining = qMax(0, kAutoSyncMaximumDelayMs
                                  - static_cast<int>(m_localChangeWindow.elapsed()));
    m_autoSyncTimer.start(qMin(kAutoSyncDebounceMs, remaining));
}

void WorkspaceController::runAutomaticSynchronization()
{
    if (!currentProjectHasRemote() || m_busy) {
        return;
    }

    // A background pull also publishes queued edits.  Manual synchronization
    // remains available for an immediate, user-visible refresh.
    m_localChangeWindow.invalidate();
    synchronizeCurrentProject(false);
}

} // namespace fsuserstories
