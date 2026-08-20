// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string invitationCode: ""
    readonly property var repository: workspace.currentProject.gitRepository || ({})

    ColumnLayout {
        anchors.fill: parent
        spacing: 12
        Label { text: qsTr("Git Sharing"); font.pixelSize: 22; font.weight: Font.Bold }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap; opacity: 0.7
            text: root.repository.localPath
                  ? qsTr("Local repository: %1").arg(root.repository.localPath)
                  : qsTr("This project does not have a Git repository yet.")
        }
        Button {
            visible: !Boolean(root.repository.localPath)
            text: qsTr("Initialize Local Repository")
            onClicked: workspace.initializeRepository()
        }
        Label { text: qsTr("Remote repository URL"); visible: Boolean(root.repository.localPath) }
        TextField {
            id: remoteField; Layout.fillWidth: true; visible: Boolean(root.repository.localPath)
            text: root.repository.remoteUrl || ""
            placeholderText: "https://github.com/owner/repository.git"
        }
        RowLayout {
            visible: Boolean(root.repository.localPath)
            Button {
                text: root.repository.remoteUrl ? qsTr("Update Remote") : qsTr("Connect Remote")
                enabled: remoteField.text.trim() !== ""
                onClicked: workspace.connectRepository(remoteField.text.trim())
            }
            Button {
                text: qsTr("Synchronize")
                enabled: Boolean(root.repository.remoteUrl)
                onClicked: workspace.synchronize()
            }
            Button {
                text: qsTr("Create Invitation")
                enabled: Boolean(root.repository.remoteUrl)
                onClicked: root.invitationCode = workspace.createInvitation()
            }
        }
        Label { text: qsTr("Invitation code"); visible: root.invitationCode !== ""; font.weight: Font.DemiBold }
        TextArea {
            visible: root.invitationCode !== ""; text: root.invitationCode
            readOnly: true; selectByMouse: true; wrapMode: TextArea.WrapAnywhere
            Layout.fillWidth: true; Layout.preferredHeight: 110
        }
        Label {
            visible: workspace.lastError !== ""; text: workspace.lastError
            color: "#b00020"; wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Item { Layout.fillHeight: true }
    }
}
