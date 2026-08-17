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
    visible: true

    Settings {
        id: settings
        property string lastProjectId: ""
    }

    Component.onCompleted: {
        if (settings.lastProjectId && workspace.projects.length > 0) {
            workspace.openProject(settings.lastProjectId)
        }
    }

    menuBar: MenuBar {
        Menu {
            title: qsTr("&File")
            Action { text: qsTr("New project…"); onTriggered: welcome.openCreateProject() }
            Action { text: qsTr("Export to Markdown…"); onTriggered: workspace.exportMarkdown(exportDialog.selectedFile) }
            Action { text: qsTr("Import from Markdown…"); onTriggered: workspace.importMarkdown(importDialog.selectedFile) }
            MenuSeparator {}
            Action { text: qsTr("Quit"); onTriggered: Qt.quit() }
        }
        Menu {
            title: qsTr("&Project")
            Action { text: qsTr("Synchronize"); onTriggered: workspace.synchronize() }
            Action { text: qsTr("Refresh"); onTriggered: workspace.refreshCurrent() }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: workspace.currentProjectId === "" ? 0 : 1

        WelcomeView { id: welcome }
        WorkspaceView {}
    }

    footer: ToolBar {
        RowLayout {
            anchors.fill: parent
            anchors.margins: 6
            Label {
                text: workspace.busy ? qsTr("Working…") : qsTr("Ready")
                Layout.fillWidth: true
            }
            Label {
                visible: workspace.lastError !== ""
                text: workspace.lastError
                color: "#b00020"
            }
            Label {
                text: qsTr("Core: %1").arg(appInfo.corePath)
                font.family: "monospace"
                opacity: 0.6
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
