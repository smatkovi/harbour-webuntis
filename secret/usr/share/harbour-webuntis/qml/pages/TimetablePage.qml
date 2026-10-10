import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: timetablePage
    allowedOrientations: Orientation.All
    
    property bool isLoading: true
    property var lessons: []
    property string viewMode: "today"  // "today" oder "week"
    property int weekOffset: 0  // 0 = aktuelle Woche, -1 = letzte Woche, +1 = nächste Woche
    
    // Wait for login before loading
    Component.onCompleted: {
        if (app.loggedIn) {
            loadTimetable()
        }
    }
    
    // Watch for login state changes
    Connections {
        target: app
        onLoggedInChanged: {
            if (app.loggedIn) {
                loadTimetable()
            } else {
                pageStack.replace(Qt.resolvedUrl("LoginPage.qml"))
            }
        }
    }
    
    SilicaListView {
        id: lessonList
        anchors.fill: parent
        model: viewMode === "today" ? todayLessons : lessons
        
        property var todayLessons: {
            var today = new Date()
            var todayInt = today.getFullYear() * 10000 + (today.getMonth() + 1) * 100 + today.getDate()
            return lessons.filter(function(l) { return l.date === todayInt })
        }
        
        header: Column {
            width: parent.width
            
            PageHeader {
                title: {
                    if (viewMode === "today") return "Heute"
                    if (weekOffset === 0) return "Diese Woche"
                    if (weekOffset === -1) return "Letzte Woche"
                    if (weekOffset === 1) return "Nächste Woche"
                    return "Woche " + (weekOffset > 0 ? "+" : "") + weekOffset
                }
                description: app.username
            }
        }
        
        PullDownMenu {
            MenuItem {
                text: "Abmelden"
                onClicked: {
                    python.doLogout(function() {
                        app.loggedIn = false
                        python.call('webuntis_classbook.clear_credentials', [], function() {
                            pageStack.replace(Qt.resolvedUrl("LoginPage.qml"))
                        })
                    })
                }
            }
            MenuItem {
                text: "Anderen Stundenplan anzeigen"
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("TimetableSelectPage.qml"))
                }
            }
            MenuItem {
                text: "Aktualisieren"
                onClicked: loadTimetable()
            }
            MenuItem {
                text: viewMode === "today" ? "Wochenansicht" : "Heute"
                onClicked: {
                    viewMode = (viewMode === "today") ? "week" : "today"
                    if (viewMode === "today") weekOffset = 0
                }
            }
            MenuItem {
                visible: viewMode === "week"
                text: "← Vorherige Woche"
                onClicked: {
                    weekOffset--
                    loadTimetable()
                }
            }
            MenuItem {
                visible: viewMode === "week"
                text: "Nächste Woche →"
                onClicked: {
                    weekOffset++
                    loadTimetable()
                }
            }
            MenuItem {
                visible: viewMode === "week" && weekOffset !== 0
                text: "Zurück zur aktuellen Woche"
                onClicked: {
                    weekOffset = 0
                    loadTimetable()
                }
            }
        }
        
        delegate: ListItem {
            id: lessonItem
            contentHeight: lessonColumn.height + 2 * Theme.paddingMedium
            
            property var lesson: modelData
            property bool isCancelled: lesson.code === "cancelled"
            property bool hasClasses: lesson.classes && lesson.classes.length > 0
            
            menu: ContextMenu {
                MenuItem {
                    text: "Klassenbuch öffnen"
                    visible: hasClasses
                    onClicked: openClassbook(lesson)
                }
            }
            
            onClicked: {
                if (hasClasses) {
                    openClassbook(lesson)
                }
            }
            
            Rectangle {
                anchors.fill: parent
                color: isCancelled ? Theme.rgba(Theme.errorColor, 0.1) : "transparent"
            }
            
            Column {
                id: lessonColumn
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: parent.width - 2*x
                spacing: Theme.paddingSmall
                
                // Datum (nur in Wochenansicht bei neuem Tag)
                Label {
                    text: {
                        var dateInt = lesson.date
                        var year = Math.floor(dateInt / 10000)
                        var month = Math.floor((dateInt % 10000) / 100)
                        var day = dateInt % 100
                        var d = new Date(year, month - 1, day)
                        var days = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag']
                        return days[d.getDay()] + ", " + day + "." + month + "."
                    }
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    visible: {
                        if (viewMode !== "week") return false
                        if (index === 0) return true
                        var prevLesson = lessonList.model[index-1]
                        return prevLesson && prevLesson.date !== lesson.date
                    }
                }
                
                Row {
                    width: parent.width
                    spacing: Theme.paddingMedium
                    
                    // Uhrzeit
                    Column {
                        width: Theme.itemSizeSmall
                        
                        Label {
                            text: formatTime(lesson.startTime)
                            font.pixelSize: Theme.fontSizeMedium
                            color: isCancelled ? Theme.secondaryColor : Theme.primaryColor
                        }
                        Label {
                            text: formatTime(lesson.endTime)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                        }
                    }
                    
                    // Fach und Klasse
                    Column {
                        width: parent.width - Theme.itemSizeSmall - Theme.paddingMedium
                        
                        Row {
                            spacing: Theme.paddingSmall
                            
                            Label {
                                text: lesson.subjects.join(", ") || lesson.type || "Kein Fach"
                                font.pixelSize: Theme.fontSizeMedium
                                color: isCancelled ? Theme.secondaryColor : Theme.primaryColor
                                font.strikeout: isCancelled
                            }
                            
                            // Klassenbuch-Icon wenn Klassen vorhanden
                            Image {
                                source: "image://theme/icon-s-clipboard"
                                visible: hasClasses
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: 0.6
                            }
                        }
                        
                        Row {
                            spacing: Theme.paddingSmall
                            
                            Label {
                                text: lesson.classes.join(", ")
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.highlightColor
                            }
                            
                            Label {
                                text: "•"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryColor
                                visible: lesson.rooms && lesson.rooms.length > 0
                            }
                            
                            Label {
                                text: lesson.rooms ? lesson.rooms.join(", ") : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryColor
                            }
                        }
                    }
                }
            }
        }
        
        ViewPlaceholder {
            enabled: !isLoading && lessonList.count === 0
            text: viewMode === "today" ? "Heute keine Stunden" : "Keine Stunden diese Woche"
            hintText: "Ziehen zum Aktualisieren"
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
    
    function loadTimetable() {
        isLoading = true
        
        // Calculate week based on offset
        if (weekOffset === 0) {
            python.getWeek(function(result) {
                handleTimetableResult(result)
            })
        } else {
            // Calculate date for the offset week
            var baseDate = new Date()
            baseDate.setDate(baseDate.getDate() + (weekOffset * 7))
            var monday = new Date(baseDate)
            monday.setDate(monday.getDate() - monday.getDay() + 1)  // Go to Monday
            var friday = new Date(monday)
            friday.setDate(friday.getDate() + 4)
            
            var startStr = monday.getFullYear().toString() + 
                          ((monday.getMonth() + 1) < 10 ? "0" : "") + (monday.getMonth() + 1).toString() +
                          (monday.getDate() < 10 ? "0" : "") + monday.getDate().toString()
            var endStr = friday.getFullYear().toString() +
                        ((friday.getMonth() + 1) < 10 ? "0" : "") + (friday.getMonth() + 1).toString() +
                        (friday.getDate() < 10 ? "0" : "") + friday.getDate().toString()
            
            python.call('webuntis_classbook.get_timetable', [startStr, endStr], function(result) {
                handleTimetableResult(result)
            })
        }
    }
    
    function handleTimetableResult(result) {
        isLoading = false
        
        if (Array.isArray(result)) {
            lessons = result
            
            // Only update app state for current week
            if (weekOffset === 0) {
                app.weekLessons = lessons
                
                // Heute-Filter für Cover
                var today = new Date()
                var todayInt = today.getFullYear() * 10000 + (today.getMonth() + 1) * 100 + today.getDate()
                app.todayLessons = lessons.filter(function(l) {
                    return l.date === todayInt
                })
            }
        } else {
            console.log("Timetable error: " + JSON.stringify(result))
        }
    }
    
    function openClassbook(lesson) {
        // Period-Daten laden und dann ClassbookPage öffnen
        isLoading = true
        
        python.getPeriodData(lesson.id, function(periodData) {
            isLoading = false
            
            if (periodData && !periodData.error) {
                // Add classIds from lesson to periodData
                periodData.classIds = lesson.classIds || []
                
                var title = lesson.subjects.join(", ") + " - " + lesson.classes.join(", ")
                pageStack.push(Qt.resolvedUrl("ClassbookPage.qml"), {
                    periodData: periodData,
                    periodId: lesson.id,
                    periodTitle: title,
                    periodStartTime: lesson.startTime,
                    periodEndTime: lesson.endTime
                })
            } else {
                console.log("Period data error: " + (periodData ? periodData.error : "no data"))
            }
        })
    }
}
