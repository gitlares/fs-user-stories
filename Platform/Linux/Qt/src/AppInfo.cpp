// SPDX-License-Identifier: MIT
#include "AppInfo.h"

namespace fsuserstories {

QString AppInfo::version()      { return QStringLiteral("0.1.0-alpha"); }
QString AppInfo::name()         { return QStringLiteral("FS User Stories"); }
QString AppInfo::organization() { return QStringLiteral("FS User Stories"); }
QString AppInfo::domain()       { return QStringLiteral("gitlares.github.io"); }

} // namespace fsuserstories
