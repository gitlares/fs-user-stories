// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    signal storySelected(var story)
    signal profileSelected(var actor)
    property bool showProfiles: false
    property string selectedStoryId: ""
    property bool activeExpanded: true
    property bool draftExpanded: false
    property bool doneExpanded: false
    Theme { id: theme }

    Connections {
        target: workspace
        function onCurrentProjectChanged() { Qt.callLater(root.ensureSelection) }
    }

    component IconLabel: Label {
        font.family: appIconFont; font.pixelSize: 16; font.weight: Font.DemiBold
        color: theme.secondaryText
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
    }

    component StorySection: ColumnLayout {
        id: section
        required property string title
        required property var stories
        required property bool expanded
        signal toggleRequested()
        spacing: 0; Layout.fillWidth: true

        ItemDelegate {
            Layout.fillWidth: true; implicitHeight: 42
            background: Rectangle { color: "transparent" }
            contentItem: RowLayout {
                spacing: 7
                IconLabel {
                    text: "chevron_right"; font.pixelSize: 15
                    rotation: section.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: 140 } }
                }
                Label {
                    text: section.title; font.pixelSize: 12; font.weight: Font.DemiBold
                    color: theme.secondaryText; Layout.fillWidth: true
                }
                Label { text: section.stories.length; font.pixelSize: 12; color: theme.tertiaryText }
            }
            onClicked: section.toggleRequested()
        }
        Label {
            visible: section.expanded && section.stories.length === 0
            text: qsTr("No stories in this section"); color: theme.tertiaryText; font.pixelSize: 12
            Layout.fillWidth: true; Layout.leftMargin: 10; Layout.bottomMargin: 10
        }
        Repeater {
            model: section.expanded ? section.stories : []
            delegate: ItemDelegate {
                id: storyRow
                required property var modelData
                Layout.fillWidth: true; implicitHeight: 112
                leftPadding: 10; rightPadding: 10; topPadding: 5; bottomPadding: 5
                background: Rectangle {
                    radius: theme.mediumRadius
                    color: storyRow.modelData.id === root.selectedStoryId ? theme.selection
                         : storyRow.hovered ? Qt.rgba(0, 0, 0, 0.025) : "transparent"
                }
                contentItem: ColumnLayout {
                    spacing: 7
                    RowLayout {
                        Label {
                            text: workspace.currentProject.prefix + "-" + storyRow.modelData.number
                            font.family: "monospace"; font.pixelSize: 11; font.weight: Font.DemiBold
                            color: theme.secondaryText; Layout.fillWidth: true
                        }
                        Label {
                            text: root.statusLabel(storyRow.modelData.status); font.pixelSize: 11
                            color: storyRow.modelData.status === "done" ? "#237a36" : theme.secondaryText
                            background: Rectangle {
                                radius: 5
                                color: storyRow.modelData.status === "done" ? "#dff5e3" : "transparent"
                            }
                            leftPadding: 6; rightPadding: 6; topPadding: 2; bottomPadding: 2
                        }
                    }
                    Label {
                        text: storyRow.modelData.title; font.pixelSize: 14; font.weight: Font.DemiBold
                        color: theme.text; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        maximumLineCount: 2; elide: Text.ElideRight
                    }
                    RowLayout {
                        spacing: 6
                        IconLabel { text: "person"; font.pixelSize: 14 }
                        Label {
                            text: root.actorName(storyRow.modelData.actorId); font.pixelSize: 11
                            color: theme.secondaryText; Layout.fillWidth: true; elide: Text.ElideRight
                        }
                        Label {
                            visible: storyRow.modelData.acceptanceCriteria.length > 0
                            text: qsTr("%1 of %2 criteria met").arg(root.metCriteria(storyRow.modelData))
                                  .arg(storyRow.modelData.acceptanceCriteria.length)
                            font.pixelSize: 11; color: theme.secondaryText
                        }
                    }
                    MacProgressBar {
                        visible: storyRow.modelData.acceptanceCriteria.length > 0; Layout.fillWidth: true
                        value: storyRow.modelData.acceptanceCriteria.length > 0
                               ? root.metCriteria(storyRow.modelData) / storyRow.modelData.acceptanceCriteria.length : 0
                    }
                }
                onClicked: root.selectStory(storyRow.modelData)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 56
            Rectangle {
                width: 200; height: 30; anchors.centerIn: parent; radius: 8; color: theme.control
                RowLayout {
                    anchors.fill: parent; anchors.margins: 2; spacing: 0
                    Repeater {
                        model: [qsTr("Stories"), qsTr("Profiles")]
                        delegate: ItemDelegate {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true; Layout.fillHeight: true
                            background: Rectangle {
                                radius: 6
                                color: (index === 1) === root.showProfiles ? theme.panel : "transparent"
                                border.width: (index === 1) === root.showProfiles ? 1 : 0
                                border.color: theme.separator
                            }
                            contentItem: Label {
                                text: modelData; font.pixelSize: 13
                                font.weight: (index === 1) === root.showProfiles ? Font.DemiBold : Font.Normal
                                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                color: theme.text
                            }
                            onClicked: root.showProfiles = index === 1
                        }
                    }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.separator }

        ColumnLayout {
            visible: !root.showProfiles
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: 20; spacing: 12
                RowLayout {
                    Label { text: qsTr("Stories"); font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true }
                    Label { text: (workspace.currentProject.stories || []).length; color: theme.secondaryText }
                }
                MacTextField {
                    id: searchField; Layout.fillWidth: true; placeholderText: qsTr("Search stories")
                    onTextChanged: {
                        root.activeExpanded = true
                        if (text.trim() !== "") { root.draftExpanded = true; root.doneExpanded = true }
                    }
                }
                RowLayout {
                    spacing: 10
                    IconLabel { text: "filter_list" }
                    Label { text: qsTr("Profile"); font.pixelSize: 12; font.weight: Font.DemiBold; color: theme.secondaryText }
                    MacComboBox {
                        id: actorFilter; Layout.fillWidth: true; model: root.actorFilterItems()
                        textRole: "name"; valueRole: "id"; implicitHeight: 30
                    }
                    MacComboBox {
                        id: sortFilter; model: [qsTr("Newest First"), qsTr("Oldest First"), qsTr("Title A–Z")]
                        implicitHeight: 30
                    }
                }
            }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: width; contentHeight: sectionColumn.implicitHeight; clip: true
                ScrollBar.vertical: ScrollBar {}
                ColumnLayout {
                    id: sectionColumn; x: 12; width: parent.width - 24; spacing: 0
                    StorySection {
                        title: qsTr("Active Stories"); stories: root.storiesFor("active"); expanded: root.activeExpanded
                        onToggleRequested: root.activeExpanded = !root.activeExpanded
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.separator }
                    StorySection {
                        title: qsTr("Drafts"); stories: root.storiesFor("draft"); expanded: root.draftExpanded
                        onToggleRequested: root.draftExpanded = !root.draftExpanded
                    }
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.separator }
                    StorySection {
                        title: qsTr("Completed"); stories: root.storiesFor("done"); expanded: root.doneExpanded
                        onToggleRequested: root.doneExpanded = !root.doneExpanded
                    }
                }
            }
        }
    }

    ProjectProfilesView {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.topMargin: 57
        visible: root.showProfiles; z: 10
        onActorSelected: (actor) => root.profileSelected(actor)
    }

    function actorName(actorId) {
        var actors = workspace.currentProject.actors || []
        for (var i = 0; i < actors.length; i++) if (actors[i].id === actorId) return actors[i].name
        return qsTr("Unknown actor")
    }
    function actorFilterItems() {
        var result = [{ id: "", name: qsTr("All Profiles") }]
        var actors = workspace.currentProject.actors || []
        for (var i = 0; i < actors.length; i++) result.push({ id: actors[i].id, name: actors[i].name })
        return result
    }
    function metCriteria(story) {
        var met = 0; var criteria = story.acceptanceCriteria || []
        for (var i = 0; i < criteria.length; i++) if (criteria[i].isMet) met++
        return met
    }
    function statusLabel(status) {
        if (status === "done") return qsTr("Done")
        if (status === "active") return qsTr("Active")
        return qsTr("Draft")
    }
    function storiesFor(status) {
        var stories = workspace.currentProject.stories || []; var result = []
        var query = searchField.text.trim().toLowerCase(); var actorId = actorFilter.currentValue || ""
        for (var i = 0; i < stories.length; i++) {
            var story = stories[i]
            if (story.status !== status || (actorId !== "" && story.actorId !== actorId)) continue
            var searchable = (story.title + " " + story.want + " " + story.outcome + " " +
                              story.notes + " " + actorName(story.actorId)).toLowerCase()
            if (query !== "" && searchable.indexOf(query) < 0) continue
            result.push(story)
        }
        result.sort(function(a, b) {
            if (sortFilter.currentIndex === 2) return a.title.localeCompare(b.title)
            var delta = (a.number || 0) - (b.number || 0)
            return sortFilter.currentIndex === 1 ? delta : -delta
        })
        return result
    }
    function selectStory(story) {
        selectedStoryId = story.id
        if (story.status === "active") activeExpanded = true
        else if (story.status === "done") doneExpanded = true
        else draftExpanded = true
        storySelected({ id: story.id, title: story.title, asA: actorName(story.actorId),
            iWant: story.want, soThat: story.outcome, status: story.status,
            notes: story.notes, criteria: story.acceptanceCriteria, actorId: story.actorId,
            attachments: story.attachments, number: story.number })
    }
    function ensureSelection() {
        var stories = workspace.currentProject.stories || []
        if (stories.length === 0) { selectedStoryId = ""; return }
        for (var i = 0; i < stories.length; i++) if (stories[i].id === selectedStoryId) return
        selectStory(stories[0])
    }
}
