import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: aboutPage
    allowedOrientations: Orientation.All
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height
        
        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge
            
            PageHeader {
                title: "Über WebUntis TKS"
            }
            
            Image {
                source: "image://theme/icon-l-people"
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "WebUntis für Sailfish OS"
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                horizontalAlignment: Text.AlignHCenter
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "Version 1.8.8"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }
            
            SectionHeader {
                text: "Funktionen"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "• Stundenplan anzeigen\n• Anwesenheit erfassen\n• Lehrstoff eintragen\n• Credentials lokal speichern"
                color: Theme.primaryColor
                wrapMode: Text.WordWrap
            }
            
            SectionHeader {
                text: "Hinweis"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "Diese App nutzt die WebUntis JSON-RPC API. Einige Funktionen wie Anwesenheitserfassung und Stoffeintragung erfordern möglicherweise erweiterte API-Berechtigungen, die nicht für alle Benutzer verfügbar sind.\n\nIn diesem Fall bitte die WebUntis-Webseite verwenden."
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }
        
        VerticalScrollDecorator {}
    }
}
