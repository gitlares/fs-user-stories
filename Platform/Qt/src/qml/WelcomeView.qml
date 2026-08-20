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
        font.weight: Font.DemiBold
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

            // Rounded icon tile (macOS-style: large rounded square with gradient).
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 80; height: 80; radius: 22
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "#dde6ff" }
                    GradientStop { position: 1.0; color: "#c5d4ff" }
                }
                IconLabel {
                    anchors.centerIn: parent
                    text: "note_add"
                    font.pixelSize: 40
                    font.weight: Font.Bold
                    color: "#0a52cc"
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 10
                Label {
                    text: qsTr("Start with a project")
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: qsTr("Create a focused space for your actors and user stories.")
                    font.pixelSize: 14
                    font.weight: Font.Medium
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
                    Layout.preferredHeight: 38
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    contentItem: Label {
                        text: parent.text
                        color: "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? "#006edc" : "#0a84ff"
                        border.width: 0
                    }
                    onClicked: root.openCreateProject()
                }
                Button {
                    text: qsTr("Use an Invitation")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? "#e5e5ea" : "#f5f5f7"
                        border.color: "#d1d1d6"
                        border.width: 1
                    }
                    onClicked: root.openJoinShared()
                }
                Button {
                    text: qsTr("Connect Existing Repository")
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? "#e5e5ea" : "#f5f5f7"
                        border.color: "#d1d1d6"
                        border.width: 1
                    }
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
            TextField { id: npPrefix; placeholderText: qsTr("ABC"); Layout.fillWidth: true; maximumLength: 3 }
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
            Label { text: qsTr("Paste the invitation code:"); wrapMode: Text.WordWrap; Layout.fillWidth: true }
            TextField { id: inviteToken; placeholderText: qsTr("Invitation code"); Layout.fillWidth: true }
            Label {
                visible: workspace.lastError !== ""
                text: workspace.lastError
                color: "#b00020"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            ColumnLayout {
                visible: workspace.githubAuthorizationPending
                Layout.fillWidth: true
                spacing: 6
                Label { text: qsTr("Authorize GitHub with this code:") }
                Label {
                    text: workspace.githubAuthorizationCode
                    font.family: "monospace"
                    font.pixelSize: 20
                    font.bold: true
                    selectByMouse: true
                }
                Button {
                    text: qsTr("Open GitHub")
                    onClicked: Qt.openUrlExternally(workspace.githubAuthorizationUrl)
                }
                Label {
                    text: qsTr("Complete authorization in the browser, then choose Continue.")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
        footer: DialogButtonBox {
            Button {
                text: workspace.githubAuthorizationPending ? qsTr("Continue") : qsTr("Join")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: inviteToken.text.trim() !== ""
                onClicked: {
                    var joined = workspace.githubAuthorizationPending
                        ? workspace.finishInvitationAuthorization()
                        : workspace.acceptInvitation(inviteToken.text.trim())
                    if (joined) {
                        inviteToken.clear()
                        close()
                    }
                }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: {
                    workspace.cancelInvitationAuthorization()
                    close()
                }
            }
        }
    }
}
