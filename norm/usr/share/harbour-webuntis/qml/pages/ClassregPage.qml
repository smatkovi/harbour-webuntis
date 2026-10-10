import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: classregPage
    allowedOrientations: Orientation.All
    
    property int periodId: 0
    property string periodTitle: ""
    property var periodData: null
    property var students: []
    
    // Geladene Daten
    property var classregEvents: []
    property var eventReasons: []
    
    // Auswahl für neue Einträge
    property var selectedStudentIds: ({})
    property int selectedReasonIndex: -1
    property string classregText: ""
    
    property string statusMessage: ""
    property bool statusError: false
    property bool isLoading: true
    
    property bool hasWritePermission: periodData && periodData.can && periodData.can.indexOf("WRITE_CLASSREGEVENT") !== -1
    
    Component.onCompleted: {
        if (periodData && periodData.students) {
            students = periodData.students
        }
        loadData()
    }
    
    function loadData() {
        isLoading = true
        
        // Events und Reasons laden
        python.getClassregEvents(periodId, function(result) {
            console.log("getClassregEvents result: " + JSON.stringify(result).substring(0, 200))
            
            if (result.events) {
                classregEvents = result.events
            }
            if (result.eventReasons && result.eventReasons.length > 0) {
                eventReasons = result.eventReasons
            }
            
            console.log("Loaded " + classregEvents.length + " events, " + eventReasons.length + " reasons")
            isLoading = false
        })
    }
    
    function toggleStudent(studentId) {
        var newMap = {}
        for (var key in selectedStudentIds) {
            newMap[key] = selectedStudentIds[key]
        }
        if (newMap[studentId]) {
            delete newMap[studentId]
        } else {
            newMap[studentId] = true
        }
        selectedStudentIds = newMap
    }
    
    function isStudentSelected(studentId) {
        return selectedStudentIds[studentId] === true
    }
    
    function getSelectedCount() {
        return Object.keys(selectedStudentIds).length
    }
    
    function selectAllStudents() {
        var newMap = {}
        for (var i = 0; i < students.length; i++) {
            newMap[students[i].studId] = true
        }
        selectedStudentIds = newMap
    }
    
    function deselectAllStudents() {
        selectedStudentIds = {}
    }
    
    function getStudentName(studentId) {
        for (var i = 0; i < students.length; i++) {
            if (students[i].studId === studentId) {
                return students[i].lastName + " " + students[i].firstName
            }
        }
        return "Unbekannt"
    }
    
    function getSelectedReasonId() {
        if (selectedReasonIndex >= 0 && selectedReasonIndex < eventReasons.length) {
            return eventReasons[selectedReasonIndex].id
        }
        return null  // null = keine Kategorie (optional)
    }
    
    function canSubmit() {
        // Mindestens ein Schüler und Text eingegeben
        return getSelectedCount() > 0 && classregText.trim().length > 0
    }
    
    function submitClassregEntries() {
        var ids = Object.keys(selectedStudentIds)
        if (ids.length === 0) {
            statusMessage = "Bitte mindestens eine/n Schüler*in auswählen"
            statusError = true
            return
        }
        
        if (!classregText.trim()) {
            statusMessage = "Bitte Eintrag-Text eingeben"
            statusError = true
            return
        }
        
        var reasonId = getSelectedReasonId()  // kann null sein
        
        statusMessage = "Speichere " + ids.length + " Einträge..."
        statusError = false
        
        // Alle Schüler-IDs als Liste senden
        var studentIdList = ids.map(function(id) { return parseInt(id) })
        
        python.submitClassregEvent(periodId, studentIdList, reasonId, classregText.trim(), function(result) {
            if (result.success) {
                statusMessage = (result.count || ids.length) + " Einträge gespeichert"
                statusError = false
                selectedStudentIds = {}
                classregText = ""
                classregTextField.text = ""
                selectedReasonIndex = -1
                loadData()
            } else {
                statusMessage = "Fehler: " + result.error
                statusError = true
            }
        })
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height + Theme.paddingLarge
        
        PullDownMenu {
            MenuItem {
                text: "Alle auswählen"
                onClicked: selectAllStudents()
            }
            MenuItem {
                text: "Auswahl aufheben"
                onClicked: deselectAllStudents()
            }
            MenuItem {
                text: "Aktualisieren"
                onClicked: loadData()
            }
        }
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingSmall
            
            PageHeader {
                title: "Klassenbucheinträge"
                description: periodTitle
            }
            
            // Loading
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: isLoading
                visible: isLoading
            }
            
            // Status
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: statusMessage
                color: statusError ? Theme.errorColor : Theme.highlightColor
                visible: statusMessage !== ""
                wrapMode: Text.WordWrap
            }
            
            // ========== BESTEHENDE EINTRÄGE ==========
            SectionHeader {
                text: "Bestehende Einträge (" + classregEvents.length + ")"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Keine Einträge vorhanden"
                color: Theme.secondaryColor
                visible: !isLoading && classregEvents.length === 0
            }
            
            Repeater {
                model: classregEvents
                
                delegate: ListItem {
                    width: parent.width
                    contentHeight: eventColumn.height + Theme.paddingSmall
                    
                    Column {
                        id: eventColumn
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingSmall
                        
                        Label {
                            width: parent.width
                            text: {
                                var name = modelData.studentName || getStudentName(modelData.studentId) || "Unbekannt"
                                return "👤 " + name
                            }
                            color: Theme.highlightColor
                        }
                        
                        Label {
                            width: parent.width
                            text: modelData.text || modelData.note || ""
                            color: Theme.primaryColor
                            wrapMode: Text.WordWrap
                            visible: (modelData.text || modelData.note || "") !== ""
                        }
                        
                        Label {
                            width: parent.width
                            text: modelData.reasonName || modelData.reason || ""
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeSmall
                            visible: (modelData.reasonName || modelData.reason || "") !== ""
                        }
                    }
                }
            }
            
            // ========== NEUER EINTRAG ==========
            SectionHeader {
                text: "Neuer Eintrag"
                visible: !isLoading && hasWritePermission
            }
            
            // Keine Berechtigung
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Keine Berechtigung für Klassenbucheinträge"
                color: Theme.errorColor
                visible: !isLoading && !hasWritePermission
            }
            
            // Klassenbucheintrag Text (immer sichtbar wenn Berechtigung)
            TextArea {
                id: classregTextField
                width: parent.width
                placeholderText: "Klassenbucheintrag eingeben..."
                label: "Eintrag (max. 1000 Zeichen)"
                visible: !isLoading && hasWritePermission
                onTextChanged: classregText = text
            }
            
            // Kategorie auswählen (nur wenn verfügbar)
            ComboBox {
                id: reasonCombo
                width: parent.width
                label: "Kategorie (optional)"
                visible: !isLoading && hasWritePermission && eventReasons.length > 0
                currentIndex: selectedReasonIndex
                value: selectedReasonIndex >= 0 ? eventReasons[selectedReasonIndex].name : "Keine"
                
                menu: ContextMenu {
                    MenuItem {
                        text: "Keine Kategorie"
                        onClicked: selectedReasonIndex = -1
                    }
                    Repeater {
                        model: eventReasons
                        
                        MenuItem {
                            text: modelData.name || modelData.longName || ("Kategorie " + modelData.id)
                            onClicked: selectedReasonIndex = index
                        }
                    }
                }
            }
            
            // Schüler*innen Auswahl Header
            SectionHeader {
                text: "Schüler*innen (" + getSelectedCount() + "/" + students.length + " ausgewählt)"
                visible: !isLoading && hasWritePermission
            }
            
            // Schüler Liste (immer sichtbar wenn Berechtigung)
            Repeater {
                model: (!isLoading && hasWritePermission) ? students : []
                
                delegate: ListItem {
                    id: studentDelegate
                    width: parent.width
                    contentHeight: Theme.itemSizeSmall
                    
                    property int studId: modelData.studId
                    property bool isSelected: isStudentSelected(studId)
                    
                    highlighted: isSelected
                    
                    onClicked: toggleStudent(studId)
                    
                    Row {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.paddingMedium
                        
                        Label {
                            text: isSelected ? "☑" : "☐"
                            font.pixelSize: Theme.fontSizeLarge
                            color: isSelected ? Theme.highlightColor : Theme.secondaryColor
                        }
                        
                        Label {
                            text: modelData.lastName + " " + modelData.firstName
                            color: isSelected ? Theme.highlightColor : Theme.primaryColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
            
            // Speichern Button
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Einträge speichern (" + getSelectedCount() + ")"
                visible: !isLoading && hasWritePermission && canSubmit()
                onClicked: submitClassregEntries()
            }
            
            // Hinweis
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Bitte Text eingeben und Schüler*innen auswählen"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                visible: !isLoading && hasWritePermission && !canSubmit()
            }
            
            Item { height: Theme.paddingLarge; width: 1 }
        }
        
        VerticalScrollDecorator {}
    }
}
