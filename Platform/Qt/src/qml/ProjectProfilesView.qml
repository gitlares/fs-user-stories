// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var selectedActor: ({})

    Rectangle { anchors.fill: parent; color: palette.window; z: -1 }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true; Layout.margins: 16
            Label { text: qsTr("Profiles"); font.pixelSize: 26; font.weight: Font.Bold; Layout.fillWidth: true }
            Button { text: qsTr("Add Profile"); onClicked: addDialog.open() }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: palette.mid }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            model: workspace.currentActors; clip: true
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0; height: 62
                contentItem: RowLayout {
                    spacing: 12
                    Label { text: "●"; color: "#0a84ff"; Layout.leftMargin: 12 }
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
                    editName.text = modelData.name; editRole.text = modelData.role
                    editDialog.open()
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
