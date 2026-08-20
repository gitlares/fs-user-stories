// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: control
    property bool prominent: false
    property string iconName: ""
    property bool destructive: false
    property bool compact: false
    Theme { id: theme }

    implicitHeight: compact ? 28 : 34
    implicitWidth: Math.max(compact ? 32 : 72, contentRow.implicitWidth + 24)
    leftPadding: 12; rightPadding: 12; topPadding: 5; bottomPadding: 5

    contentItem: RowLayout {
        id: contentRow
        spacing: 6
        Label {
            visible: control.iconName !== ""
            text: control.iconName
            font.family: appIconFont
            font.pixelSize: control.compact ? 15 : 16
            color: control.prominent ? "white" : control.destructive ? theme.red : theme.text
        }
        Label {
            visible: control.text !== ""
            text: control.text
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: control.prominent ? "white" : control.destructive ? theme.red : theme.text
        }
    }
    background: Rectangle {
        radius: theme.smallRadius
        color: {
            if (!control.enabled) return theme.control
            if (control.prominent) return control.down ? theme.accentPressed : theme.accent
            return control.down || control.hovered ? theme.controlHover : theme.panel
        }
        border.width: control.prominent ? 0 : 1
        border.color: theme.separator
        opacity: control.enabled ? 1 : 0.48
        Rectangle {
            x: 1; y: 2; width: parent.width; height: parent.height; radius: parent.radius
            color: theme.shadow; z: -1; visible: control.enabled
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 1; height: 1; radius: 1
            visible: !control.prominent
            color: Qt.rgba(1, 1, 1, 0.8)
        }
    }
}
