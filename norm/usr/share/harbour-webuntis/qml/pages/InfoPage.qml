import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: infoPage
    allowedOrientations: Orientation.All
    
    property string title: "Information"
    property string message: ""
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height
        
        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge
            
            PageHeader {
                title: infoPage.title
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: message
                color: Theme.highlightColor
                wrapMode: Text.WordWrap
            }
            
            Button {
                text: "OK"
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: pageStack.pop()
            }
        }
    }
}
