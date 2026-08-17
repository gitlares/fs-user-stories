// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    signal storySelected(var story)

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Top section: tabs + title row ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: "transparent"
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                RowLayout {
                    spacing: 4
                    Button {
                        text: qsTr("Stories")
                        flat: true
                        font.weight: Font.DemiBold
                    }
                    Button {
                        text: qsTr("Profiles")
                        flat: true
                        opacity: 0.6
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: qsTr("Stories")
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                    Label {
                        text: workspace.currentStoryModel ? workspace.currentStoryModel.count : 0
                        opacity: 0.5
                        font.pixelSize: 16
                    }
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search stories")
                    onTextChanged: workspace.searchCurrent(text)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#e0e0e0"
        }

        // ---- Filters row ----
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 8
            ComboBox {
                id: profileFilter
                Layout.fillWidth: true
                model: workspace.currentProjectId === "" ? [] : [qsTr("All Profiles")]
                onCurrentTextChanged: workspace.searchCurrent(searchField.text, statusFilter.currentValue, currentValue)
            }
            ComboBox {
                id: statusFilter
                model: [qsTr("All"), qsTr("Active"), qsTr("Drafts"), qsTr("Completed")]
                onCurrentTextChanged: workspace.searchCurrent(searchField.text, currentValue)
            }
            ComboBox {
                id: sortBox
                model: [qsTr("Oldest First"), qsTr("Newest First")]
                onCurrentTextChanged: workspace.searchCurrent(searchField.text, statusFilter.currentValue, profileFilter.currentValue)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#e0e0e0"
        }

        // ---- Stories sectioned list ----
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: workspace.currentStoryModel
            clip: true
            spacing: 0
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0
                height: 36
                contentItem: RowLayout {
                    spacing: 8
                    anchors.margins: 0
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: {
                            if (status === "done" || status === "completed") return "#22c55e"
                            if (status === "active") return "#3b82f6"
                            return "#a3a3a3"
                        }
                        Layout.leftMargin: 16
                    }
                    Label {
                        text: title
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        elide: Label.ElideRight
                        font.pixelSize: 13
                    }
                    Label {
                        text: status
                        font.pixelSize: 10
                        opacity: 0.5
                        Layout.rightMargin: 12
                    }
                }
                highlighted: ListView.isCurrentItem
                onClicked: {
                    list.currentIndex = index
                    storySelected({
                        id:       model.storyId,
                        title:    model.title,
                        asA:      model.asA,
                        iWant:    model.iWant,
                        soThat:   model.soThat,
                        status:   model.status,
                        notes:    model.notes,
                        criteria: model.criteria
                    })
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#e0e0e0"
        }

        // ---- New story button ----
        Button {
            Layout.fillWidth: true
            Layout.margins: 8
            text: qsTr("New story…")
            flat: true
            onClicked: newStoryDialog.open()
        }

        Dialog {
            id: newStoryDialog
            title: qsTr("New story")
            modal: true
            anchors.centerIn: parent
            width: 420
            contentItem: ColumnLayout {
                spacing: 6
                TextField { id: newTitle; placeholderText: qsTr("Title"); Layout.fillWidth: true }
                TextField { id: newAsA; placeholderText: qsTr("As a"); Layout.fillWidth: true }
                TextField { id: newIWant; placeholderText: qsTr("I want"); Layout.fillWidth: true }
                TextField { id: newSoThat; placeholderText: qsTr("So that"); Layout.fillWidth: true }
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

        // Helper to wire detail panel
        function clearSelection() {
            list.currentIndex = -1
        }
    }
}
