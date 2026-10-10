import QtQuick 2.6
import Sailfish.Silica 1.0

CoverBackground {
    id: cover
    
    // Aktuelle Zeit für Updates
    property int currentTime: 0
    property var upcomingEvents: []
    
    // Timer für regelmäßige Aktualisierung (jede Minute)
    Timer {
        id: updateTimer
        interval: 60000  // 1 Minute
        running: Qt.application.active || cover.status === Cover.Active
        repeat: true
        triggeredOnStart: true
        onTriggered: updateCurrentTime()
    }
    
    function updateCurrentTime() {
        var now = new Date()
        currentTime = now.getHours() * 100 + now.getMinutes()
        filterUpcomingEvents()
    }
    
    function filterUpcomingEvents() {
        if (!app.todayLessons || app.todayLessons.length === 0) {
            upcomingEvents = []
            return
        }
        
        var events = []
        var now = currentTime
        
        for (var i = 0; i < app.todayLessons.length; i++) {
            var lesson = app.todayLessons[i]
            if (!lesson) continue
            
            var start = lesson.startTime || 0
            var end = lesson.endTime || 0
            
            // Ereignis ist aktuell laufend oder noch kommend
            if (end >= now || start >= now) {
                var evt = {
                    startTime: start,
                    endTime: end,
                    subjects: lesson.subjects || [],
                    rooms: lesson.rooms || [],
                    classes: lesson.classes || [],
                    code: lesson.code || "",
                    type: lesson.type || "lesson",  // lesson, break, supervision, etc.
                    isCurrent: (start <= now && end > now),
                    isNext: false
                }
                events.push(evt)
            }
        }
        
        // Sortieren nach Startzeit
        events.sort(function(a, b) { return a.startTime - b.startTime })
        
        // Markiere das nächste Event (falls keins aktuell läuft)
        var hasCurrentEvent = events.some(function(e) { return e.isCurrent })
        if (!hasCurrentEvent && events.length > 0) {
            events[0].isNext = true
        }
        
        // Maximal 3 Events anzeigen
        upcomingEvents = events.slice(0, 3)
    }
    
    function formatTime(t) {
        if (!t) return ""
        var h = Math.floor(t / 100)
        var m = t % 100
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
    }
    
    function getEventLabel(evt) {
        if (!evt) return ""
        
        // Fach/Beschreibung
        if (evt.subjects && evt.subjects.length > 0) {
            return evt.subjects.join(", ")
        }
        
        // Fallback: Klassen oder Typ
        if (evt.classes && evt.classes.length > 0) {
            return evt.classes.join(", ")
        }
        
        return evt.type || ""
    }
    
    Column {
        anchors.centerIn: parent
        spacing: Theme.paddingSmall
        width: parent.width - 2*Theme.paddingMedium
        
        Label {
            text: "WebUntis"
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
            anchors.horizontalCenter: parent.horizontalCenter
        }
        
        Label {
            text: app.loggedIn ? app.username : "Nicht angemeldet"
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeExtraSmall
            anchors.horizontalCenter: parent.horizontalCenter
            truncationMode: TruncationMode.Fade
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }
        
        Item { height: Theme.paddingSmall; width: 1 }
        
        // Kommende Ereignisse anzeigen
        Column {
            width: parent.width
            visible: app.loggedIn && upcomingEvents.length > 0
            spacing: Theme.paddingSmall
            
            Repeater {
                model: upcomingEvents
                
                Row {
                    width: parent.width
                    spacing: Theme.paddingSmall
                    
                    // Indikator für aktuelle Stunde
                    Rectangle {
                        width: 3
                        height: parent.height
                        color: modelData.isCurrent ? Theme.highlightColor : "transparent"
                        radius: 1
                    }
                    
                    Label {
                        text: formatTime(modelData.startTime)
                        color: modelData.isCurrent ? Theme.highlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.bold: modelData.isCurrent
                        width: Theme.itemSizeExtraSmall * 0.65
                    }
                    
                    Label {
                        text: getEventLabel(modelData)
                        color: {
                            if (modelData.code === "cancelled") return Theme.secondaryColor
                            if (modelData.isCurrent) return Theme.highlightColor
                            return Theme.primaryColor
                        }
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.strikeout: modelData.code === "cancelled"
                        font.bold: modelData.isCurrent
                        truncationMode: TruncationMode.Fade
                        width: parent.width - Theme.itemSizeExtraSmall * 0.65 - Theme.paddingSmall - 3
                    }
                }
            }
        }
        
        // Keine Stunden mehr
        Label {
            text: app.loggedIn ? 
                  (app.todayLessons.length === 0 ? "Keine Stunden" : "Feierabend! 🎉") :
                  ""
            color: Theme.secondaryColor
            font.pixelSize: Theme.fontSizeSmall
            anchors.horizontalCenter: parent.horizontalCenter
            visible: app.loggedIn && upcomingEvents.length === 0
        }
    }
    
    // Cover-Aktionen
    CoverActionList {
        id: coverActions
        
        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: {
                updateCurrentTime()
                // Optional: Daten neu laden
                if (app.loggedIn) {
                    app.refreshTimetable()
                }
            }
        }
    }
    
    Component.onCompleted: updateCurrentTime()
    
    // Update wenn App aktiviert wird
    Connections {
        target: Qt.application
        onActiveChanged: {
            if (Qt.application.active) {
                updateCurrentTime()
            }
        }
    }
}
