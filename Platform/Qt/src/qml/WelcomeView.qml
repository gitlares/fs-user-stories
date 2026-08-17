// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    function openCreateProject() { newProjectDialog.open() }
    function openJoinShared()    { joinSharedDialog.open() }

    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Rectangle {
        anchors.fill: parent
        color: palette.window

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 22
            width: 380

            // Rounded icon tile (matches mac "text.badge.plus" 64x64 tile).
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 64; height: 64; radius: 18
                color: Qt.rgba(0.34, 0.40, 0.95, 0.10)   // accent-tinted background
                IconLabel {
                    anchors.centerIn: parent
                    text: "note_add"
                    font.pixelSize: 30
                    color: "#4f56d2"
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8
                Label {
                    text: qsTr("Start with a project")
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("Create a focused space for your actors and user stories.")
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 360
                    opacity: 0.7
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                spacing: 8

                Button {
                    text: qsTr("Create Project")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    highlighted: true
                    onClicked: root.openCreateProject()
                }
                Button {
                    text: qsTr("Use an Invitation")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    onClicked: root.openJoinShared()
                }
                Button {
                    text: qsTr("Connect Existing Repository")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    onClicked: root.openJoinShared()
                }
            }
        }
    }

    // ---- Reusable dialogs (also used from toolbar) ----
    Dialog {
        id: newProjectDialog
        title: qsTr("Create Project")
        modal: true
        anchors.centerIn: parent
        width: 380
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: qsTr("Name") }
            TextField { id: npName; placeholderText: qsTr("My project"); Layout.fillWidth: true }
            Label { text: qsTr("Prefix (3 letters, uppercase)") }
            TextField { id: npPrefix; placeholderText: qsTr("ABC"); Layout.fillWidth: true; maxLength: 3 }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Create")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: npName.text.trim() !== "" && npPrefix.text.trim() !== ""
                onClicked: {
                    workspace.createProject(npName.text.trim(), npPrefix.text.trim().toUpperCase())
                    close()
                }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: close()
            }
        }
    }

    Dialog {
        id: joinSharedDialog
        title: qsTr("Join Shared Project")
        modal: true
        anchors.centerIn: parent
        width: 460
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: qsTr("Paste the invitation URL:"); wrapMode: Text.WordWrap; Layout.fillWidth: true }
            TextField { id: inviteToken; placeholderText: qsTr("https://…/invitation/…"); Layout.fillWidth: true }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Join"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: inviteToken.text.trim() !== ""
                onClicked: { workspace.acceptInvitation(inviteToken.text.trim()); close() }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: close()
            }
        }
    }
}
