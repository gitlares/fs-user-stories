// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    function openCreateProject() {
        createDialog.open()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 18
        width: 480

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
            opacity: 0.75
        }

        ListView {
            id: projectList
            Layout.fillWidth: true
            Layout.preferredHeight: 240
            model: workspace.projects
            clip: true
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0
                text: modelData.name + "  ·  " + modelData.prefix
                onClicked: {
                    workspace.openProject(modelData.id)
                    settings.lastProjectId = modelData.id
                }
            }
            Label {
                anchors.centerIn: parent
                visible: projectList.count === 0
                text: qsTr("No projects yet. Create one to get started.")
                opacity: 0.6
            }
        }

        Button {
            text: qsTr("New project…")
            Layout.alignment: Qt.AlignHCenter
            onClicked: root.openCreateProject()
        }
    }

    Dialog {
        id: createDialog
        title: qsTr("Create a new project")
        modal: true
        anchors.centerIn: parent
        width: 360
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: qsTr("Name") }
            TextField { id: newName; placeholderText: qsTr("My project") }
            Label { text: qsTr("Prefix") }
            TextField { id: newPrefix; placeholderText: "ABC" }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Create")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: newName.text.trim() !== "" && newPrefix.text.trim() !== ""
                onClicked: {
                    workspace.createProject(newName.text.trim(), newPrefix.text.trim())
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
}
