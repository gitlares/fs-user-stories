// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: window
    Theme { id: theme }
    title: appInfo.name + " " + appInfo.version
    width: 1280
    height: 800
    minimumWidth: 1024
    minimumHeight: 680
    visible: true
    color: theme.window

    onClosing: function(close) {
        if (appInfo.keepRunningInTray) {
            close.accepted = false
            window.hide()
        }
    }

    // Reusable icon label style — Material Symbols Outlined (variable font,
    // weight axis 100-700). We pick 500 ("Demibold") because macs SF Symbols
    // default look heavier than weight 100. PixelSize matches the mac toolbar
    // icon size at the 1100x720 default window.
    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 16
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Settings {
        id: settings
        property string lastProjectId: ""
    }

    Component.onCompleted: {
        // Trigger initial workspace load, then auto-open the last project
        // (or the first one if no preference has been recorded). We listen
        // for the projectsChanged signal so we can open a project once the
        // list is actually populated (not on a stale, empty read).
        workspace.load()
    }
    Connections {
        target: workspace
        function onProjectsChanged() {
            if (workspace.projects.length === 0) return
            var target = settings.lastProjectId
            var match = ""
            for (var i = 0; i < workspace.projects.length; i++) {
                if (workspace.projects[i].id === target) match = workspace.projects[i].id
            }
            workspace.openProject(match || workspace.projects[0].id)
        }
    }

    // Toolbar (mac-style primary action row).
    header: ToolBar {
        height: 52
        background: Rectangle {
            color: theme.toolbar
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: theme.separator
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 14
            spacing: 8

            Item { Layout.preferredWidth: 238 }
            IconLabel { text: "side_navigation"; font.pixelSize: 19; opacity: 0.85 }
            Label {
                Layout.fillWidth: true
                text: qsTr("FS User Stories")
                font.pixelSize: 15
                font.weight: Font.Bold
                elide: Label.ElideRight
            }

            // Sync indicator
            MacIconButton {
                iconName: "sync"
                ToolTip.text: qsTr("Synchronize with Git")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: gitDialog.open()
            }
            MacIconButton {
                iconName: "refresh"
                ToolTip.text: qsTr("Refresh")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: workspace.refreshCurrent()
            }
            MacIconButton {
                visible: workspace.currentProjectId !== ""
                iconName: "person_add"
                ToolTip.text: qsTr("Add Profile")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: newActorDialog.open()
            }
            MacIconButton {
                visible: workspace.currentProjectId !== ""
                enabled: workspace.currentActors.length > 0
                iconName: "edit_square"
                ToolTip.text: qsTr("Add Story")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: newStoryDialog.open()
            }
            MacIconButton {
                iconName: "more_horiz"
                circular: true
                ToolTip.text: qsTr("More")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: moreMenu.open()
                Menu {
                    id: moreMenu
                    MenuItem {
                        text: qsTr("Export to Markdown…")
                        enabled: workspace.currentProjectId !== ""
                        onTriggered: exportOptionsDialog.open()
                    }
                    MenuItem {
                        text: qsTr("Import from Markdown…")
                        enabled: workspace.currentProjectId !== ""
                        onTriggered: importDialog.open()
                    }
                    MenuSeparator {}
                    MenuItem {
                        text: qsTr("Edit Project…")
                        enabled: workspace.currentProjectId !== ""
                        onTriggered: {
                            epName.text = workspace.currentProject.name || ""
                            epPrefix.text = workspace.currentProject.prefix || ""
                            editProjectDialog.open()
                        }
                    }
                    MenuSeparator {}
                    MenuItem {
                        text: qsTr("About…")
                        onTriggered: aboutDialog.open()
                    }
                }
            }
        }
    }

    footer: ToolBar {
        height: visible ? 26 : 0
        visible: workspace.busy || workspace.lastError !== ""
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 8
            IconLabel { text: workspace.busy ? "hourglass_top" : "error"; opacity: 0.7 }
            Label {
                text: workspace.busy ? qsTr("Working…") : workspace.lastError
                color: workspace.lastError !== "" ? "#b00020" : palette.windowText
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Label.ElideRight
            }
            Label {
                text: qsTr("Core: %1").arg(appInfo.corePath)
                font.family: "monospace"
                font.pixelSize: 10
                opacity: 0.4
            }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: workspace.currentProjectId === "" ? 0 : 1

        WelcomeView { id: welcome }
        WorkspaceView {}
    }

    // ---- Dialogs ----
    Dialog {
        id: aboutDialog
        title: qsTr("About FS User Stories")
        modal: true
        anchors.centerIn: parent
        width: 520
        contentItem: ColumnLayout {
            spacing: 6
            Label { text: appInfo.name; font.bold: true; font.pixelSize: 18 }
            Label { text: qsTr("Version %1").arg(appInfo.version) }
            Label { text: qsTr("Local, offline-first user stories, shared with Git.") }
            Label {
                text: qsTr("Core: %1").arg(appInfo.corePath)
                font.family: "monospace"; font.pixelSize: 10; opacity: 0.6; wrapMode: Text.WordWrap
            }
        }
        standardButtons: Dialog.Ok
    }

    Dialog {
        id: newProjectDialog
        title: qsTr("Create Project")
        modal: true
        anchors.centerIn: parent
        width: 380
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: qsTr("Name") }
            TextField { id: npName; placeholderText: qsTr("My project"); Layout.fillWidth: true }
            Label { text: qsTr("Prefix (3 letters, uppercase)") }
            TextField { id: npPrefix; placeholderText: qsTr("ABC"); Layout.fillWidth: true; maximumLength: 3 }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Create")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: npName.text.trim() !== "" && npPrefix.text.trim() !== ""
                onClicked: {
                    workspace.createProject(npName.text.trim(), npPrefix.text.trim().toUpperCase())
                    if (workspace.lastError === "") newProjectDialog.close()
                }
            }
            Button {
                text: qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: newProjectDialog.close()
            }
        }
    }

    Dialog {
        id: joinSharedDialog
        title: qsTr("Join Shared Project")
        modal: true
        anchors.centerIn: parent
        width: 460
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: qsTr("Paste the invitation code:"); wrapMode: Text.WordWrap; Layout.fillWidth: true }
            TextField { id: inviteToken; placeholderText: qsTr("Invitation code"); Layout.fillWidth: true }
            Label {
                visible: workspace.lastError !== ""
                text: workspace.lastError
                color: "#b00020"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            ColumnLayout {
                visible: workspace.githubAuthorizationPending
                Layout.fillWidth: true
                spacing: 6
                Label { text: qsTr("Authorize GitHub with this code:") }
                TextEdit {
                    text: workspace.githubAuthorizationCode
                    font.family: "monospace"
                    font.pixelSize: 20
                    font.bold: true
                    readOnly: true
                    selectByMouse: true
                    color: palette.text
                }
                Button {
                    text: qsTr("Open GitHub")
                    onClicked: Qt.openUrlExternally(workspace.githubAuthorizationUrl)
                }
                Label {
                    text: qsTr("Complete authorization in the browser, then choose Continue.")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
        footer: DialogButtonBox {
            Button {
                text: workspace.githubAuthorizationPending ? qsTr("Continue") : qsTr("Join")
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: inviteToken.text.trim() !== ""
                onClicked: {
                    var joined = workspace.githubAuthorizationPending
                        ? workspace.finishInvitationAuthorization()
                        : workspace.acceptInvitation(inviteToken.text.trim())
                    if (joined) {
                        inviteToken.clear()
                        joinSharedDialog.close()
                    }
                }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: {
                    workspace.cancelInvitationAuthorization()
                    joinSharedDialog.close()
                }
            }
        }
    }

    Dialog {
        id: newActorDialog
        title: qsTr("Add Profile")
        modal: true
        anchors.centerIn: parent
        width: 380
        contentItem: ColumnLayout {
            spacing: 6
            Label { text: qsTr("Name") }
            TextField { id: naName; placeholderText: qsTr("Product Manager"); Layout.fillWidth: true }
            Label { text: qsTr("Role") }
            TextField { id: naRole; placeholderText: qsTr("Responsibilities"); Layout.fillWidth: true }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Save"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: naName.text.trim() !== ""
                onClicked: {
                    workspace.addActor(naName.text.trim(), naRole.text.trim())
                    if (workspace.lastError === "") newActorDialog.close()
                }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: newActorDialog.close()
            }
        }
    }

    Dialog {
        id: newStoryDialog
        title: qsTr("Add Story")
        modal: true
        anchors.centerIn: parent
        width: 460
        contentItem: ColumnLayout {
            spacing: 6
            Label { text: qsTr("Title") }
            TextField { id: nsTitle; Layout.fillWidth: true }
            Label { text: qsTr("Actor") }
            ComboBox {
                id: nsActor
                Layout.fillWidth: true
                model: workspace.currentActors
                textRole: "name"
            }
            Label { text: qsTr("I want") }
            TextField { id: nsIWant; Layout.fillWidth: true }
            Label { text: qsTr("So that") }
            TextField { id: nsSoThat; Layout.fillWidth: true }
            Label { text: qsTr("Acceptance criterion") }
            TextField {
                id: nsCriterion
                Layout.fillWidth: true
                placeholderText: qsTr("How will we know it is complete?")
            }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Save"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: nsTitle.text.trim() !== "" &&
                         nsActor.currentIndex >= 0 &&
                         nsIWant.text.trim() !== "" &&
                         nsSoThat.text.trim() !== "" &&
                         nsCriterion.text.trim() !== ""
                onClicked: {
                    workspace.createStory(nsTitle.text.trim(),
                                          workspace.currentActors[nsActor.currentIndex].name,
                                          nsIWant.text.trim(),
                                          nsSoThat.text.trim(),
                                          nsCriterion.text.trim())
                    if (workspace.lastError === "") newStoryDialog.close()
                }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: newStoryDialog.close()
            }
        }
    }

    Dialog {
        id: editProjectDialog
        title: qsTr("Edit Project")
        modal: true; anchors.centerIn: parent; width: 420
        contentItem: ColumnLayout {
            Label { text: qsTr("Project name") }
            TextField { id: epName; Layout.fillWidth: true }
            Label { text: qsTr("Story prefix") }
            TextField { id: epPrefix; Layout.fillWidth: true }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Delete"); DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                onClicked: { workspace.deleteProject(workspace.currentProjectId); if (workspace.lastError === "") editProjectDialog.close() }
            }
            Button {
                text: qsTr("Save"); enabled: epName.text.trim() !== "" && epPrefix.text.trim() !== ""
                onClicked: { workspace.updateProject(epName.text.trim(), epPrefix.text.trim().toUpperCase()); if (workspace.lastError === "") editProjectDialog.close() }
            }
            Button { text: qsTr("Cancel"); onClicked: editProjectDialog.close() }
        }
    }

    Dialog {
        id: gitDialog
        title: qsTr("Git Sharing")
        modal: true
        anchors.centerIn: parent
        width: Math.min(760, window.width - 80)
        height: Math.min(720, window.height - 80)
        contentItem: GitSyncView { anchors.fill: parent }
        footer: DialogButtonBox {
            Button { text: qsTr("Close"); onClicked: gitDialog.close() }
        }
    }

    FileDialog {
        id: exportDialog
        fileMode: FileDialog.SaveFile
        title: qsTr("Export stories to Markdown")
        nameFilters: ["Markdown files (*.md)"]
        onAccepted: workspace.exportMarkdownSelection(
                        selectedFile,
                        ["all", "active", "done", "draft", "selected"][exportScope.currentIndex],
                        exportOptionsDialog.selectedStoryIds())
    }
    FileDialog {
        id: importDialog
        fileMode: FileDialog.OpenFile
        title: qsTr("Import stories from Markdown")
        nameFilters: ["Markdown files (*.md)"]
        onAccepted: {
            if (workspace.prepareMarkdownImport(selectedFile))
                importReviewDialog.open()
        }
    }

    Dialog {
        id: exportOptionsDialog
        property var selectedStories: ({})
        title: qsTr("Export Stories")
        modal: true; anchors.centerIn: parent; width: 560; height: 560
        onOpened: { exportScope.currentIndex = 0; selectedStories = ({}) }
        function selectedStoryIds() {
            var ids = []
            var stories = workspace.currentProject.stories || []
            if (exportScope.currentIndex !== 4) return ids
            for (var i = 0; i < stories.length; i++)
                if (selectedStories[stories[i].id]) ids.push(stories[i].id)
            return ids
        }
        contentItem: ColumnLayout {
            spacing: 14
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: theme.secondaryText
                text: qsTr("Create one Markdown file. Attachments are not included.")
            }
            Label { text: qsTr("Stories to Export"); font.weight: Font.DemiBold }
            MacComboBox {
                id: exportScope; Layout.fillWidth: true
                model: [qsTr("All Stories"), qsTr("Active"), qsTr("Completed"), qsTr("Drafts"), qsTr("Selected Stories")]
            }
            Label {
                visible: exportScope.currentIndex !== 4
                text: qsTr("The matching stories will be included in the file.")
                color: theme.secondaryText
            }
            ScrollView {
                visible: exportScope.currentIndex === 4
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                ColumnLayout {
                    width: parent.width; spacing: 4
                    Repeater {
                        model: workspace.currentProject.stories || []
                        delegate: CheckBox {
                            required property var modelData
                            Layout.fillWidth: true
                            text: (workspace.currentProject.prefix || "") + "-" + modelData.number + " — " + modelData.title
                            onToggled: {
                                exportOptionsDialog.selectedStories[modelData.id] = checked
                                exportOptionsDialog.selectedStories = Object.assign({}, exportOptionsDialog.selectedStories)
                            }
                        }
                    }
                }
            }
        }
        footer: DialogButtonBox {
            Button { text: qsTr("Cancel"); onClicked: exportOptionsDialog.close() }
            Button {
                text: qsTr("Export…")
                enabled: exportScope.currentIndex !== 4 || exportOptionsDialog.selectedStoryIds().length > 0
                onClicked: { exportOptionsDialog.close(); exportDialog.open() }
            }
        }
    }

    Dialog {
        id: importReviewDialog
        property var selectedStories: ({})
        title: qsTr("Review Imported Stories")
        modal: true; anchors.centerIn: parent; width: 600; height: 580
        onOpened: {
            var selected = ({})
            for (var i = 0; i < workspace.pendingImportStories.length; i++)
                selected[workspace.pendingImportStories[i].id] = true
            selectedStories = selected
        }
        function selectedStoryIds() {
            var ids = []
            for (var i = 0; i < workspace.pendingImportStories.length; i++) {
                var story = workspace.pendingImportStories[i]
                if (selectedStories[story.id]) ids.push(story.id)
            }
            return ids
        }
        contentItem: ColumnLayout {
            spacing: 12
            Label {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: theme.secondaryText
                text: qsTr("Choose the stories to add. Existing attachments are not imported.")
            }
            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                ColumnLayout {
                    width: parent.width; spacing: 4
                    Repeater {
                        model: workspace.pendingImportStories
                        delegate: CheckBox {
                            required property var modelData
                            Layout.fillWidth: true
                            checked: Boolean(importReviewDialog.selectedStories[modelData.id])
                            text: (modelData.originalReference || qsTr("Story")) + " — " + modelData.title
                            onToggled: {
                                importReviewDialog.selectedStories[modelData.id] = checked
                                importReviewDialog.selectedStories = Object.assign({}, importReviewDialog.selectedStories)
                            }
                        }
                    }
                }
            }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Cancel")
                onClicked: { workspace.cancelPreparedMarkdownImport(); importReviewDialog.close() }
            }
            Button {
                text: qsTr("Import Selected")
                enabled: importReviewDialog.selectedStoryIds().length > 0
                onClicked: {
                    if (workspace.applyPreparedMarkdownImport(importReviewDialog.selectedStoryIds()))
                        importReviewDialog.close()
                }
            }
        }
    }
}
