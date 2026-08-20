// SPDX-License-Identifier: MIT
#include "WorkspaceController.h"
#include "CoreClient.h"
#include "CorePaths.h"
#include "StoryModel.h"

#include <QFileInfo>
#include <QDesktopServices>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QUrl>

Q_LOGGING_CATEGORY(lcWorkspace, "fsuserstories.workspace")

namespace fsuserstories {

namespace {
constexpr auto kGitHubOAuthClientId = "Ov23liEDQnlgdtJTGCUt";
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
    };
    if (!statusFilter.isEmpty()) {
        searchQuery.insert("status", statusFilter);
    }
    if (!profileFilter.isEmpty()) {
        searchQuery.insert("profileId", profileFilter);
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

void WorkspaceController::createStory(const QString &title,
                                      const QString &asA,
                                      const QString &iWant,
                                      const QString &soThat)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    QVariantMap command{
        {"command", "apply_stored_workspace_command"},
        {"database_path", m_databasePath},
        {"project_id", m_currentProjectId},
        {"operation", "add_story"},
        {"title", title},
        {"asA", asA},
        {"iWant", iWant},
        {"soThat", soThat},
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
        applyProject(project);
    }
    refreshCurrent();
}

void WorkspaceController::updateStory(const QString &storyId, const QVariantMap &fields)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    QVariantMap command{
        {"command", "apply_stored_workspace_command"},
        {"database_path", m_databasePath},
        {"project_id", m_currentProjectId},
        {"operation", "update_story"},
        {"storyId", storyId},
    };
    for (auto it = fields.constBegin(); it != fields.constEnd(); ++it) {
        command.insert(it.key(), it.value());
    }
    setBusy(true);
    const QVariantMap reply = runCommand(command);
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
}

void WorkspaceController::synchronize()
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "synchronize_stored_project"},
        {"database_path", m_databasePath},
        {"attachments_root", m_attachmentsRoot},
        {"project_id", m_currentProjectId},
        {"access_token", m_accessToken.isEmpty() ? QVariant() : QVariant(m_accessToken)},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        const QVariantMap errorValue = reply.value("error").toMap();
        if (errorValue.value("code").toString() == QLatin1String("sync_conflicts")) {
            const QVariantList conflicts =
                errorValue.value("details").toMap().value("conflicts").toList();
            emit syncConflicts(conflicts);
            return;
        }
        setError(errorValue.value("message").toString());
        return;
    }
    emit info(tr("Project synchronized."));
    refreshCurrent();
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
    QDesktopServices::openUrl(QUrl(githubAuthorizationUrl()));
    emit info(tr("Authorize GitHub in the browser, then return and choose Continue."));
    return false;
}

bool WorkspaceController::finishInvitationAuthorization()
{
    if (m_pendingAuthorization.isEmpty() || m_pendingRemoteUrl.isEmpty()) {
        setError(tr("Start the invitation again to authorize GitHub."));
        return false;
    }

    setError({});
    setBusy(true);
    const QVariantMap authorizationReply = runCommand({
        {"command", "github_finish_authorization"},
        {"client_id", QString::fromLatin1(kGitHubOAuthClientId)},
        {"authorization", m_pendingAuthorization},
    });
    setBusy(false);
    if (!authorizationReply.value("ok").toBool()) {
        setError(authorizationReply.value("error").toMap().value("message").toString());
        return false;
    }

    const QString accessToken =
        authorizationReply.value("result").toMap().value("accessToken").toString();
    if (accessToken.isEmpty()) {
        setError(tr("GitHub authorized the app but returned no access token."));
        return false;
    }

    m_accessToken = accessToken;
    const QString remoteUrl = m_pendingRemoteUrl;
    cancelInvitationAuthorization();
    return joinInvitationRemote(remoteUrl, m_accessToken);
}

void WorkspaceController::cancelInvitationAuthorization()
{
    if (m_pendingAuthorization.isEmpty() && m_pendingRemoteUrl.isEmpty()) {
        return;
    }
    m_pendingAuthorization.clear();
    m_pendingRemoteUrl.clear();
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
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    const QString path = targetFile.isLocalFile() ? targetFile.toLocalFile() : targetFile.toString();
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "export_markdown"},
        {"document", QVariantMap{
            {"projectId", m_currentProjectId},
            {"targetPath", path},
        }},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    emit info(tr("Exported to %1").arg(path));
}

void WorkspaceController::importMarkdown(const QUrl &sourceFile)
{
    if (!m_client || m_currentProjectId.isEmpty()) {
        return;
    }
    const QString path = sourceFile.isLocalFile() ? sourceFile.toLocalFile() : sourceFile.toString();
    setBusy(true);
    const QVariantMap reply = runCommand({
        {"command", "import_markdown"},
        {"markdown", QVariantMap{
            {"projectId", m_currentProjectId},
            {"sourcePath", path},
        }},
    });
    setBusy(false);
    if (!reply.value("ok").toBool()) {
        setError(reply.value("error").toMap().value("message").toString());
        return;
    }
    emit info(tr("Imported from %1").arg(path));
    refreshCurrent();
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
    for (int i = 0; i < m_projects.size(); ++i) {
        if (m_projects[i].toMap().value("id").toString() == project.value("id").toString()) {
            m_projects[i] = project;
            emit projectsChanged();
            return;
        }
    }
    m_projects.append(project);
    emit projectsChanged();
}

} // namespace fsuserstories
