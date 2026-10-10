import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: viewPage
    allowedOrientations: Orientation.All
    
    property int entityType: 0
    property int entityId: 0
    property string entityName: ""
    
    property bool isLoading: true
    property int weekOffset: 0
    
    ListModel {
        id: lessonModel
    }
    
    Component.onCompleted: {
        loadTimetable()
    }
    
    SilicaListView {
        id: lessonList
        anchors.fill: parent
        model: lessonModel
        
        header: Column {
            width: parent.width
            
            PageHeader {
                title: entityName
                description: {
                    if (weekOffset === 0) return "Diese Woche"
                    if (weekOffset === -1) return "Letzte Woche"
                    if (weekOffset === 1) return "Nächste Woche"
                    return "Woche " + (weekOffset > 0 ? "+" : "") + weekOffset
                }
            }
        }
        
        PullDownMenu {
            MenuItem {
                text: "← Vorherige Woche"
                onClicked: {
                    weekOffset--
                    loadTimetable()
                }
            }
            MenuItem {
                text: "Nächste Woche →"
                onClicked: {
                    weekOffset++
                    loadTimetable()
                }
            }
            MenuItem {
                visible: weekOffset !== 0
                text: "Aktuelle Woche"
                onClicked: {
                    weekOffset = 0
                    loadTimetable()
                }
            }
        }
        
        section {
            property: "dateFormatted"
            delegate: SectionHeader {
                text: section
            }
        }
        
        delegate: ListItem {
            id: lessonItem
            contentHeight: lessonColumn.height + 2 * Theme.paddingMedium
            
            property bool isCancelled: model.code === "cancelled"
            
            onClicked: {
                // Öffne Stundendetails
                pageStack.push(Qt.resolvedUrl("PeriodDetailPage.qml"), {
                    periodId: model.lessonId,
                    periodTitle: model.subjectsStr,
                    periodTime: model.dateFormatted + " " + model.timeRange
                })
            }
            
            Column {
                id: lessonColumn
                anchors {
                    left: parent.left
                    right: parent.right
                    margins: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                spacing: Theme.paddingSmall
                
                Row {
                    spacing: Theme.paddingMedium
                    
                    Label {
                        text: model.timeRange
                        font.pixelSize: Theme.fontSizeSmall
                        color: isCancelled ? Theme.secondaryColor : Theme.primaryColor
                    }
                    
                    Label {
                        text: model.subjectsStr
                        font.bold: true
                        font.strikeout: isCancelled
                        color: isCancelled ? Theme.secondaryColor : Theme.highlightColor
                    }
                }
                
                Row {
                    spacing: Theme.paddingMedium
                    
                    Label {
                        visible: entityType !== 1 && model.classesStr !== ""
                        text: "📚 " + model.classesStr
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                    
                    Label {
                        visible: entityType !== 2 && model.teachersStr !== ""
                        text: "👩‍🏫 " + model.teachersStr
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                    
                    Label {
                        visible: entityType !== 4 && model.roomsStr !== ""
                        text: "🚪 " + model.roomsStr
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                }
                
                Label {
                    visible: isCancelled
                    text: "⚠ Entfällt"
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.errorColor
                }
            }
        }
        
        ViewPlaceholder {
            enabled: !isLoading && lessonList.count === 0
            text: "Keine Stunden in dieser Woche"
            hintText: "Wischen zum Wechseln der Woche"
        }
        
        BusyIndicator {
            anchors.centerIn: parent
            size: BusyIndicatorSize.Large
            running: isLoading
            visible: isLoading
        }
        
        VerticalScrollDecorator {}
    }
    
    function formatTime(t) {
        if (!t) return ""
        var h = Math.floor(t / 100)
        var m = t % 100
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }
    
    function formatDate(dateInt) {
        if (!dateInt) return ""
        var str = dateInt.toString()
        var year = str.substring(0, 4)
        var month = str.substring(4, 6)
        var day = str.substring(6, 8)
        
        var days = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
        var d = new Date(parseInt(year), parseInt(month) - 1, parseInt(day))
        return days[d.getDay()] + ", " + day + "." + month + "."
    }
    
    function loadTimetable() {
        isLoading = true
        lessonModel.clear()
        
        // Calculate week dates
        var baseDate = new Date()
        baseDate.setDate(baseDate.getDate() + (weekOffset * 7))
        var monday = new Date(baseDate)
        monday.setDate(monday.getDate() - monday.getDay() + 1)
        var friday = new Date(monday)
        friday.setDate(friday.getDate() + 4)
        
        var startStr = monday.getFullYear().toString() + 
                      ((monday.getMonth() + 1) < 10 ? "0" : "") + (monday.getMonth() + 1).toString() +
                      (monday.getDate() < 10 ? "0" : "") + monday.getDate().toString()
        var endStr = friday.getFullYear().toString() +
                    ((friday.getMonth() + 1) < 10 ? "0" : "") + (friday.getMonth() + 1).toString() +
                    (friday.getDate() < 10 ? "0" : "") + friday.getDate().toString()
        
        python.getTimetableFor(entityType, entityId, startStr, endStr, function(result) {
            isLoading = false
            
            if (Array.isArray(result)) {
                for (var i = 0; i < result.length; i++) {
                    var l = result[i]
                    lessonModel.append({
                        lessonId: l.id,
                        date: l.date,
                        dateFormatted: formatDate(l.date),
                        timeRange: formatTime(l.startTime) + " - " + formatTime(l.endTime),
                        code: l.code || "",
                        subjectsStr: l.subjects ? l.subjects.join(", ") : "",
                        classesStr: l.classes ? l.classes.join(", ") : "",
                        teachersStr: l.teachers ? l.teachers.join(", ") : "",
                        roomsStr: l.rooms ? l.rooms.join(", ") : ""
                    })
                }
            } else {
                console.log("Timetable error: " + JSON.stringify(result))
            }
        })
    }
}
