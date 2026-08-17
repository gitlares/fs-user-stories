// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

ApplicationWindow {
    id: window
    title: appInfo.name + " " + appInfo.version
    width: 1280
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true

    Settings {
        id: settings
        property string lastProjectId: ""
    }

    Component.onCompleted: {
        if (workspace.projects.length > 0) {
            // We have projects: open the most recent (or lastProjectId if still valid).
            var target = settings.lastProjectId
            var match = null
            for (var i = 0; i < workspace.projects.length; i++) {
                if (workspace.projects[i].id === target) match = workspace.projects[i].id
            }
            workspace.openProject(match || workspace.projects[0].id)
        }
    }

    // mac-style toolbar/header with project name and right-side action icons
    header: ToolBar {
        height: 44
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            // Project name (mac-style title bar)
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
                font.pixelSize: 15
                font.weight: Font.Medium
                elide: Label.ElideRight
            }

            // Right-side action icons (refresh / sync / more)
            ToolButton {
                text: "⟳"   // refresh
                font.pixelSize: 16
                ToolTip.text: qsTr("Refresh")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: workspace.refreshCurrent()
            }
            ToolButton {
                text: "⟳"   // sync (Git)
                font.pixelSize: 16
                ToolTip.text: qsTr("Synchronize with Git")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: workspace.synchronize()
            }
            ToolButton {
                text: "⋯"   // more
                font.pixelSize: 18
                ToolTip.text: qsTr("More")
                ToolTip.visible: hovered
                ToolTip.delay: 500
                onClicked: moreMenu.open()
                Menu {
                    id: moreMenu
                    MenuItem { text: qsTr("Export to Markdown…"); onTriggered: workspace.exportMarkdown(exportDialog.selectedFile) }
                    MenuItem { text: qsTr("Import from Markdown…"); onTriggered: workspace.importMarkdown(importDialog.selectedFile) }
                    MenuSeparator {}
                    MenuItem { text: qsTr("About…"); onTriggered: aboutDialog.open() }
                }
            }
        }
    }

    // Slim footer (only shows when there's an error or work in progress)
    footer: ToolBar {
        height: visible ? 28 : 0
        visible: workspace.busy || workspace.lastError !== ""
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 8
            BusyIndicator {
                running: workspace.busy
                visible: workspace.busy
                implicitWidth: 14
                implicitHeight: 14
            }
            Label {
                text: workspace.busy ? qsTr("Working…")
                                     : workspace.lastError
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

    // File menu accessible from menu shortcuts (kept for keyboard users)
    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")
            Action { text: qsTr("New project…"); onTriggered: welcome.openCreateProject() }
            MenuSeparator {}
            Action { text: qsTr("Quit"); onTriggered: Qt.quit() }
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
            Label { text: qsTr("Core: %1").arg(appInfo.corePath); font.family: "monospace"; font.pixelSize: 10; opacity: 0.6; wrapMode: Text.WordWrap }
        }
        standardButtons: Dialog.Ok
    }
}
