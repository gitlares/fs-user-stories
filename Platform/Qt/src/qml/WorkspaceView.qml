// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    Theme { id: theme }

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
            Layout.preferredWidth: 238
            Layout.minimumWidth: 210
            Layout.maximumWidth: 300
            Layout.fillHeight: true
            color: theme.sidebar

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Projects header
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        Label {
                            text: qsTr("Projects")
                            font.weight: Font.DemiBold
                            font.pixelSize: 12
                            color: theme.secondaryText
                            Layout.fillWidth: true
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // Project list — folder icon + name + progress dots on the right
                ListView {
                    id: projectList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: workspace.projects
                    clip: true
                    delegate: ItemDelegate {
                        width: ListView.view ? ListView.view.width : 0
                        height: 68
                        highlighted: modelData.id === workspace.currentProjectId
                        leftPadding: 10; rightPadding: 10; topPadding: 3; bottomPadding: 3
                        background: Rectangle {
                            radius: theme.mediumRadius
                            color: parent.highlighted ? theme.selection : "transparent"
                        }
                        contentItem: RowLayout {
                            spacing: 8
                            anchors.margins: 0
                            IconLabel {
                                text: "folder"
                                Layout.leftMargin: 12
                                Layout.rightMargin: 4
                                opacity: 0.6
                                color: theme.secondaryText
                            }
                            ColumnLayout {
                                spacing: 2
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.pixelSize: 13
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
                                    Label {
                                        visible: false
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
                                MacProgressBar {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 4
                                    value: {
                                        var total = modelData.stories ? modelData.stories.length : 0
                                        var done = 0
                                        for (var i = 0; i < total; i++)
                                            if (modelData.stories[i].status === "done") done++
                                        return total > 0 ? done / total : 0
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

                // ---- MCP Active indicator ----
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.separator }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 4
                    RowLayout {
                        spacing: 8
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            color: workspace.mcpServerActive ? theme.green : theme.tertiaryText
                        }
                        Label {
                            text: workspace.mcpServerActive ? qsTr("MCP Active") : qsTr("MCP Inactive")
                            font.pixelSize: 12; font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        MacIconButton {
                            iconName: "content_copy"; compact: true
                            enabled: workspace.mcpServerActive
                            onClicked: workspace.copyMcpServerUrl()
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: 17
                        text: workspace.mcpServerUrl
                        font.family: "monospace"
                        font.pixelSize: 10
                        opacity: 0.55
                        elide: Label.ElideLeft
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.separator }

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
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.separator }

        // ---------- MIDDLE: Stories list with Picker (Stories/Profiles) ----------
        StoryList {
            id: storyList
            Layout.preferredWidth: 460
            Layout.minimumWidth: 400
            Layout.maximumWidth: 620
            Layout.fillHeight: true
            onStorySelected: (s) => detailPane.setStory(s)
            onProfileSelected: (actor) => profilePane.setProfile(actor)
        }

        // divider
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: theme.separator }

        // ---------- RIGHT: Story detail ----------
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: storyList.showProfiles ? 1 : 0
            StoryDetailView { id: detailPane }
            ProfileDetailView { id: profilePane }
        }
    }
}
