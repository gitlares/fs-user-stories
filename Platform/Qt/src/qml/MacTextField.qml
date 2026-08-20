// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls

TextField {
    id: control
    Theme { id: theme }
    implicitHeight: 34
    leftPadding: 10; rightPadding: 10
    font.pixelSize: 13
    color: theme.text
    placeholderTextColor: theme.tertiaryText
    selectionColor: theme.accent
    background: Rectangle {
        radius: theme.smallRadius
        color: theme.panel
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? theme.accent : theme.separator
    }
}
