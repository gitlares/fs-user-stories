// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    signal actorSelected(var actor)
    property var selectedActor: ({})
    Theme { id: theme }

    Rectangle { anchors.fill: parent; color: theme.window; z: -1 }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 16
            Label { text: qsTr("Profiles"); font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true }
            MacButton { text: qsTr("Add Profile"); iconName: "person_add"; onClicked: addDialog.open() }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.separator }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            model: workspace.currentActors; clip: true
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0; height: 70
                leftPadding: 12; rightPadding: 12; topPadding: 4; bottomPadding: 4
                background: Rectangle {
                    radius: theme.mediumRadius
                    color: modelData.id === root.selectedActor.id ? theme.selection
                         : parent.hovered ? theme.control : "transparent"
                }
                contentItem: RowLayout {
                    spacing: 12
                    Rectangle {
                        width: 34; height: 34; radius: 17; color: Qt.rgba(0.04, 0.52, 1, 0.12)
                        Label { anchors.centerIn: parent; text: modelData.name.charAt(0).toUpperCase(); color: theme.accent; font.weight: Font.Bold }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        Label { text: modelData.name; font.weight: Font.DemiBold }
                        Label { text: modelData.role || qsTr("No description"); opacity: 0.6; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                    Label {
                        opacity: 0.55
                        text: {
                            var count = 0
                            var stories = workspace.currentProject.stories || []
                            for (var i = 0; i < stories.length; i++) if (stories[i].actorId === modelData.id) count++
                            return qsTr("%1 stories").arg(count)
                        }
                    }
                }
                onClicked: {
                    root.selectedActor = modelData
                    root.actorSelected(modelData)
                }
            }
        }
    }

    Dialog {
        id: addDialog; title: qsTr("Add Profile"); anchors.centerIn: parent; modal: true; width: 420
        contentItem: ColumnLayout {
            Label { text: qsTr("Profile name") }
            TextField { id: addName; Layout.fillWidth: true }
            Label { text: qsTr("Short description") }
            TextArea { id: addRole; Layout.fillWidth: true; Layout.preferredHeight: 90; wrapMode: TextArea.Wrap }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Add Profile"); enabled: addName.text.trim() !== ""
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: {
                    workspace.addActor(addName.text.trim(), addRole.text.trim())
                    if (workspace.lastError === "") { addName.clear(); addRole.clear(); addDialog.close() }
                }
            }
            Button { text: qsTr("Cancel"); onClicked: addDialog.close() }
        }
    }

    Dialog {
        id: editDialog; title: qsTr("Edit Profile"); anchors.centerIn: parent; modal: true; width: 420
        contentItem: ColumnLayout {
            Label { text: qsTr("Profile name") }
            TextField { id: editName; Layout.fillWidth: true }
            Label { text: qsTr("Short description") }
            TextArea { id: editRole; Layout.fillWidth: true; Layout.preferredHeight: 90; wrapMode: TextArea.Wrap }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Delete"); DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                onClicked: { workspace.deleteActor(root.selectedActor.id); if (workspace.lastError === "") editDialog.close() }
            }
            Button {
                text: qsTr("Save"); enabled: editName.text.trim() !== ""
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: {
                    workspace.updateActor(root.selectedActor.id, editName.text.trim(), editRole.text.trim())
                    if (workspace.lastError === "") editDialog.close()
                }
            }
            Button { text: qsTr("Cancel"); onClicked: editDialog.close() }
        }
    }
}
