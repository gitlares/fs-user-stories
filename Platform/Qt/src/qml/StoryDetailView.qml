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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: storyTitle === "" ? qsTr("No story selected") : storyTitle
            font.pixelSize: 20
            font.bold: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        GridLayout {
            visible: storyId !== ""
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Layout.fillWidth: true

            Label { text: qsTr("As a") }
            TextField { text: storyAsA; Layout.fillWidth: true; onEditingFinished: workspace.updateStory(storyId, { asA: text }) }

            Label { text: qsTr("I want") }
            TextField { text: storyIWant; Layout.fillWidth: true; onEditingFinished: workspace.updateStory(storyId, { iWant: text }) }

            Label { text: qsTr("So that") }
            TextField { text: storySoThat; Layout.fillWidth: true; onEditingFinished: workspace.updateStory(storyId, { soThat: text }) }

            Label { text: qsTr("Status") }
            ComboBox {
                model: ["draft", "active", "completed"]
                currentIndex: model.indexOf(storyStatus)
                onActivated: workspace.updateStory(storyId, { status: currentValue })
            }
        }

        Label { text: qsTr("Notes"); font.bold: true }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                text: storyNotes
                placeholderText: qsTr("Notes are saved automatically.")
                wrapMode: TextArea.Wrap
                onEditingFinished: workspace.updateStory(storyId, { notes: text })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Button {
                text: qsTr("Delete")
                enabled: storyId !== ""
                onClicked: {
                    workspace.deleteStory(storyId)
                    storyId = ""
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
