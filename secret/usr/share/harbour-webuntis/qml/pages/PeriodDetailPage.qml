import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: detailPage
    allowedOrientations: Orientation.All
    
    property int periodId: 0
    property string periodTitle: ""
    property string periodTime: ""
    property var periodData: null
    property bool isLoading: true
    
    Component.onCompleted: {
        loadPeriodData()
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: contentColumn.height
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: Theme.paddingMedium
            
            PageHeader {
                title: periodTitle
                description: periodTime
            }
            
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: isLoading
                visible: isLoading
            }
            
            // Lehrstoff
            SectionHeader {
                text: "Lehrstoff"
                visible: !isLoading
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !isLoading
                text: {
                    if (!periodData || !periodData.topic) return "(kein Lehrstoff eingetragen)"
                    return periodData.topic.text || periodData.topic.lessonText || "(kein Lehrstoff eingetragen)"
                }
                wrapMode: Text.WordWrap
                color: periodData && periodData.topic && (periodData.topic.text || periodData.topic.lessonText) 
                       ? Theme.primaryColor : Theme.secondaryColor
            }
            
            // Notizen für alle
            SectionHeader {
                text: "Notizen (für alle)"
                visible: !isLoading && periodData && periodData.notesAll && periodData.notesAll.text
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !isLoading && periodData && periodData.notesAll && periodData.notesAll.text
                text: periodData && periodData.notesAll ? periodData.notesAll.text || "" : ""
                wrapMode: Text.WordWrap
                color: Theme.primaryColor
            }
            
            // Notizen für Lehrer
            SectionHeader {
                text: "Notizen (für Lehrer*innen)"
                visible: !isLoading && periodData && periodData.notesStaff && periodData.notesStaff.text
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !isLoading && periodData && periodData.notesStaff && periodData.notesStaff.text
                text: periodData && periodData.notesStaff ? periodData.notesStaff.text || "" : ""
                wrapMode: Text.WordWrap
                color: Theme.highlightColor
            }
            
            // Klassenbucheinträge
            SectionHeader {
                text: "Klassenbucheinträge"
                visible: !isLoading && periodData && periodData.classRegEvents && periodData.classRegEvents.length > 0
            }
            
            Repeater {
                model: !isLoading && periodData && periodData.classRegEvents ? periodData.classRegEvents : []
                
                delegate: Item {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    height: eventLabel.height + Theme.paddingSmall
                    
                    Label {
                        id: eventLabel
                        width: parent.width
                        text: {
                            var ev = modelData
                            var elementName = ev.elementName || "Unbekannt"
                            var reason = ev.reason || ""
                            var note = ev.text || ""
                            var prefix = ev.elementType === "CLASS" ? "📢 " : "👤 "
                            return prefix + elementName + (reason ? " [" + reason + "]" : "") + ": " + note
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryColor
                    }
                }
            }
            
            // Hausübungen
            SectionHeader {
                text: "Hausübungen"
                visible: !isLoading && periodData && periodData.homeworks && periodData.homeworks.length > 0
            }
            
            Repeater {
                model: !isLoading && periodData && periodData.homeworks ? periodData.homeworks : []
                
                delegate: Item {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    height: hwLabel.height + Theme.paddingSmall
                    
                    Label {
                        id: hwLabel
                        width: parent.width
                        text: {
                            var hw = modelData
                            var hwText = hw.text || hw.description || hw.remark || ""
                            var dueDate = hw.dueDate || hw.endDate || ""
                            return "📝 " + hwText + (dueDate ? " (bis " + dueDate + ")" : "")
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryColor
                    }
                }
            }
            
            // Abwesenheiten
            SectionHeader {
                text: "Abwesenheiten"
                visible: !isLoading && periodData && periodData.absences && periodData.absences.length > 0
            }
            
            Repeater {
                model: !isLoading && periodData && periodData.absences ? periodData.absences : []
                
                delegate: Item {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    height: absLabel.height + Theme.paddingSmall
                    
                    Label {
                        id: absLabel
                        width: parent.width
                        text: {
                            var a = modelData
                            // Find student name
                            var studentName = "ID " + a.studentId
                            if (periodData && periodData.students) {
                                for (var i = 0; i < periodData.students.length; i++) {
                                    if (periodData.students[i].studId === a.studentId) {
                                        studentName = periodData.students[i].lastName + " " + periodData.students[i].firstName
                                        break
                                    }
                                }
                            }
                            var reason = a.absenceReason || a.reason || "Abwesend"
                            var isLate = a.isLate || (a.startTime && a.startTime > 0)
                            if (isLate) {
                                return "⏰ " + studentName + ": Verspätet"
                            }
                            return "❌ " + studentName + ": " + reason
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.errorColor
                    }
                }
            }
            
            // Schülerliste
            SectionHeader {
                text: "Schüler*innen (" + (periodData && periodData.students ? periodData.students.length : 0) + ")"
                visible: !isLoading && periodData && periodData.students && periodData.students.length > 0
            }
            
            Repeater {
                model: !isLoading && periodData && periodData.students ? periodData.students : []
                
                delegate: Item {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    height: studentLabel.height + Theme.paddingSmall
                    
                    Label {
                        id: studentLabel
                        width: parent.width
                        text: modelData.lastName + " " + modelData.firstName
                        font.pixelSize: Theme.fontSizeSmall
                        color: {
                            // Check if student has absence
                            if (periodData && periodData.absences) {
                                for (var i = 0; i < periodData.absences.length; i++) {
                                    if (periodData.absences[i].studentId === modelData.studId) {
                                        return Theme.errorColor
                                    }
                                }
                            }
                            return Theme.primaryColor
                        }
                    }
                }
            }
            
            // Keine Daten Hinweis
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !isLoading && (!periodData || periodData.error)
                text: periodData && periodData.error ? periodData.error : "Keine Daten verfügbar"
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }
            
            Item { height: Theme.paddingLarge; width: 1 }
        }
        
        VerticalScrollDecorator {}
    }
    
    function loadPeriodData() {
        isLoading = true
        console.log("PeriodDetailPage: loading data for period " + periodId)
        python.getPeriodData(periodId, function(result) {
            isLoading = false
            periodData = result
            console.log("PeriodDetailPage: loaded data for period " + periodId)
            if (result && result.topic) {
                console.log("PeriodDetailPage: topic = " + JSON.stringify(result.topic))
            } else {
                console.log("PeriodDetailPage: no topic in result")
            }
            if (result && result.error) {
                console.log("PeriodDetailPage: error = " + result.error)
            }
        })
    }
}
