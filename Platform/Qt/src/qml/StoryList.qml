// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    signal storySelected(var story)
    property bool showProfiles: false

    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 16
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Segmented picker: Stories / Profiles (matches mac segmented control) ----
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 250
                    Layout.preferredHeight: 32
                    Layout.alignment: Qt.AlignHCenter
                    radius: 16
                    color: Qt.rgba(0, 0, 0, 0.04)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 2
                        spacing: 0
                        Repeater {
                            model: [
                                { label: qsTr("Stories"),  icon: "book" },
                                { label: qsTr("Profiles"), icon: "group" }
                            ]
                            delegate: ItemDelegate {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    color: (index === 1) === root.showProfiles ? palette.base : "transparent"
                                    border.color: (index === 1) === root.showProfiles ? palette.mid : "transparent"
                                    border.width: 0.5
                                }
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    IconLabel { text: modelData.icon; font.pixelSize: 15; opacity: 0.8 }
                                    Label {
                                        text: modelData.label
                                        font.pixelSize: 13
                                        font.weight: (index === 1) === root.showProfiles ? Font.DemiBold : Font.Normal
                                    }
                                }
                                onClicked: root.showProfiles = index === 1
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Search field
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 32
                    radius: 8
                    color: Qt.rgba(0, 0, 0, 0.04)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 6
                        IconLabel { text: "search"; font.pixelSize: 15; opacity: 0.55 }
                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            background: null
                            placeholderText: qsTr("Search stories")
                            font.pixelSize: 13
                            onTextChanged: workspace.searchCurrent(text)
                        }
                    }
                }
            }
        }

        // Story count header (large)
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8
                Label {
                    text: qsTr("Stories")
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }
                Label {
                    text: workspace.currentStoryModel ? workspace.currentStoryModel.count : 0
                    font.pixelSize: 26
                    opacity: 0.4
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: palette.mid }

        // ---- Filters / sort row ----
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10; Layout.bottomMargin: 10
            Layout.leftMargin: 16; Layout.rightMargin: 16
            spacing: 8
            ComboBox {
                Layout.fillWidth: true
                model: [qsTr("All Profiles")]
                onActivated: workspace.searchCurrent(searchField.text, statusFilter.currentValue, currentValue)
            }
            ComboBox {
                id: statusFilter
                model: [qsTr("All"), qsTr("Active"), qsTr("Drafts"), qsTr("Completed")]
                onActivated: workspace.searchCurrent(searchField.text, currentValue)
            }
            ComboBox {
                model: [qsTr("Oldest First"), qsTr("Newest First")]
                onActivated: workspace.searchCurrent(searchField.text, statusFilter.currentValue)
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: palette.mid }

        // ---- Stories list ----
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: workspace.currentStoryModel
            clip: true
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0
                height: 40
                contentItem: RowLayout {
                    spacing: 8
                    anchors.margins: 0
                    Rectangle {
                        width: 9; height: 9; radius: 4
                        Layout.leftMargin: 18
                        color: {
                            if (status === "done" || status === "completed") return "#22c55e"
                            if (status === "active") return "#3b82f6"
                            return "#a3a3a3"
                        }
                    }
                    Label {
                        text: title
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        elide: Label.ElideRight
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Label {
                        text: status
                        font.pixelSize: 11
                        opacity: 0.5
                        Layout.rightMargin: 12
                    }
                }
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
                        criteria: model.criteria,
                        actorId: model.profileId,
                        attachments: model.attachments,
                        number: model.number
                    })
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: palette.mid }

        Button {
            Layout.fillWidth: true
            Layout.margins: 8
            text: qsTr("New story…")
            flat: true
            onClicked: /* opened from toolbar in main */ { }
        }

        function clearSelection() { list.currentIndex = -1 }
    }

    ProjectProfilesView {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 58
        visible: root.showProfiles
        z: 10
    }
}
