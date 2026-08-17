// SPDX-License-Identifier: MIT
#pragma once

#include <QString>

namespace fsuserstories {

struct AppInfo
{
    static QString version();
    static QString name();
    static QString organization();
    static QString domain();
};

} // namespace fsuserstories
