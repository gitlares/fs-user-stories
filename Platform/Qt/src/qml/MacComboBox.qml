// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    Theme { id: theme }
    implicitHeight: 30
    leftPadding: 10; rightPadding: 28
    font.pixelSize: 12

    delegate: ItemDelegate {
        required property var modelData
        width: control.popup.width
        implicitHeight: 30
        contentItem: Label {
            text: control.textRole ? modelData[control.textRole] : modelData
            color: theme.text; font.pixelSize: 12
            verticalAlignment: Text.AlignVCenter
        }
        highlighted: control.highlightedIndex === index
        background: Rectangle {
            radius: 5
            color: parent.highlighted ? theme.selection : "transparent"
        }
    }
    indicator: Label {
        x: control.width - width - 8; anchors.verticalCenter: parent.verticalCenter
        text: "unfold_more"; font.family: appIconFont; font.pixelSize: 15; color: theme.secondaryText
    }
    contentItem: Label {
        leftPadding: 0; rightPadding: control.indicator.width + control.spacing
        text: control.displayText; font: control.font; color: theme.text
        verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
    }
    background: Rectangle {
        radius: theme.smallRadius; color: control.down ? theme.controlHover : theme.control
        border.width: 0
    }
    popup: Popup {
        y: control.height + 4; width: control.width; implicitHeight: contentItem.implicitHeight + 8
        padding: 4
        contentItem: ListView {
            clip: true; implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle {
            radius: theme.mediumRadius; color: theme.panel; border.width: 1; border.color: theme.separator
        }
    }
}
