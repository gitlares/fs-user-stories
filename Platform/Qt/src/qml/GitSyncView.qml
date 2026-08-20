// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string invitationCode: ""
    readonly property var repository: workspace.currentProject.gitRepository || ({})
    Theme { id: theme }
    Rectangle { anchors.fill: parent; color: theme.window }

    ScrollView {
        anchors.fill: parent; clip: true
        ColumnLayout {
            width: Math.max(480, root.width - 40); x: 20; y: 16; spacing: 16
            Label { text: qsTr("Share & Sync"); font.pixelSize: 24; font.weight: Font.DemiBold }
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: theme.secondaryText
                text: qsTr("Keep the local SQLite workspace synchronized through a private Git repository.")
            }

            Rectangle {
                Layout.fillWidth: true; implicitHeight: localContent.implicitHeight + 36
                radius: theme.cardRadius; color: theme.panel; border.width: 1; border.color: theme.separator
                ColumnLayout {
                    id: localContent; anchors.fill: parent; anchors.margins: 18; spacing: 12
                    RowLayout {
                        Label { text: qsTr("Local Repository"); font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Rectangle { width: 8; height: 8; radius: 4; color: root.repository.localPath ? theme.green : theme.tertiaryText }
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 11
                        color: theme.secondaryText
                        text: root.repository.localPath || qsTr("Not initialized")
                    }
                    MacButton {
                        visible: !Boolean(root.repository.localPath)
                        text: qsTr("Initialize Local Repository"); iconName: "folder_open"; prominent: true
                        onClicked: workspace.initializeRepository()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; implicitHeight: remoteContent.implicitHeight + 36
                radius: theme.cardRadius; color: theme.panel; border.width: 1; border.color: theme.separator
                ColumnLayout {
                    id: remoteContent; anchors.fill: parent; anchors.margins: 18; spacing: 10
                    Label { text: qsTr("Remote Repository"); font.pixelSize: 16; font.weight: Font.DemiBold }
                    Label { text: qsTr("HTTPS Git URL"); color: theme.secondaryText; font.pixelSize: 12 }
                    MacTextField {
                        id: remoteField; Layout.fillWidth: true
                        text: root.repository.remoteUrl || ""
                        placeholderText: "https://github.com/owner/repository.git"
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        MacButton {
                            text: root.repository.remoteUrl ? qsTr("Update Remote") : qsTr("Connect Remote")
                            enabled: Boolean(root.repository.localPath) && remoteField.text.trim() !== ""
                            onClicked: workspace.connectRepository(remoteField.text.trim())
                        }
                        Item { Layout.fillWidth: true }
                        MacButton {
                            text: qsTr("Synchronize"); iconName: "sync"; prominent: true
                            enabled: Boolean(root.repository.remoteUrl) && !workspace.busy
                            onClicked: workspace.synchronize()
                        }
                    }
                }
            }

            Rectangle {
                visible: Boolean(root.repository.remoteUrl)
                Layout.fillWidth: true; implicitHeight: shareContent.implicitHeight + 36
                radius: theme.cardRadius; color: theme.panel; border.width: 1; border.color: theme.separator
                ColumnLayout {
                    id: shareContent; anchors.fill: parent; anchors.margins: 18; spacing: 10
                    RowLayout {
                        Label { text: qsTr("Invitation"); font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        MacButton {
                            text: qsTr("Create Invitation"); iconName: "person_add"
                            onClicked: root.invitationCode = workspace.createInvitation()
                        }
                    }
                    Label {
                        visible: root.invitationCode === ""; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: qsTr("Generate a portable invitation code for another FS User Stories user.")
                        color: theme.secondaryText
                    }
                    TextArea {
                        visible: root.invitationCode !== ""; text: root.invitationCode
                        readOnly: true; selectByMouse: true; wrapMode: TextArea.WrapAnywhere
                        Layout.fillWidth: true; Layout.preferredHeight: 100; padding: 10
                        background: Rectangle { radius: theme.mediumRadius; color: theme.control }
                    }
                }
            }

            Label {
                visible: workspace.lastError !== ""; text: workspace.lastError
                color: theme.red; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
            Item { Layout.preferredHeight: 16 }
        }
    }
}
