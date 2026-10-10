import QtQuick 2.6
import Sailfish.Silica 1.0

// Schluessel aus dem QR-Code nachtragen, ohne sich neu anzumelden.
Page {
    id: secretPage
    allowedOrientations: Orientation.All

    property string hint: ""
    property string errorMessage: ""
    property bool isChecking: false

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader { title: "Schlüssel nachtragen" }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: hint.length > 0 ? hint
                      : "Stundendetails, Abwesenheiten und Lehrstoff holt WebUntis nur über die Mobile-Schnittstelle. Die braucht den Schlüssel aus dem QR-Code."
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "In WebUntis: Profil → Freigaben → Anzeigen. Unter dem QR-Code steht der Schlüssel auch als Text."
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
            }

            TextField {
                id: secretField
                width: parent.width
                placeholderText: "16-stellig"
                label: "Schlüssel"
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.enabled: text.trim().length >= 16
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: saveSecret()
            }

            Button {
                text: isChecking ? "Prüfe..." : "Prüfen und speichern"
                anchors.horizontalCenter: parent.horizontalCenter
                enabled: !isChecking && secretField.text.trim().length >= 16
                onClicked: saveSecret()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: errorMessage
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: errorMessage.length > 0
            }

            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: isChecking
                visible: isChecking
            }
        }
    }

    function saveSecret() {
        var page = secretPage
        if (page.isChecking) return
        page.isChecking = true
        page.errorMessage = ""

        python.setSecret(secretField.text, function(result) {
            page.isChecking = false
            if (result && result.success) {
                pageStack.pop()
            } else {
                page.errorMessage = (result && result.error) ? result.error
                                    : "Schlüssel abgelehnt"
            }
        })
    }
}
