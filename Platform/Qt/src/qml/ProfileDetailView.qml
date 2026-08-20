// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var profile: ({})
    property bool editMode: false
    Theme { id: theme }
    Rectangle { anchors.fill: parent; color: theme.window }

    ColumnLayout {
        anchors.centerIn: parent; visible: !profile.id; spacing: 8
        Label {
            text: "person"; font.family: appIconFont; font.pixelSize: 44
            color: theme.tertiaryText; Layout.alignment: Qt.AlignHCenter
        }
        Label { text: qsTr("Select a Profile"); font.pixelSize: 18; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter }
        Label { text: qsTr("Choose a profile to see its details."); color: theme.secondaryText; Layout.alignment: Qt.AlignHCenter }
    }

    ColumnLayout {
        visible: Boolean(profile.id)
        width: Math.min(620, root.width - 72); anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: 36; spacing: 24
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            MacButton {
                text: root.editMode ? qsTr("Save Changes") : qsTr("Edit Profile")
                iconName: "edit"
                onClicked: {
                    if (!root.editMode) { nameField.text = profile.name; roleField.text = profile.role; root.editMode = true; return }
                    workspace.updateActor(profile.id, nameField.text.trim(), roleField.text.trim())
                    if (workspace.lastError === "") root.editMode = false
                }
            }
            MacIconButton { iconName: "delete"; onClicked: deleteDialog.open() }
        }
        Rectangle {
            Layout.alignment: Qt.AlignHCenter; width: 76; height: 76; radius: 38
            color: Qt.rgba(0.04, 0.52, 1, 0.12)
            Label {
                anchors.centerIn: parent; text: profile.name ? profile.name.charAt(0).toUpperCase() : ""
                color: theme.accent; font.pixelSize: 30; font.weight: Font.Bold
            }
        }
        Label {
            visible: !root.editMode; text: profile.name || ""; font.pixelSize: 28
            font.weight: Font.DemiBold; Layout.alignment: Qt.AlignHCenter
        }
        Label {
            visible: !root.editMode; text: profile.role || qsTr("No description")
            color: theme.secondaryText; font.pixelSize: 14; Layout.alignment: Qt.AlignHCenter
        }
        MacTextField { id: nameField; visible: root.editMode; Layout.fillWidth: true; placeholderText: qsTr("Profile name") }
        TextArea {
            id: roleField; visible: root.editMode; Layout.fillWidth: true; Layout.preferredHeight: 100
            placeholderText: qsTr("Short description"); wrapMode: TextArea.Wrap; padding: 10
            background: Rectangle { radius: theme.mediumRadius; color: theme.panel; border.width: 1; border.color: theme.separator }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 76; radius: theme.cardRadius; color: theme.panel
            RowLayout {
                anchors.fill: parent; anchors.margins: 20
                Label { text: qsTr("Stories for this profile"); font.weight: Font.DemiBold; Layout.fillWidth: true }
                Label { text: root.storyCount(); font.pixelSize: 24; font.weight: Font.DemiBold; color: theme.secondaryText }
            }
        }
    }

    Dialog {
        id: deleteDialog; title: qsTr("Delete Profile?"); modal: true; anchors.centerIn: parent; width: 420
        contentItem: Label {
            text: qsTr("A profile can only be deleted when no stories use it.")
            wrapMode: Text.WordWrap
        }
        footer: DialogButtonBox {
            MacButton { text: qsTr("Delete Profile"); destructive: true; onClicked: { workspace.deleteActor(profile.id); if (workspace.lastError === "") { root.profile = ({}); deleteDialog.close() } } }
            MacButton { text: qsTr("Cancel"); onClicked: deleteDialog.close() }
        }
    }

    function setProfile(value) { profile = value || ({}); editMode = false }
    function storyCount() {
        var count = 0; var stories = workspace.currentProject.stories || []
        for (var i = 0; i < stories.length; i++) if (stories[i].actorId === profile.id) count++
        return count
    }
}
