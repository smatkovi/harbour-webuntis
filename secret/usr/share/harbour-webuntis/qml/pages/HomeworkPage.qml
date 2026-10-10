import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: homeworkPage
    allowedOrientations: Orientation.All
    
    property int periodId: 0
    property string periodTitle: ""
    property var periodData: null
    
    // Geladene Daten
    property var homeworks: []
    
    // Bearbeiten
    property int editingHomeworkId: 0
    property string homeworkText: ""
    property date homeworkDueDate: {
        var d = new Date()
        d.setDate(d.getDate() + 7)
        return d
    }
    property bool homeworkDueDateSet: false
    property string homeworkRemark: ""
    
    property string statusMessage: ""
    property bool statusError: false
    property bool isLoading: true
    
    Component.onCompleted: {
        loadData()
    }
    
    function loadData() {
        isLoading = true
        
        // Hausübungen aus periodData holen (homeWorks Feld)
        if (periodData && periodData.homeworks) {
            homeworks = periodData.homeworks
            console.log("Loaded " + homeworks.length + " homeworks from periodData")
            isLoading = false
        } else {
            // Fallback: API aufrufen
            python.getHomework(periodId, function(result) {
                isLoading = false
                console.log("getHomework result: " + JSON.stringify(result).substring(0, 300))
                
                if (result.homework) {
                    if (Array.isArray(result.homework)) {
                        homeworks = result.homework
                    } else if (result.homework.records) {
                        homeworks = result.homework.records
                    } else if (result.homework.text) {
                        homeworks = [result.homework]
                    } else {
                        homeworks = []
                    }
                } else {
                    homeworks = []
                }
                console.log("Loaded " + homeworks.length + " homeworks from API")
            })
        }
    }
    
    function reloadData() {
        // Neu laden über getPeriodData
        python.getPeriodData(periodId, function(result) {
            isLoading = false
            if (result && result.homeworks) {
                homeworks = result.homeworks
            }
        })
    }
    
    function formatDateInt(dateInt) {
        if (!dateInt) return ""
        var s = dateInt.toString()
        if (s.length === 8) {
            return s.substring(6, 8) + "." + s.substring(4, 6) + "." + s.substring(0, 4)
        }
        return s
    }
    
    function parseDateInt(dateInt) {
        if (!dateInt) return new Date()
        var s = dateInt.toString()
        if (s.length === 8) {
            var year = parseInt(s.substring(0, 4))
            var month = parseInt(s.substring(4, 6)) - 1
            var day = parseInt(s.substring(6, 8))
            return new Date(year, month, day)
        }
        return new Date()
    }
    
    function formatDateDisplay(d) {
        var day = d.getDate().toString()
        var month = (d.getMonth() + 1).toString()
        var year = d.getFullYear()
        if (day.length === 1) day = "0" + day
        if (month.length === 1) month = "0" + month
        return day + "." + month + "." + year
    }
    
    function formatDateApi(d) {
        var day = d.getDate().toString()
        var month = (d.getMonth() + 1).toString()
        var year = d.getFullYear()
        if (day.length === 1) day = "0" + day
        if (month.length === 1) month = "0" + month
        return year + "-" + month + "-" + day
    }
    
    function clearForm() {
        editingHomeworkId = 0
        homeworkText = ""
        homeworkTextField.text = ""
        homeworkDueDateSet = false
        homeworkRemark = ""
        remarkField.text = ""
        var d = new Date()
        d.setDate(d.getDate() + 7)
        homeworkDueDate = d
    }
    
    function editHomework(hw) {
        editingHomeworkId = hw.id || 0
        homeworkText = hw.text || hw.description || ""
        homeworkTextField.text = homeworkText
        homeworkRemark = hw.remark || ""
        remarkField.text = homeworkRemark
        
        var due = hw.endDate || hw.dueDate || hw.date
        if (due) {
            homeworkDueDate = parseDateInt(due)
            homeworkDueDateSet = true
        } else {
            homeworkDueDateSet = false
        }
        
        statusMessage = "Bearbeite Hausübung #" + editingHomeworkId
        statusError = false
    }
    
    function submitHomework() {
        if (!homeworkText.trim()) {
            statusMessage = "Bitte Hausübungstext eingeben"
            statusError = true
            return
        }
        
        if (!homeworkDueDateSet) {
            statusMessage = "Bitte Fälligkeitsdatum wählen"
            statusError = true
            return
        }
        
        var dueStr = formatDateApi(homeworkDueDate)
        var hwId = editingHomeworkId > 0 ? editingHomeworkId : null
        
        statusMessage = hwId ? "Aktualisiere Hausübung..." : "Speichere Hausübung..."
        statusError = false
        
        python.submitHomework(periodId, homeworkText, dueStr, homeworkRemark, hwId, function(result) {
            if (result.success) {
                statusMessage = hwId ? "Hausübung aktualisiert" : "Hausübung gespeichert"
                statusError = false
                clearForm()
                reloadData()
            } else {
                statusMessage = "Fehler: " + result.error
                statusError = true
            }
        })
    }
    
    function deleteHomework(hwId) {
        if (!hwId) return
        
        statusMessage = "Lösche Hausübung..."
        statusError = false
        
        python.deleteHomework(hwId, function(result) {
            if (result.success) {
                statusMessage = "Hausübung gelöscht"
                statusError = false
                clearForm()
                reloadData()
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
                text: "Neue Hausübung"
                onClicked: clearForm()
            }
            MenuItem {
                text: "Aktualisieren"
                onClicked: reloadData()
            }
        }
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingMedium
            
            PageHeader {
                title: "Hausübungen"
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
            
            // ========== BESTEHENDE HAUSÜBUNGEN ==========
            SectionHeader {
                text: "Bestehende Hausübungen (" + homeworks.length + ")"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Keine Hausübungen vorhanden"
                color: Theme.secondaryColor
                visible: !isLoading && homeworks.length === 0
            }
            
            Repeater {
                model: homeworks
                
                delegate: ListItem {
                    id: hwDelegate
                    width: parent.width
                    contentHeight: hwColumn.height + Theme.paddingMedium
                    
                    property int hwId: modelData.id || 0
                    property bool isEditing: editingHomeworkId === hwId && hwId > 0
                    
                    highlighted: isEditing
                    
                    menu: ContextMenu {
                        MenuItem {
                            text: "Bearbeiten"
                            onClicked: editHomework(modelData)
                        }
                        MenuItem {
                            text: "Löschen"
                            visible: hwId > 0
                            onClicked: {
                                remorseAction("Löschen", function() {
                                    deleteHomework(hwId)
                                })
                            }
                        }
                    }
                    
                    onClicked: editHomework(modelData)
                    
                    Column {
                        id: hwColumn
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        spacing: Theme.paddingSmall
                        
                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall
                            
                            Label {
                                text: isEditing ? "✎" : "📝"
                                font.pixelSize: Theme.fontSizeMedium
                            }
                            
                            Label {
                                width: parent.width - Theme.fontSizeMedium - Theme.paddingSmall
                                text: modelData.text || modelData.description || ""
                                color: isEditing ? Theme.highlightColor : Theme.primaryColor
                                wrapMode: Text.WordWrap
                            }
                        }
                        
                        Row {
                            spacing: Theme.paddingMedium
                            
                            Label {
                                text: {
                                    var due = modelData.endDate || modelData.dueDate || modelData.date
                                    if (due) {
                                        return "📅 Fällig: " + formatDateInt(due)
                                    }
                                    return ""
                                }
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                visible: text !== ""
                            }
                            
                            Label {
                                text: modelData.remark || ""
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                visible: (modelData.remark || "") !== ""
                            }
                        }
                    }
                }
            }
            
            // ========== NEUE/BEARBEITEN HAUSÜBUNG ==========
            SectionHeader {
                text: editingHomeworkId > 0 ? "Hausübung bearbeiten" : "Neue Hausübung"
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Keine Berechtigung für Hausübungen"
                color: Theme.errorColor
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") === -1
            }
            
            // Hausübungstext
            TextArea {
                id: homeworkTextField
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "Hausübungstext eingeben..."
                label: "Aufgabe"
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1
                onTextChanged: homeworkText = text
            }
            
            // Bemerkung
            TextField {
                id: remarkField
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "Bemerkung (optional)"
                label: "Bemerkung"
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1
                onTextChanged: homeworkRemark = text
            }
            
            // Fälligkeitsdatum
            ValueButton {
                id: dueDateButton
                width: parent.width
                label: "Fällig am"
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1
                value: homeworkDueDateSet ? formatDateDisplay(homeworkDueDate) : "Datum wählen..."
                
                onClicked: {
                    var dialog = pageStack.push(dueDatePickerComponent, {
                        date: homeworkDueDate
                    })
                    dialog.accepted.connect(function() {
                        homeworkDueDate = dialog.date
                        homeworkDueDateSet = true
                    })
                }
            }
            
            // Buttons
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingMedium
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1 && homeworkText.trim() !== "" && homeworkDueDateSet
                
                Button {
                    text: editingHomeworkId > 0 ? "Aktualisieren" : "Speichern"
                    onClicked: submitHomework()
                }
                
                Button {
                    text: "Abbrechen"
                    visible: editingHomeworkId > 0
                    onClicked: clearForm()
                }
            }
            
            // Hinweis
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Bitte Text eingeben und Datum wählen"
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                visible: !isLoading && periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1 && (homeworkText.trim() === "" || !homeworkDueDateSet) && editingHomeworkId === 0
            }
            
            // Tipp
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "💡 Tippe auf eine Hausübung zum Bearbeiten"
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                horizontalAlignment: Text.AlignHCenter
                visible: !isLoading && homeworks.length > 0 && editingHomeworkId === 0
            }
            
            Item { height: Theme.paddingLarge; width: 1 }
        }
        
        VerticalScrollDecorator {}
    }
    
    // DatePickerDialog Component
    Component {
        id: dueDatePickerComponent
        
        DatePickerDialog {
        }
    }
}
