// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: window
    title: appInfo.name + " " + appInfo.version
    width: 1100
    height: 720
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    color: palette.window

    // Reusable icon label style — Material Symbols ligature + thin font weight.
    component IconLabel: Label {
        font.family: appIconFont
        font.pixelSize: 16
        font.weight: Font.Normal
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Settings {
        id: settings
        property string lastProjectId: ""
    }

    Component.onCompleted: {
        if (workspace.projects.length > 0) {
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
        height: 44
        background: Rectangle {
            color: palette.window
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: palette.mid
            }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 8
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: {
                    if (workspace.currentProjectId === "") return qsTr("FS User Stories")
                    var id = workspace.currentProjectId
                    for (var i = 0; i < workspace.projects.length; i++) {
                        if (workspace.projects[i].id === id) return workspace.projects[i].name
                    }
                    return qsTr("FS User Stories")
                }
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Label.ElideRight
            }

            // Sync indicator
            ToolButton {
                contentItem: IconLabel { text: "sync" }
                ToolTip.text: qsTr("Synchronize with Git")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: workspace.synchronize()
            }
            ToolButton {
                contentItem: IconLabel { text: "refresh" }
                ToolTip.text: qsTr("Refresh")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: workspace.refreshCurrent()
            }
            ToolButton {
                visible: workspace.currentProjectId !== ""
                contentItem: IconLabel { text: "person_add" }
                ToolTip.text: qsTr("Add Profile")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: newActorDialog.open()
            }
            ToolButton {
                visible: workspace.currentProjectId !== ""
                contentItem: IconLabel { text: "edit_square" }
                ToolTip.text: qsTr("Add Story")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: newStoryDialog.open()
            }
            ToolButton {
                contentItem: IconLabel { text: "more_horiz" }
                ToolTip.text: qsTr("More")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: moreMenu.open()
                Menu {
                    id: moreMenu
                    MenuItem {
                        text: qsTr("Export to Markdown…")
                        onTriggered: workspace.exportMarkdown(exportDialog.selectedFile)
                    }
                    MenuItem {
                        text: qsTr("Import from Markdown…")
                        onTriggered: workspace.importMarkdown(importDialog.selectedFile)
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

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")
            Action { text: qsTr("New project…"); onTriggered: welcome.openCreateProject() }
            MenuSeparator {}
            Action { text: qsTr("Quit"); onTriggered: Qt.quit() }
        }
    }

    // ---- Dialogs ----
    Dialog {
        id: aboutDialog
        title: qsTr("About FS User Stories")
        modal: true
        anchors.centerIn: parent
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
                    close()
                }
            }
            Button {
                text: qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: close()
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
            Label { text: qsTr("Paste the invitation URL:"); wrapMode: Text.WordWrap; Layout.fillWidth: true }
            TextField { id: inviteToken; placeholderText: qsTr("https://…/invitation/…"); Layout.fillWidth: true }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Join"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: inviteToken.text.trim() !== ""
                onClicked: { workspace.acceptInvitation(inviteToken.text.trim()); close() }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: close()
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
                onClicked: { close() }   // wired in next iteration
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: close()
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
            Label { text: qsTr("As a") }
            TextField { id: nsAsA; Layout.fillWidth: true }
            Label { text: qsTr("I want") }
            TextField { id: nsIWant; Layout.fillWidth: true }
            Label { text: qsTr("So that") }
            TextField { id: nsSoThat; Layout.fillWidth: true }
        }
        footer: DialogButtonBox {
            Button {
                text: qsTr("Save"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                enabled: nsTitle.text.trim() !== ""
                onClicked: {
                    workspace.createStory(nsTitle.text.trim(),
                                          nsAsA.text.trim(),
                                          nsIWant.text.trim(),
                                          nsSoThat.text.trim())
                    close()
                }
            }
            Button {
                text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: close()
            }
        }
    }

    FileDialog {
        id: exportDialog
        fileMode: FileDialog.SaveFile
        title: qsTr("Export stories to Markdown")
        nameFilters: ["Markdown files (*.md)"]
    }
    FileDialog {
        id: importDialog
        fileMode: FileDialog.OpenFile
        title: qsTr("Import stories from Markdown")
        nameFilters: ["Markdown files (*.md)"]
    }
}
