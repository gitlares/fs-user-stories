// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

Item {
    id: root
    property string storyId: ""
    property int storyNumber: 0
    property string storyTitle: ""
    property string storyAsA: ""
    property string storyIWant: ""
    property string storySoThat: ""
    property string storyStatus: ""
    property string storyNotes: ""
    property var storyCriteria: []
    property string storyActorId: ""
    property var storyAttachments: []
    property bool editMode: false
    property bool notesExpanded: false
    readonly property bool readOnly: storyStatus === "done"
    readonly property int metCriteriaCount: countMetCriteria()
    readonly property real completion: storyCriteria.length > 0 ? metCriteriaCount / storyCriteria.length : 0
    Theme { id: theme }

    Connections {
        target: workspace
        function onCurrentProjectChanged() { root.reloadStory() }
    }

    component IconLabel: Label {
        font.family: appIconFont; font.pixelSize: 17; font.weight: Font.DemiBold
        color: theme.secondaryText
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }
    component StatementRow: RowLayout {
        required property string label
        required property string value
        spacing: 22; Layout.fillWidth: true
        Label {
            text: parent.label; color: theme.secondaryText; font.pixelSize: 12
            font.weight: Font.DemiBold; Layout.preferredWidth: 82
        }
        Label {
            text: parent.value; color: theme.text; font.pixelSize: 14
            Layout.fillWidth: true; wrapMode: Text.WordWrap
        }
    }

    Rectangle { anchors.fill: parent; color: theme.window }

    ColumnLayout {
        anchors.centerIn: parent
        visible: storyId === ""
        spacing: 8
        IconLabel { text: "description"; font.pixelSize: 42; opacity: 0.35; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("Select a Story"); font.pixelSize: 18; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("Choose a story to see its details."); color: theme.secondaryText; Layout.alignment: Qt.AlignHCenter }
    }

    ScrollView {
        anchors.fill: parent
        visible: storyId !== ""
        clip: true
        contentWidth: Math.max(480, availableWidth)
        contentHeight: storyContent.implicitHeight + 68
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            id: storyContent
            width: Math.min(720, Math.max(480, root.width - 72))
            x: Math.max(36, (root.width - width) / 2)
            y: 34; spacing: 26

            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Label {
                        text: workspace.currentProject.prefix + "-" + storyNumber
                        font.family: "monospace"; font.pixelSize: 12; font.weight: Font.DemiBold
                        color: theme.secondaryText
                    }
                    MacComboBox {
                        id: statusCombo
                        model: [qsTr("Draft"), qsTr("Active"), qsTr("Done")]
                        currentIndex: storyStatus === "active" ? 1 : storyStatus === "done" ? 2 : 0
                        implicitHeight: 28; implicitWidth: 92
                        onActivated: workspace.setStoryStatus(storyId, ["draft", "active", "done"][currentIndex])
                    }
                    Item { Layout.fillWidth: true }
                    MacButton {
                        text: root.editMode ? qsTr("Save Changes") : qsTr("Edit Story")
                        iconName: "edit"; enabled: !root.readOnly
                        onClicked: {
                            if (!root.editMode) { root.editMode = true; return }
                            var actorId = workspace.currentActors[actorEditor.currentIndex].id
                            workspace.updateStory(storyId, titleEditor.text.trim(), actorId,
                                                  wantEditor.text.trim(), outcomeEditor.text.trim(), storyCriteria)
                            if (workspace.lastError === "") root.editMode = false
                        }
                    }
                    MacIconButton {
                        iconName: "more_horiz"; circular: true
                        onClicked: storyMenu.open()
                        Menu {
                            id: storyMenu
                            MenuItem {
                                text: qsTr("Duplicate Story")
                                onTriggered: workspace.duplicateStory(storyId, storyTitle + qsTr(" Copy"))
                            }
                            MenuSeparator {}
                            MenuItem { text: qsTr("Delete Story"); onTriggered: deleteStoryDialog.open() }
                        }
                    }
                }
                Label {
                    visible: !root.editMode
                    text: storyTitle; font.pixelSize: 30; font.weight: Font.DemiBold
                    color: theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap
                }
                MacTextField {
                    id: titleEditor; visible: root.editMode; text: storyTitle
                    font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true
                }
                RowLayout {
                    visible: root.readOnly; spacing: 8; Layout.fillWidth: true
                    IconLabel { text: "lock"; font.pixelSize: 14 }
                    Label {
                        text: qsTr("Completed stories are read-only. Change status to Active or Draft to edit.")
                        color: theme.secondaryText; font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statementContent.implicitHeight + 44
                radius: theme.cardRadius; color: theme.panel
                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.035)
                ColumnLayout {
                    id: statementContent
                    anchors.fill: parent; anchors.margins: 22; spacing: 18
                    StatementRow { visible: !root.editMode; label: qsTr("As"); value: storyAsA }
                    StatementRow { visible: !root.editMode; label: qsTr("I want"); value: storyIWant }
                    StatementRow { visible: !root.editMode; label: qsTr("So that"); value: storySoThat }
                    RowLayout {
                        visible: root.editMode; Layout.fillWidth: true
                        Label { text: qsTr("As"); color: theme.secondaryText; Layout.preferredWidth: 82 }
                        MacComboBox {
                            id: actorEditor; Layout.fillWidth: true; model: workspace.currentActors; textRole: "name"
                            currentIndex: root.actorIndexForId(root.storyActorId)
                        }
                    }
                    RowLayout {
                        visible: root.editMode; Layout.fillWidth: true
                        Label { text: qsTr("I want"); color: theme.secondaryText; Layout.preferredWidth: 82 }
                        MacTextField { id: wantEditor; text: storyIWant; Layout.fillWidth: true }
                    }
                    RowLayout {
                        visible: root.editMode; Layout.fillWidth: true
                        Label { text: qsTr("So that"); color: theme.secondaryText; Layout.preferredWidth: 82 }
                        MacTextField { id: outcomeEditor; text: storySoThat; Layout.fillWidth: true }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Acceptance Criteria"); font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    MacIconButton {
                        iconName: "add"; enabled: !root.readOnly
                        onClicked: addCriterionDialog.open()
                    }
                }
                Repeater {
                    model: storyCriteria
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 0
                        ItemDelegate {
                            Layout.fillWidth: true; implicitHeight: 42
                            background: Rectangle { color: "transparent" }
                            contentItem: RowLayout {
                                spacing: 12
                                IconLabel {
                                    text: modelData.isMet ? "check_circle" : "radio_button_unchecked"
                                    color: modelData.isMet ? theme.green : theme.secondaryText; font.pixelSize: 20
                                }
                                Label {
                                    text: modelData.text; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                    color: modelData.isMet ? theme.secondaryText : theme.text
                                    font.strikeout: modelData.isMet
                                }
                                MacIconButton {
                                    iconName: "delete"; enabled: !root.readOnly
                                    onClicked: workspace.deleteAcceptanceCriterion(storyId, modelData.id)
                                }
                            }
                            onClicked: if (!root.readOnly) workspace.toggleAcceptanceCriterion(storyId, modelData.id)
                        }
                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 32; Layout.preferredHeight: 1; color: theme.separator }
                    }
                }
                Label {
                    visible: storyCriteria.length === 0; text: qsTr("No acceptance criteria yet.")
                    color: theme.secondaryText; Layout.fillWidth: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                RowLayout {
                    Label { text: qsTr("Completion"); font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Label { text: Math.round(root.completion * 100) + "%"; font.pixelSize: 19; font.weight: Font.DemiBold }
                }
                MacProgressBar { Layout.fillWidth: true; value: root.completion }
                Label {
                    text: qsTr("%1 of %2 criteria met").arg(root.metCriteriaCount).arg(storyCriteria.length)
                    color: theme.secondaryText; font.pixelSize: 12
                }
                MacButton {
                    visible: storyStatus === "active" && storyCriteria.length > 0 && root.completion === 1
                    text: qsTr("Mark as Completed"); iconName: "check_circle"; prominent: true
                    Layout.fillWidth: true; onClicked: workspace.setStoryStatus(storyId, "done")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                ItemDelegate {
                    Layout.fillWidth: true; implicitHeight: 36
                    background: Rectangle { color: "transparent" }
                    contentItem: RowLayout {
                        IconLabel { text: "chevron_right"; rotation: root.notesExpanded ? 90 : 0 }
                        Label { text: qsTr("Notes"); font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        Label { visible: storyNotes === ""; text: qsTr("Optional"); color: theme.tertiaryText }
                    }
                    onClicked: root.notesExpanded = !root.notesExpanded
                }
                TextArea {
                    id: notesEditor; visible: root.notesExpanded; text: storyNotes
                    readOnly: root.readOnly; wrapMode: TextArea.Wrap; Layout.fillWidth: true; Layout.preferredHeight: 110
                    padding: 10
                    background: Rectangle { radius: theme.mediumRadius; color: theme.panel; border.width: 1; border.color: theme.separator }
                }
                RowLayout {
                    visible: root.notesExpanded && !root.readOnly; Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    MacButton {
                        text: qsTr("Save Notes"); prominent: true; enabled: notesEditor.text.trim() !== storyNotes
                        onClicked: workspace.updateStoryNotes(storyId, notesEditor.text.trim())
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout {
                    Label { text: qsTr("Attachments"); font.pixelSize: 17; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    MacIconButton { iconName: "attach_file"; enabled: !root.readOnly; onClicked: attachmentDialog.open() }
                }
                Rectangle {
                    visible: storyAttachments.length === 0
                    Layout.fillWidth: true; Layout.preferredHeight: 138
                    radius: theme.mediumRadius; color: Qt.rgba(0, 0, 0, 0.018)
                    border.width: 1; border.color: theme.separator
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 7
                        IconLabel { text: "attach_file"; font.pixelSize: 34; color: theme.accent; Layout.alignment: Qt.AlignHCenter }
                        Label { text: qsTr("Drop files here or choose files"); font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
                        Label { text: qsTr("Images, documents, and other project files"); color: theme.secondaryText; font.pixelSize: 12; Layout.alignment: Qt.AlignHCenter }
                    }
                    DropArea {
                        anchors.fill: parent
                        enabled: !root.readOnly
                        onDropped: (drop) => {
                            if (drop.hasUrls) workspace.importAttachments(storyId, drop.urls)
                        }
                    }
                    TapHandler {
                        enabled: !root.readOnly
                        onTapped: attachmentDialog.open()
                    }
                }
                Repeater {
                    model: storyAttachments
                    delegate: ItemDelegate {
                        required property var modelData
                        Layout.fillWidth: true; implicitHeight: 42
                        contentItem: RowLayout {
                            IconLabel { text: "description" }
                            Label { text: modelData.filename; Layout.fillWidth: true; elide: Text.ElideMiddle }
                            Label { text: Math.max(1, Math.round(modelData.byteSize / 1024)) + " KB"; color: theme.secondaryText }
                            MacIconButton { iconName: "delete"; enabled: !root.readOnly; onClicked: workspace.removeAttachment(storyId, modelData.id) }
                        }
                        background: Rectangle { radius: theme.smallRadius; color: parent.hovered ? theme.control : "transparent" }
                        onClicked: workspace.openAttachment(modelData.relativePath)
                    }
                }
            }
        }
    }

    Dialog {
        id: addCriterionDialog; title: qsTr("Add Acceptance Criterion")
        anchors.centerIn: parent; modal: true; width: 420
        contentItem: MacTextField { id: newCriterionText; placeholderText: qsTr("Expected result") }
        footer: DialogButtonBox {
            MacButton {
                text: qsTr("Add"); prominent: true; enabled: newCriterionText.text.trim() !== ""
                onClicked: {
                    workspace.addAcceptanceCriterion(storyId, newCriterionText.text.trim())
                    if (workspace.lastError === "") { newCriterionText.clear(); addCriterionDialog.close() }
                }
            }
            MacButton { text: qsTr("Cancel"); onClicked: addCriterionDialog.close() }
        }
    }
    Dialog {
        id: deleteStoryDialog; title: qsTr("Delete Story?"); anchors.centerIn: parent; modal: true; width: 440
        contentItem: Label {
            text: qsTr("Deleting this story will permanently remove it, its acceptance criteria, and its attachments. This cannot be undone.")
            wrapMode: Text.WordWrap
        }
        footer: DialogButtonBox {
            MacButton { text: qsTr("Delete Story"); destructive: true; onClicked: { workspace.deleteStory(storyId); root.clear(); deleteStoryDialog.close() } }
            MacButton { text: qsTr("Cancel"); onClicked: deleteStoryDialog.close() }
        }
    }
    FileDialog {
        id: attachmentDialog; title: qsTr("Add Attachments"); fileMode: FileDialog.OpenFiles
        onAccepted: workspace.importAttachments(storyId, selectedFiles)
    }

    function countMetCriteria() {
        var count = 0
        for (var i = 0; i < storyCriteria.length; i++) if (storyCriteria[i].isMet) count++
        return count
    }
    function setStory(s) {
        storyId = s.id || ""; storyNumber = s.number || 0; storyTitle = s.title || ""
        storyAsA = s.asA || ""; storyIWant = s.iWant || ""; storySoThat = s.soThat || ""
        storyStatus = s.status || ""; storyNotes = s.notes || ""; storyCriteria = s.criteria || []
        storyActorId = s.actorId || ""; storyAttachments = s.attachments || []
        editMode = false; notesExpanded = storyNotes !== ""
    }
    function clear() {
        storyId = ""; storyNumber = 0; storyTitle = ""; storyAsA = ""; storyIWant = ""
        storySoThat = ""; storyStatus = ""; storyNotes = ""; storyCriteria = []
        storyActorId = ""; storyAttachments = []; editMode = false; notesExpanded = false
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
            var actorName = qsTr("Unknown actor")
            for (var j = 0; j < workspace.currentActors.length; j++)
                if (workspace.currentActors[j].id === stories[i].actorId) actorName = workspace.currentActors[j].name
            setStory({ id: stories[i].id, number: stories[i].number, title: stories[i].title,
                asA: actorName, actorId: stories[i].actorId, iWant: stories[i].want,
                soThat: stories[i].outcome, status: stories[i].status, notes: stories[i].notes,
                criteria: stories[i].acceptanceCriteria, attachments: stories[i].attachments })
            return
        }
        clear()
    }
}
