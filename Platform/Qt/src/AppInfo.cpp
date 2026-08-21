// SPDX-License-Identifier: MIT
#include "AppInfo.h"

namespace fsuserstories {

QString AppInfo::version()      { return QStringLiteral("1.0.5"); }
QString AppInfo::name()         { return QStringLiteral("FS User Stories"); }
QString AppInfo::organization() { return QStringLiteral("FS User Stories"); }
QString AppInfo::domain()       { return QStringLiteral("gitlares.github.io"); }

} // namespace fsuserstories
