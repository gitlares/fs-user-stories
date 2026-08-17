// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.preferredWidth: 320
            Layout.fillHeight: true
            color: palette.window

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Label {
                        text: qsTr("Projects")
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Button {
                        text: qsTr("Sync")
                        onClicked: workspace.synchronize()
                    }
                }

                ListView {
                    id: projectList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: workspace.projects
                    delegate: ItemDelegate {
                        width: ListView.view ? ListView.view.width : 0
                        text: modelData.name
                        highlighted: modelData.id === workspace.currentProjectId
                        onClicked: {
                            workspace.openProject(modelData.id)
                            settings.lastProjectId = modelData.id
                        }
                    }
                }

                Button {
                    text: qsTr("Back to welcome")
                    Layout.fillWidth: true
                    onClicked: workspace.openProject("")
                }
            }
        }

        StoryList {
            Layout.fillHeight: true
            Layout.preferredWidth: 360
        }

        StoryDetailView {
            Layout.fillHeight: true
            Layout.fillWidth: true
        }
    }
}
