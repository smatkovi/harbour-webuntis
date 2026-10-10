import QtQuick 2.6
import Sailfish.Silica 1.0

Dialog {
    id: editStudentsPage
    allowedOrientations: Orientation.All
    
    property string className: ""
    property var onSaved: function() {}
    property var students: []
    
    Component.onCompleted: {
        python.call('webuntis_backend.load_students', [className], function(result) {
            if (result && result.length > 0) {
                students = result
                textArea.text = result.join("\n")
            }
        })
    }
    
    onAccepted: {
        // Namen aus TextArea lesen (ein Name pro Zeile)
        var lines = textArea.text.split("\n")
        var names = []
        for (var i = 0; i < lines.length; i++) {
            var name = lines[i].trim()
            if (name.length > 0) {
                names.push(name)
            }
        }
        
        // Speichern
        python.call('webuntis_backend.save_students', [className, names], function(result) {
            onSaved()
        })
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height
        
        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium
            
            DialogHeader {
                title: "Schülerliste: " + className
                acceptText: "Speichern"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "Ein Name pro Zeile eingeben:"
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
            }
            
            TextArea {
                id: textArea
                width: parent.width
                height: Math.max(Screen.height * 0.5, implicitHeight)
                placeholderText: "Mustermann Max\nMusterfrau Maria\n..."
                label: "Schülerliste"
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: TextEdit.NoWrap
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "Tipp: Namen aus WebUntis oder Klassenliste kopieren"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
            }
            
            SectionHeader {
                text: "Schnelleingabe"
            }
            
            TextField {
                id: quickAddField
                width: parent.width
                placeholderText: "Name hinzufügen"
                label: "Neuer Schüler"
                EnterKey.enabled: text.length > 0
                EnterKey.iconSource: "image://theme/icon-m-add"
                EnterKey.onClicked: {
                    if (textArea.text.length > 0 && !textArea.text.endsWith("\n")) {
                        textArea.text += "\n"
                    }
                    textArea.text += text
                    text = ""
                }
            }
        }
        
        VerticalScrollDecorator {}
    }
}
