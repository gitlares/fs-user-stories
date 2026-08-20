// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls

ProgressBar {
    id: control
    Theme { id: theme }
    implicitHeight: 5
    background: Rectangle {
        implicitHeight: 5
        radius: 3
        color: theme.control
    }
    contentItem: Item {
        implicitHeight: 5
        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: 3
            color: control.value >= 1 ? theme.green : theme.accent
        }
    }
}
