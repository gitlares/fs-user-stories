// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------- LEFT SIDEBAR ----------
        Rectangle {
            id: sidebar
            Layout.preferredWidth: 240
            Layout.minimumWidth: 200
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            color: palette.alternateBase

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Projects header
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        Label {
                            text: qsTr("Projects")
                            font.weight: Font.Bold
                            font.pixelSize: 12
                            opacity: 0.55
                            Layout.fillWidth: true
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // Project list — folder icon + name + progress dots on the right
                ListView {
                    id: projectList
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    model: workspace.projects
                    clip: true
                    delegate: ItemDelegate {
                        width: ListView.view ? ListView.view.width : 0
                        height: 50
                        highlighted: modelData.id === workspace.currentProjectId
                        contentItem: RowLayout {
                            spacing: 8
                            anchors.margins: 0
                            IconLabel {
                                text: "folder"
                                Layout.leftMargin: 14
                                Layout.rightMargin: 4
                                opacity: 0.6
                                color: highlighted ? "#4f56d2" : palette.text
                            }
                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    elide: Label.ElideRight
                                }
                                RowLayout {
                                    spacing: 6
                                    Label {
                                        text: {
                                            var total = modelData.stories ? modelData.stories.length : 0
                                            var done = 0
                                            if (modelData.stories) {
                                                for (var i = 0; i < modelData.stories.length; i++) {
                                                    var s = modelData.stories[i].status
                                                    if (s === "completed" || s === "done") done++
                                                }
                                            }
                                            return done + "/" + total
                                        }
                                        font.pixelSize: 11; opacity: 0.5
                                        Layout.fillWidth: true
                                    }
                                    // progress dots
                                    Label {
                                        text: {
                                            var total = modelData.stories ? modelData.stories.length : 0
                                            var done = 0
                                            if (modelData.stories) {
                                                for (var i = 0; i < modelData.stories.length; i++) {
                                                    var s = modelData.stories[i].status
                                                    if (s === "completed" || s === "done") done++
                                                }
                                            }
                                            var dots = ""
                                            for (var j = 0; j < Math.min(total, 8); j++)
                                                dots += (j < done ? "●" : "○") + " "
                                            return dots
                                        }
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        opacity: 0.7
                                        Layout.rightMargin: 12
                                    }
                                }
                            }
                        }
                        onClicked: {
                            workspace.openProject(modelData.id)
                            settings.lastProjectId = modelData.id
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // ---- MCP Active indicator ----
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: palette.mid }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 4
                    RowLayout {
                        spacing: 8
                        Rectangle { width: 9; height: 9; radius: 5; color: "#22c55e" }
                        Label {
                            text: qsTr("MCP Active")
                            font.pixelSize: 13; font.weight: Font.Bold
                            Layout.fillWidth: true
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 17
                        text: "http://127.0.0.1:49231/mcp"
                        font.family: "monospace"
                        font.pixelSize: 10
                        opacity: 0.55
                        elide: Label.ElideLeft
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: palette.mid }

                // ---- Bottom action buttons (like mac) ----
                Button {
                    text: qsTr("New Project")
                    Layout.fillWidth: true
                    Layout.leftMargin: 14; Layout.rightMargin: 14
                    Layout.topMargin: 14
                    flat: true
                    contentItem: RowLayout {
                        spacing: 10
                        IconLabel { text: "add"; font.pixelSize: 18 }
                        Label {
                            text: qsTr("New Project")
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                        }
                    }
                    onClicked: welcome.openCreateProject()
                }
                Button {
                    text: qsTr("Join Shared Project")
                    Layout.fillWidth: true
                    Layout.leftMargin: 14; Layout.rightMargin: 14
                    Layout.topMargin: 6
                    Layout.bottomMargin: 14
                    flat: true
                    contentItem: RowLayout {
                        spacing: 10
                        IconLabel { text: "person_add"; font.pixelSize: 18 }
                        Label {
                            text: qsTr("Join Shared Project")
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                        }
                    }
                    onClicked: welcome.openJoinShared()
                }
            }
        }

        // divider
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: palette.mid }

        // ---------- MIDDLE: Stories list with Picker (Stories/Profiles) ----------
        StoryList {
            Layout.preferredWidth: 420
            Layout.fillHeight: true
            onStorySelected: (s) => detailPane.setStory(s)
        }

        // divider
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: palette.mid }

        // ---------- RIGHT: Story detail ----------
        StoryDetailView {
            id: detailPane
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
