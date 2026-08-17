// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        TextField {
            id: searchField
            placeholderText: qsTr("Search stories")
            onTextChanged: workspace.searchCurrent(text)
        }

        ComboBox {
            id: statusFilter
            model: [qsTr("All"), "draft", "active", "completed"]
            onCurrentTextChanged: workspace.searchCurrent(searchField.text, currentValue)
        }

        ComboBox {
            id: profileFilter
            model: workspace.currentProjectId === "" ? [] : [qsTr("All profiles")]
            onCurrentTextChanged: workspace.searchCurrent(searchField.text, statusFilter.currentValue, currentValue)
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: workspace.currentStoryModel
            clip: true
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0
                text: title + "  ·  " + status
                onClicked: {
                    detailView.storyId = storyId
                    detailView.storyTitle = title
                    detailView.storyAsA = asA
                    detailView.storyIWant = iWant
                    detailView.storySoThat = soThat
                    detailView.storyStatus = status
                    detailView.storyNotes = notes
                }
            }
        }

        Button {
            text: qsTr("New story…")
            Layout.fillWidth: true
            onClicked: newStoryDialog.open()
        }
    }

    Dialog {
        id: newStoryDialog
        title: qsTr("New story")
        anchors.centerIn: parent
        modal: true
        width: 480
        contentItem: ColumnLayout {
            spacing: 6
            TextField { id: newTitle; placeholderText: qsTr("Title") }
            TextField { id: newAsA; placeholderText: qsTr("As a") }
            TextField { id: newIWant; placeholderText: qsTr("I want") }
            TextField { id: newSoThat; placeholderText: qsTr("So that") }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Create")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: newTitle.text.trim() !== ""
                onClicked: {
                    workspace.createStory(newTitle.text.trim(),
                                          newAsA.text.trim(),
                                          newIWant.text.trim(),
                                          newSoThat.text.trim())
                    newStoryDialog.close()
                }
            }
            Button {
                text: qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: newStoryDialog.close()
            }
        }
    }
}
