// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    // Fields filled in by StoryList when an item is tapped.
    property string storyId: ""
    property string storyTitle: ""
    property string storyAsA: ""
    property string storyIWant: ""
    property string storySoThat: ""
    property string storyStatus: ""
    property string storyNotes: ""
    property var    storyCriteria: []

    readonly property bool readOnly: storyStatus === "done" || storyStatus === "completed"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ---- Header: NUB-1 + Done badge + Edit Story + ⋯ ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: storyId !== ""

            Label {
                text: storyId.substr(0, 8)
                font.pixelSize: 14
                font.weight: Font.DemiBold
                opacity: 0.5
                Layout.fillWidth: true
            }

            // Status badge
            Rectangle {
                radius: 10
                color: {
                    if (storyStatus === "done" || storyStatus === "completed") return "#dcfce7"
                    if (storyStatus === "active") return "#dbeafe"
                    if (storyStatus === "") return "#f3f4f6"
                    return "#f3f4f6"
                }
                Layout.preferredHeight: 22
                Layout.preferredWidth: badgeText.implicitWidth + 18
                Label {
                    id: badgeText
                    anchors.centerIn: parent
                    text: {
                        if (storyStatus === "") return ""
                        return storyStatus.charAt(0).toUpperCase() + storyStatus.slice(1)
                    }
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: {
                        if (storyStatus === "done" || storyStatus === "completed") return "#15803d"
                        if (storyStatus === "active") return "#1d4ed8"
                        return "#525252"
                    }
                }
            }
            Item { Layout.fillWidth: true }
            Button {
                text: root.readOnly ? qsTr("🔒  Read-only") : qsTr("✎  Edit Story")
                flat: true
                enabled: !root.readOnly
            }
            ToolButton {
                text: "⋯"
                font.pixelSize: 16
                Menu {
                    id: storyMenu
                    MenuItem {
                        text: qsTr("Delete this story")
                        onTriggered: {
                            workspace.deleteStory(storyId)
                            root.clear()
                        }
                    }
                }
            }
        }

        // ---- Title ----
        Label {
            visible: storyId !== ""
            text: storyTitle
            font.pixelSize: 22
            font.weight: Font.Bold
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- Read-only notice (for done stories) ----
        Rectangle {
            visible: storyId !== "" && root.readOnly
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 6
            color: "#f3f4f6"
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Label { text: "🔒"; font.pixelSize: 14 }
                Label {
                    text: qsTr("Completed stories are read-only. Change status to Active or Draft to edit.")
                    font.pixelSize: 11
                    opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ---- "No story selected" placeholder ----
        ColumnLayout {
            visible: storyId === ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            Label {
                text: qsTr("Select a story to view its details.")
                opacity: 0.5
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 64
            }
        }

        // ---- Editable fields ----
        ColumnLayout {
            visible: storyId !== ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            enabled: !root.readOnly
            spacing: 4

            Label {
                text: qsTr("As a")
                font.weight: Font.DemiBold
                font.pixelSize: 11
                opacity: 0.55
            }
            TextField {
                Layout.fillWidth: true
                text: storyAsA
                placeholderText: qsTr("As a …")
            }

            Label {
                text: qsTr("I want")
                font.weight: Font.DemiBold
                font.pixelSize: 11
                opacity: 0.55
                Layout.topMargin: 6
            }
            TextField {
                Layout.fillWidth: true
                text: storyIWant
                placeholderText: qsTr("I want …")
            }

            Label {
                text: qsTr("So that")
                font.weight: Font.DemiBold
                font.pixelSize: 11
                opacity: 0.55
                Layout.topMargin: 6
            }
            TextField {
                Layout.fillWidth: true
                text: storySoThat
                placeholderText: qsTr("So that …")
            }

            // ---- Acceptance Criteria ----
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Label {
                    text: qsTr("Acceptance Criteria")
                    font.weight: Font.Bold
                    font.pixelSize: 12
                    Layout.fillWidth: true
                }
                ToolButton {
                    text: "+"
                    font.pixelSize: 16
                    ToolTip.text: qsTr("Add criterion")
                    ToolTip.visible: hovered
                    ToolTip.delay: 400
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4
                clip: true
                model: storyCriteria
                delegate: ItemDelegate {
                    width: ListView.view ? ListView.view.width : 0
                    height: 36
                    contentItem: RowLayout {
                        spacing: 8
                        anchors.margins: 0
                        Rectangle {
                            width: 18; height: 18; radius: 9
                            color: modelData.isMet ? "#22c55e" : "#d4d4d8"
                            Label {
                                anchors.centerIn: parent
                                text: modelData.isMet ? "✓" : ""
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.text
                            wrapMode: Text.WordWrap
                            font.pixelSize: 12
                            opacity: modelData.isMet ? 0.55 : 1
                        }
                    }
                }
            }
        }
    }

    function setStory(s) {
        storyId      = s.id        || ""
        storyTitle   = s.title     || ""
        storyAsA     = s.asA       || ""
        storyIWant   = s.iWant     || ""
        storySoThat  = s.soThat    || ""
        storyStatus  = s.status    || ""
        storyNotes   = s.notes     || ""
        storyCriteria = s.criteria || []
    }

    function clear() {
        storyId = ""
        storyTitle = ""
        storyAsA = ""
        storyIWant = ""
        storySoThat = ""
        storyStatus = ""
        storyNotes = ""
        storyCriteria = []
    }
}
