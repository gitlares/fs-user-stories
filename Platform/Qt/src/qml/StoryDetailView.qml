// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
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
    property string storyActorId: ""
    property var storyAttachments: []
    property bool editMode: false

    readonly property bool readOnly: storyStatus === "done" || storyStatus === "completed"

    Connections {
        target: workspace
        function onCurrentProjectChanged() { root.reloadStory() }
    }

    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 14
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    component BigIconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 18
        font.weight: Font.DemiBold
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
                radius: 12
                color: {
                    if (storyStatus === "done" || storyStatus === "completed") return "#dcfce7"
                    if (storyStatus === "active") return "#dbeafe"
                    return "#f3f4f6"
                }
                Layout.preferredHeight: 24
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
                        font.pixelSize: 14
                        color: storyStatus === "done" || storyStatus === "completed" ? "#15803d"
                              : storyStatus === "active" ? "#1d4ed8"
                              : "#525252"
                    }
                    Label {
                        id: badgeText
                        text: storyStatus.charAt(0).toUpperCase() + storyStatus.slice(1)
                        font.pixelSize: 12
                        font.weight: Font.Bold
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
                id: editStoryButton
                text: root.readOnly ? qsTr("Read-only") : (root.editMode ? qsTr("Save Changes") : qsTr("Edit Story"))
                flat: true
                contentItem: RowLayout {
                    spacing: 6
                    BigIconLabel { text: root.readOnly ? "lock" : "edit" }
                    Label { text: editStoryButton.text }
                }
                enabled: !root.readOnly
                onClicked: {
                    if (!root.editMode) { root.editMode = true; return }
                    var actorId = workspace.currentActors[actorField.currentIndex].id
                    workspace.updateStory(storyId, titleField.text.trim(), actorId,
                                          wantField.text.trim(), outcomeField.text.trim(),
                                          storyCriteria)
                    if (workspace.lastError === "") {
                        storyTitle = titleField.text; storyActorId = actorId
                        storyAsA = workspace.currentActors[actorField.currentIndex].name; storyIWant = wantField.text
                        storySoThat = outcomeField.text; root.editMode = false
                    }
                }
            }

            ComboBox {
                visible: storyId !== ""
                model: ["draft", "active", "done"]
                currentIndex: Math.max(0, model.indexOf(storyStatus))
                onActivated: workspace.setStoryStatus(storyId, currentValue)
            }

            ToolButton {
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
        TextField {
            id: titleField
            visible: storyId !== ""
            text: storyTitle
            readOnly: !root.editMode
            font.pixelSize: 32
            font.weight: Font.Bold
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
            enabled: root.editMode && !root.readOnly
            spacing: 10

            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("As a"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                ComboBox {
                    id: actorField
                    Layout.fillWidth: true
                    model: workspace.currentActors
                    textRole: "name"
                    currentIndex: root.actorIndexForId(root.storyActorId)
                }
            }
            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("I want"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                TextField { id: wantField; Layout.fillWidth: true; text: storyIWant; placeholderText: qsTr("I want …"); font.pixelSize: 13 }
            }
            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("So that"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                TextField { id: outcomeField; Layout.fillWidth: true; text: storySoThat; placeholderText: qsTr("So that …"); font.pixelSize: 13 }
            }

            // Notes
            ColumnLayout {
                spacing: 4; Layout.fillWidth: true
                Label { text: qsTr("Notes"); font.weight: Font.DemiBold; opacity: 0.55; font.pixelSize: 11 }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    TextArea {
                        id: notesField
                        text: storyNotes
                        wrapMode: TextArea.Wrap
                        font.pixelSize: 12
                    }
                }
                Button {
                    text: qsTr("Save Notes")
                    enabled: notesField.text !== storyNotes
                    onClicked: {
                        workspace.updateStoryNotes(storyId, notesField.text)
                        if (workspace.lastError === "") storyNotes = notesField.text
                    }
                }
            }
        }

        // ---- Managed attachments ----
        RowLayout {
            Layout.fillWidth: true
            visible: storyId !== ""
            Label {
                text: qsTr("Attachments")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            ToolButton {
                contentItem: BigIconLabel { text: "attach_file" }
                enabled: !root.readOnly
                ToolTip.text: qsTr("Add attachments (maximum 10 MB each)")
                ToolTip.visible: hovered
                onClicked: attachmentDialog.open()
            }
        }
        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 120)
            visible: storyId !== "" && storyAttachments.length > 0
            model: storyAttachments
            clip: true
            delegate: ItemDelegate {
                width: ListView.view ? ListView.view.width : 0
                contentItem: RowLayout {
                    IconLabel { text: "description" }
                    Label { text: modelData.filename; Layout.fillWidth: true; elide: Text.ElideMiddle }
                    Label { text: Math.max(1, Math.round(modelData.byteSize / 1024)) + " KB"; opacity: 0.55 }
                    ToolButton {
                        text: "×"
                        enabled: !root.readOnly
                        onClicked: workspace.removeAttachment(storyId, modelData.id)
                    }
                }
                onClicked: workspace.openAttachment(modelData.relativePath)
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
                contentItem: BigIconLabel { text: "add" }
                ToolTip.text: qsTr("Add criterion")
                ToolTip.visible: hovered
                ToolTip.delay: 400
                enabled: !root.readOnly
                onClicked: addCriterionDialog.open()
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
                    ToolButton {
                        text: "×"
                        enabled: !root.readOnly
                        onClicked: workspace.deleteAcceptanceCriterion(storyId, modelData.id)
                    }
                }
                onClicked: if (!root.readOnly) workspace.toggleAcceptanceCriterion(storyId, modelData.id)
            }
        }
    }

    Dialog {
        id: addCriterionDialog
        title: qsTr("Add Acceptance Criterion")
        anchors.centerIn: parent
        modal: true
        width: 420
        contentItem: TextField { id: newCriterionText; placeholderText: qsTr("Expected result") }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Add"); enabled: newCriterionText.text.trim() !== ""
                onClicked: {
                    workspace.addAcceptanceCriterion(storyId, newCriterionText.text.trim())
                    if (workspace.lastError === "") { newCriterionText.clear(); addCriterionDialog.close() }
                }
            }
            Button { text: qsTr("Cancel"); onClicked: addCriterionDialog.close() }
        }
    }

    FileDialog {
        id: attachmentDialog
        title: qsTr("Add Attachments")
        fileMode: FileDialog.OpenFiles
        onAccepted: workspace.importAttachments(storyId, selectedFiles)
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
        storyActorId = s.actorId || ""
        storyAttachments = s.attachments || []
        editMode = false
    }
    function clear() {
        storyId = ""; storyTitle = ""; storyAsA = ""
        storyIWant = ""; storySoThat = ""; storyStatus = ""
        storyNotes = ""; storyCriteria = []
        storyActorId = ""; storyAttachments = []; editMode = false
    }

    function actorIdForName(name) {
        for (var i = 0; i < workspace.currentActors.length; i++)
            if (workspace.currentActors[i].name.toLowerCase() === name.trim().toLowerCase())
                return workspace.currentActors[i].id
        return storyActorId
    }

    function actorIndexForId(actorId) {
        for (var i = 0; i < workspace.currentActors.length; i++)
            if (workspace.currentActors[i].id === actorId) return i
        return 0
    }

    function reloadStory() {
        if (storyId === "") return
        var stories = workspace.currentProject.stories || []
        for (var i = 0; i < stories.length; i++) {
            if (stories[i].id !== storyId) continue
            var actorName = ""
            for (var j = 0; j < workspace.currentActors.length; j++)
                if (workspace.currentActors[j].id === stories[i].actorId) actorName = workspace.currentActors[j].name
            setStory({ id: stories[i].id, title: stories[i].title, asA: actorName,
                       actorId: stories[i].actorId, iWant: stories[i].want,
                       soThat: stories[i].outcome, status: stories[i].status,
                       notes: stories[i].notes, criteria: stories[i].acceptanceCriteria,
                       attachments: stories[i].attachments })
            return
        }
        clear()
    }
}
