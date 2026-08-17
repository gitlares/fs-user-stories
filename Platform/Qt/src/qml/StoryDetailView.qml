// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string storyId: ""
    property string storyTitle: ""
    property string storyAsA: ""
    property string storyIWant: ""
    property string storySoThat: ""
    property string storyStatus: ""
    property string storyNotes: ""
    property var    storyCriteria: []

    readonly property bool readOnly: storyStatus === "done" || storyStatus === "completed"

    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 14
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    component BigIconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        // ---- Header row: STATUS BADGE + ID + ⋯ (matches mac NUB-1 | Done) ----
        RowLayout {
            Layout.fillWidth: true
            visible: storyId !== ""
            spacing: 8

            // Status badge pill
            Rectangle {
                radius: 10
                color: {
                    if (storyStatus === "done" || storyStatus === "completed") return "#dcfce7"
                    if (storyStatus === "active") return "#dbeafe"
                    return "#f3f4f6"
                }
                Layout.preferredHeight: 22
                Layout.preferredWidth: badgeText.implicitWidth + 28
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    BigIconLabel {
                        text: storyStatus === "done" || storyStatus === "completed"
                              ? "check_circle"
                              : storyStatus === "active"
                                ? "play_circle"
                                : "edit_note"
                        color: storyStatus === "done" || storyStatus === "completed" ? "#15803d"
                              : storyStatus === "active" ? "#1d4ed8"
                              : "#525252"
                    }
                    Label {
                        id: badgeText
                        text: storyStatus.charAt(0).toUpperCase() + storyStatus.slice(1)
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: storyStatus === "done" || storyStatus === "completed" ? "#15803d"
                              : storyStatus === "active" ? "#1d4ed8"
                              : "#525252"
                    }
                }
            }

            // "NUB-1" reference (we use the project prefix + first 8 of story id)
            Label {
                text: {
                    var prefix = ""
                    for (var i = 0; i < workspace.projects.length; i++) {
                        if (workspace.projects[i].id === workspace.currentProjectId) {
                            prefix = workspace.projects[i].prefix
                            break
                        }
                    }
                    return prefix + "-" + storyId.substr(0, 8)
                }
                font.pixelSize: 11
                opacity: 0.5
            }

            Item { Layout.fillWidth: true }

            Button {
                text: root.readOnly ? qsTr("Read-only") : qsTr("Edit Story")
                flat: true
                iconLabel: true
                contentItem: RowLayout {
                    spacing: 6
                    BigIconLabel { text: root.readOnly ? "lock" : "edit" }
                    Label { text: root.readOnly ? qsTr("Read-only") : qsTr("Edit Story") }
                }
                enabled: !root.readOnly
            }

            ToolButton {
                iconLabel: true
                contentItem: BigIconLabel { text: "more_horiz" }
                onClicked: storyMenu.open()
                Menu {
                    id: storyMenu
                    MenuItem {
                        text: qsTr("Delete this story")
                        onTriggered: { workspace.deleteStory(storyId); root.clear() }
                    }
                }
            }
        }

        // ---- Title (big, bold) ----
        Label {
            visible: storyId !== ""
            text: storyTitle
            font.pixelSize: 28
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ---- Read-only notice ----
        Rectangle {
            visible: storyId !== "" && root.readOnly
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 6
            color: "#f3f4f6"
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                BigIconLabel { text: "lock"; opacity: 0.6 }
                Label {
                    text: qsTr("Completed stories are read-only. Change status to Active or Draft to edit.")
                    font.pixelSize: 12; opacity: 0.7
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ---- "Select a story" placeholder ----
        ColumnLayout {
            visible: storyId === ""
            Layout.fillWidth: true
            Layout.fillHeight: true
            Label {
                text: qsTr("Select a story from the list to view its details.")
                opacity: 0.5
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 80
                font.pixelSize: 13
            }
        }

        // ---- Editable fields ----
        ColumnLayout {
            visible: storyId !== ""
            Layout.fillWidth: true
            enabled: !root.readOnly
            spacing: 10

            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("As a"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                TextField { Layout.fillWidth: true; text: storyAsA; placeholderText: qsTr("As a …"); font.pixelSize: 13 }
            }
            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("I want"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                TextField { Layout.fillWidth: true; text: storyIWant; placeholderText: qsTr("I want …"); font.pixelSize: 13 }
            }
            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("So that"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                TextField { Layout.fillWidth: true; text: storySoThat; placeholderText: qsTr("So that …"); font.pixelSize: 13 }
            }

            // Notes
            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("Notes"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    TextArea {
                        text: storyNotes
                        wrapMode: TextArea.Wrap
                        font.pixelSize: 12
                        onEditingFinished: {}  // TODO: save notes
                    }
                }
            }
        }

        // ---- Acceptance Criteria section ----
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: storyId !== ""
            Label {
                text: qsTr("Acceptance Criteria")
                font.pixelSize: 13; font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            ToolButton {
                iconLabel: true
                contentItem: BigIconLabel { text: "add" }
                ToolTip.text: qsTr("Add criterion")
                ToolTip.visible: hovered
                ToolTip.delay: 400
            }
        }
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: storyId !== ""
            model: storyCriteria
            clip: true
            spacing: 6
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0
                height: 38
                contentItem: RowLayout {
                    spacing: 10
                    anchors.margins: 0
                    Rectangle {
                        width: 18; height: 18; radius: 9
                        color: modelData.isMet ? "#22c55e" : "#d4d4d8"
                        Layout.leftMargin: 4
                        BigIconLabel { anchors.centerIn: parent; text: modelData.isMet ? "check" : ""; color: "white"; font.pixelSize: 11 }
                    }
                    Label {
                        text: modelData.text
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                        opacity: modelData.isMet ? 0.6 : 1
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
        storyId = ""; storyTitle = ""; storyAsA = ""
        storyIWant = ""; storySoThat = ""; storyStatus = ""
        storyNotes = ""; storyCriteria = []
    }
}
