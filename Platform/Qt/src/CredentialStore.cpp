// SPDX-License-Identifier: MIT
#include "CredentialStore.h"

#include <QEventLoop>
#include <qtkeychain/keychain.h>

namespace fsuserstories {

namespace {
const QString kService = QStringLiteral("com.nuboohub.fs-user-stories");
const QString kGitHubTokenKey = QStringLiteral("github-access-token");
}

QString CredentialStore::readGitHubToken(QString *errorMessage)
{
    QKeychain::ReadPasswordJob job(kService);
    job.setAutoDelete(false);
    job.setInsecureFallback(false);
    job.setKey(kGitHubTokenKey);

    QEventLoop loop;
    QObject::connect(&job, &QKeychain::Job::finished, &loop, &QEventLoop::quit);
    job.start();
    loop.exec();

    if (job.error() == QKeychain::NoError) {
        return job.textData();
    }
    if (job.error() != QKeychain::EntryNotFound && errorMessage) {
        *errorMessage = job.errorString();
    }
    return {};
}

bool CredentialStore::writeGitHubToken(const QString &token,
                                       QString *errorMessage)
{
    QKeychain::WritePasswordJob job(kService);
    job.setAutoDelete(false);
    job.setInsecureFallback(false);
    job.setKey(kGitHubTokenKey);
    job.setTextData(token);

    QEventLoop loop;
    QObject::connect(&job, &QKeychain::Job::finished, &loop, &QEventLoop::quit);
    job.start();
    loop.exec();

    if (job.error() == QKeychain::NoError) {
        return true;
    }
    if (errorMessage) {
        *errorMessage = job.errorString();
    }
    return false;
}

} // namespace fsuserstories
