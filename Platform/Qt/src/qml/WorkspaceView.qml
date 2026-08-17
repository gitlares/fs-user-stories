// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Helper for progress dots: "1/5"
    function progressText(prefix, projectId) {
        var p = null
        for (var i = 0; i < workspace.projects.length; i++) {
            if (workspace.projects[i].id === projectId) p = workspace.projects[i]
        }
        if (!p) return ""
        var total = 0, done = 0
        // storyModel exposes currentProjectId via QML binding
        if (storyModel && storyModel.storyCount !== undefined) total = storyModel.storyCount
        if (storyModel && storyModel.doneCount !== undefined) done = storyModel.doneCount
        return done + "/" + total
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------- LEFT SIDEBAR ----------
        Rectangle {
            id: sidebar
            Layout.preferredWidth: 240
            Layout.fillHeight: true
            color: "#fafafa"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 0
                spacing: 0

                // Projects header
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        Label {
                            text: qsTr("Projects")
                            font.weight: Font.DemiBold
                            font.pixelSize: 13
                            opacity: 0.6
                            Layout.fillWidth: true
                        }
                    }
                }

                // Project list
                ListView {
                    id: projectList
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    model: workspace.projects
                    clip: true
                    spacing: 0
                    delegate: ItemDelegate {
                        width: ListView.view ? ListView.view.width : 0
                        height: 52
                        highlighted: modelData.id === workspace.currentProjectId
                        contentItem: ColumnLayout {
                            spacing: 2
                            anchors.margins: 0
                            Label {
                                Layout.fillWidth: true
                                Layout.leftMargin: 16
                                Layout.rightMargin: 12
                                Layout.topMargin: 8
                                text: modelData.name
                                font.pixelSize: 13
                                font.weight: modelData.id === workspace.currentProjectId ? Font.DemiBold : Font.Normal
                                elide: Label.ElideRight
                            }
                            RowLayout {
                                spacing: 8
                                Layout.leftMargin: 16
                                Layout.topMargin: 0
                                Label {
                                    text: {
                                        var total = modelData.stories ? modelData.stories.length : 0
                                        var done = 0
                                        if (modelData.stories) {
                                            for (var i = 0; i < modelData.stories.length; i++) {
                                                if (modelData.stories[i].status === "completed" ||
                                                    modelData.stories[i].status === "done") done++
                                            }
                                        }
                                        return done + "/" + total
                                    }
                                    font.pixelSize: 11
                                    opacity: 0.5
                                    Layout.fillWidth: true
                                }
                                // Progress dots: ● ● ● ○ ○
                                Label {
                                    text: {
                                        var total = modelData.stories ? modelData.stories.length : 0
                                        var done = 0
                                        if (modelData.stories) {
                                            for (var i = 0; i < modelData.stories.length; i++) {
                                                if (modelData.stories[i].status === "completed" ||
                                                    modelData.stories[i].status === "done") done++
                                            }
                                        }
                                        var dots = ""
                                        for (var j = 0; j < Math.min(total, 8); j++) dots += (j < done ? "●" : "○") + " "
                                        return dots
                                    }
                                    font.pixelSize: 10
                                    opacity: 0.6
                                    Layout.rightMargin: 12
                                }
                            }
                        }
                        onClicked: {
                            workspace.openProject(modelData.id)
                            settings.lastProjectId = modelData.id
                        }
                    }
                }

                Item { Layout.fillHeight: true }   // spacer

                // MCP Active indicator (bottom of sidebar)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#e0e0e0"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: "#22c55e"
                    }
                    Label {
                        text: qsTr("MCP Active")
                        font.weight: Font.DemiBold
                        font.pixelSize: 12
                        Layout.fillWidth: true
                    }
                }
                Label {
                    Layout.fillWidth: true
                    Layout.leftMargin: 22
                    Layout.bottomMargin: 4
                    text: "http://127.0.0.1:49231/mcp"
                    font.family: "monospace"
                    font.pixelSize: 10
                    opacity: 0.5
                    elide: Label.ElideLeft
                }

                // New Project / Join Shared buttons
                Button {
                    text: qsTr("+  New Project")
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 4
                    flat: true
                    onClicked: welcome.openCreateProject()
                }
                Button {
                    text: qsTr("👥  Join Shared Project")
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 12
                    flat: true
                    onClicked: welcome.openJoinShared()
                }
            }
        }

        // vertical divider
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: "#e0e0e0"
        }

        // ---------- MIDDLE: Stories list ----------
        StoryList {
            id: storyList
            Layout.preferredWidth: 360
            Layout.fillHeight: true
            onStorySelected: (story) => detailPane.setStory(story)
        }

        // vertical divider
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: "#e0e0e0"
        }

        // ---------- RIGHT: Story detail ----------
        StoryDetailView {
            id: detailPane
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
