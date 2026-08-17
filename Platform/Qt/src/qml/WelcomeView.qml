// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    function openCreateProject() {
        newName.text = ""
        newPrefix.text = ""
        createDialog.open()
    }

    function openJoinShared() {
        joinDialog.open()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 18
        width: 460

        Label {
            text: qsTr("Welcome to FS User Stories")
            font.pixelSize: 28
            font.bold: true
            Layout.alignment: Qt.AlignHCenter
        }
        Label {
            text: qsTr("Your stories, on your computer. Share with Git. Nothing else.")
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: projectsList.count > 0 ? (projectsList.count * 48 + 16) : 0
            visible: projectsList.count > 0
            color: palette.base
            border.color: palette.mid
            border.width: 1
            radius: 6

            ListView {
                id: projectsList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: workspace.projects
                spacing: 0
                delegate: ItemDelegate {
                    width: ListView.view ? ListView.view.width : 0
                    height: 48
                    contentItem: RowLayout {
                        spacing: 12
                        Label {
                            text: modelData.name + "  ·  " + modelData.prefix
                            Layout.fillWidth: true
                            Layout.leftMargin: 12
                            font.pixelSize: 14
                        }
                        Label {
                            text: modelData.id.substr(0, 8)
                            font.family: "monospace"
                            opacity: 0.4
                            font.pixelSize: 11
                            Layout.rightMargin: 12
                        }
                    }
                    onClicked: {
                        workspace.openProject(modelData.id)
                        settings.lastProjectId = modelData.id
                    }
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            Button {
                text: qsTr("+  New Project")
                font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 220
                onClicked: root.openCreateProject()
            }
            Button {
                text: qsTr("👥  Join Shared Project")
                font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 220
                onClicked: root.openJoinShared()
            }
        }
    }

    Dialog {
        id: createDialog
        title: qsTr("Create a new project")
        modal: true
        anchors.centerIn: parent
        width: 380
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: qsTr("Name") }
            TextField { id: newName; placeholderText: qsTr("My project"); Layout.fillWidth: true }
            Label { text: qsTr("Prefix (3 letters, uppercase)") }
            TextField { id: newPrefix; placeholderText: qsTr("ABC"); Layout.fillWidth: true; maxLength: 3 }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Create")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: newName.text.trim() !== "" && newPrefix.text.trim() !== ""
                onClicked: {
                    var id = workspace.createProject(newName.text.trim(), newPrefix.text.trim().toUpperCase())
                    createDialog.close()
                }
            }
            Button {
                text: qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: createDialog.close()
            }
        }
    }

    Dialog {
        id: joinDialog
        title: qsTr("Join Shared Project")
        modal: true
        anchors.centerIn: parent
        width: 460
        contentItem: ColumnLayout {
            spacing: 8
            Label {
                text: qsTr("Paste the invitation URL or share token you received:")
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            TextField {
                id: inviteToken
                placeholderText: qsTr("https://…/invitation/… or fs-invite:TOKEN")
                Layout.fillWidth: true
            }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Join")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: inviteToken.text.trim() !== ""
                onClicked: {
                    // WorkspaceController exposes joinSharedProject via the
                    // accept_invitation core command once we wire it. For now
                    // surface a friendly message and reload.
                    workspace.acceptInvitation(inviteToken.text.trim())
                    joinDialog.close()
                }
            }
            Button {
                text: qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: joinDialog.close()
            }
        }
    }
}
