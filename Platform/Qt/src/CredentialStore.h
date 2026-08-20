// SPDX-License-Identifier: MIT
#pragma once

#include <QString>

namespace fsuserstories {

class CredentialStore
{
public:
    static QString readGitHubToken(QString *errorMessage = nullptr);
    static bool writeGitHubToken(const QString &token,
                                 QString *errorMessage = nullptr);
};

} // namespace fsuserstories
