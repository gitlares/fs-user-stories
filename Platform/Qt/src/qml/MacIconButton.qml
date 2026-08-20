// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls

ToolButton {
    id: control
    property string iconName: ""
    property bool circular: false
    property bool compact: false
    Theme { id: theme }
    implicitWidth: compact ? 26 : 32
    implicitHeight: compact ? 26 : 30
    padding: 5
    contentItem: Label {
        text: control.iconName
        font.family: appIconFont
        font.pixelSize: control.compact ? 15 : 18
        font.weight: Font.DemiBold
        color: theme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: control.enabled ? 1 : 0.38
    }
    background: Rectangle {
        radius: control.circular ? height / 2 : theme.smallRadius
        color: control.down || control.hovered ? theme.controlHover : Qt.rgba(1, 1, 1, 0.72)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.04)
        Rectangle {
            x: 1; y: 1; width: parent.width; height: parent.height; radius: parent.radius
            color: Qt.rgba(0, 0, 0, 0.07); z: -1
        }
    }
}
