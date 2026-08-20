// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string invitationCode: ""
    property var conflictChoices: ({})
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
                            visible: !Boolean(root.repository.remoteUrl)
                            text: qsTr("Create Private GitHub Repository")
                            iconName: "cloud_upload"
                            prominent: true
                            enabled: !workspace.busy
                            onClicked: workspace.createPrivateGitHubRepository()
                        }
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
                    Rectangle {
                        visible: workspace.githubAuthorizationPending
                                 && workspace.githubAuthorizationForRepositoryCreation
                        Layout.fillWidth: true
                        implicitHeight: authorizationContent.implicitHeight + 24
                        radius: theme.mediumRadius
                        color: theme.control
                        ColumnLayout {
                            id: authorizationContent
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8
                            Label {
                                text: qsTr("Authorize FS User Stories on GitHub")
                                font.weight: Font.DemiBold
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: theme.secondaryText
                                text: qsTr("The code is already copied. Paste it in the GitHub page that opened, approve access, then return here.")
                            }
                            Label {
                                text: workspace.githubAuthorizationCode
                                font.family: "monospace"
                                font.pixelSize: 20
                                font.weight: Font.Bold
                            }
                            RowLayout {
                                MacButton {
                                    text: qsTr("Open GitHub Again")
                                    onClicked: Qt.openUrlExternally(workspace.githubAuthorizationUrl)
                                }
                                Item { Layout.fillWidth: true }
                                MacButton {
                                    text: qsTr("Cancel")
                                    onClicked: workspace.cancelInvitationAuthorization()
                                }
                                MacButton {
                                    text: qsTr("Continue")
                                    prominent: true
                                    onClicked: workspace.finishGitHubRepositoryCreation()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: workspace.pendingSyncConflicts.length > 0
                Layout.fillWidth: true; implicitHeight: conflictContent.implicitHeight + 36
                radius: theme.cardRadius; color: "#fff8e6"; border.width: 1; border.color: "#e4b84c"
                ColumnLayout {
                    id: conflictContent; anchors.fill: parent; anchors.margins: 18; spacing: 10
                    Label { text: qsTr("Synchronization Conflicts"); font.pixelSize: 16; font.weight: Font.DemiBold }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap; color: theme.secondaryText
                        text: qsTr("Both copies changed the same item. Choose which version to keep for each conflict.")
                    }
                    Repeater {
                        model: workspace.pendingSyncConflicts
                        delegate: RowLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: (modelData.entityType || qsTr("Item")) + " · " + (modelData.entityId || "")
                                elide: Text.ElideMiddle
                            }
                            MacComboBox {
                                id: choice
                                model: [qsTr("Choose…"), qsTr("Keep Mine"), qsTr("Use Shared")]
                                onCurrentIndexChanged: root.conflictChoices[index] = currentIndex
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        MacButton {
                            text: qsTr("Resolve and Synchronize")
                            prominent: true
                            onClicked: {
                                var resolutions = []
                                for (var i = 0; i < workspace.pendingSyncConflicts.length; i++) {
                                    var selected = root.conflictChoices[i] || 0
                                    if (selected === 0) {
                                        return
                                    }
                                    var conflict = workspace.pendingSyncConflicts[i]
                                    resolutions.push({
                                        entityType: conflict.entityType,
                                        entityId: conflict.entityId,
                                        choice: selected === 2 ? "shared" : "mine"
                                    })
                                }
                                if (workspace.resolveSynchronization(resolutions))
                                    root.conflictChoices = ({})
                            }
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
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: theme.separator
                    }
                    Label {
                        text: qsTr("Invite a GitHub Collaborator")
                        font.weight: Font.DemiBold
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        MacTextField {
                            id: collaboratorField
                            Layout.fillWidth: true
                            placeholderText: qsTr("GitHub username")
                        }
                        MacButton {
                            text: qsTr("Send Invitation")
                            enabled: collaboratorField.text.trim() !== "" && !workspace.busy
                            onClicked: {
                                if (workspace.inviteGitHubCollaborator(collaboratorField.text))
                                    collaboratorField.clear()
                            }
                        }
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
