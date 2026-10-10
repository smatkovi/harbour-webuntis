import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: classbookPage
    
    property var periodData: null
    property int periodId: 0
    property string periodTitle: ""
    property int periodStartTime: 0
    property int periodEndTime: 0
    property bool periodLocked: false  // True wenn absenceChecked bereits True ist
    
    // Selected student for lateness dialog
    property int selectedStudentId: 0
    property string selectedStudentName: ""
    
    // Klassenbucheintrag
    property var eventReasons: []
    property int classregStudentId: 0
    property string classregStudentName: ""
    
    // Helper function for old JS engine (no padStart)
    function pad2(n) {
        return (n < 10 ? "0" : "") + n
    }
    
    function formatTime(t) {
        if (!t) return ""
        var h = Math.floor(t / 100)
        var m = t % 100
        return pad2(h) + ":" + pad2(m)
    }
    
    // Klassenbucheintrag Dialog öffnen
    function openClassregDialog(studentId, studentName) {
        classregStudentId = studentId
        classregStudentName = studentName
        
        // EventReasons laden falls noch nicht vorhanden
        if (eventReasons.length === 0) {
            python.getClassregEvents(periodId, function(result) {
                if (result.eventReasons) {
                    eventReasons = result.eventReasons
                    console.log("Loaded " + eventReasons.length + " event reasons")
                }
                // Auto-select first reason
                if (eventReasons.length > 0) {
                    classregDialog.selectedReasonId = eventReasons[0].id
                    console.log("Auto-selected reason: " + eventReasons[0].id)
                }
                classregDialog.open()
            })
        } else {
            // Auto-select first reason
            if (eventReasons.length > 0 && classregDialog.selectedReasonId === 0) {
                classregDialog.selectedReasonId = eventReasons[0].id
                console.log("Auto-selected reason: " + eventReasons[0].id)
            }
            classregDialog.open()
        }
    }
    
    // Klassenbucheintrag Dialog
    Dialog {
        id: classregDialog
        
        property int selectedReasonId: 0
        
        Column {
            width: parent.width
            spacing: Theme.paddingMedium
            
            DialogHeader {
                title: "Klassenbucheintrag"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Eintrag für: " + classregStudentName
                color: Theme.highlightColor
            }
            
            ComboBox {
                id: reasonCombo
                width: parent.width
                label: "Grund"
                currentIndex: 0
                
                menu: ContextMenu {
                    Repeater {
                        model: eventReasons
                        MenuItem {
                            text: modelData.name || modelData.longName || ("Grund " + modelData.id)
                            onClicked: {
                                console.log("Selected reason: " + modelData.id + " - " + modelData.name)
                                classregDialog.selectedReasonId = modelData.id
                            }
                        }
                    }
                }
                
                // Auto-select first reason when model changes
                Component.onCompleted: {
                    if (eventReasons.length > 0) {
                        classregDialog.selectedReasonId = eventReasons[0].id
                        console.log("Auto-selected first reason: " + eventReasons[0].id)
                    }
                }
            }
            
            TextArea {
                id: classregNoteField
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "Bemerkung (optional)..."
                label: "Bemerkung"
            }
        }
        
        onAccepted: {
            console.log("Dialog accepted, selectedReasonId: " + classregDialog.selectedReasonId)
            console.log("classregStudentId: " + classregStudentId + ", periodId: " + periodId)
            
            if (classregDialog.selectedReasonId > 0) {
                saveStatus = "Speichere Klassenbucheintrag..."
                saveError = false
                python.submitClassregEvent(periodId, classregStudentId, classregDialog.selectedReasonId, classregNoteField.text, function(result) {
                    if (result.success) {
                        saveStatus = "Klassenbucheintrag gespeichert"
                        classregNoteField.text = ""
                        classregDialog.selectedReasonId = 0
                        reloadPeriodData()
                    } else {
                        saveStatus = "Fehler: " + result.error
                        saveError = true
                        console.log("Classreg error: " + result.error)
                    }
                })
            } else {
                console.log("No reason selected, skipping submit")
                saveStatus = "Bitte Grund auswählen"
                saveError = true
            }
        }
        
        onRejected: {
            classregNoteField.text = ""
            classregDialog.selectedReasonId = 0
        }
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height
        
        PullDownMenu {
            MenuItem {
                text: "Hausübungen"
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("HomeworkPage.qml"), {
                        periodId: periodId,
                        periodTitle: periodTitle,
                        periodData: periodData
                    })
                }
            }
            MenuItem {
                text: "Klassenbucheinträge"
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("ClassregPage.qml"), {
                        periodId: periodId,
                        periodTitle: periodTitle,
                        periodData: periodData
                    })
                }
            }
            MenuItem {
                text: "Alle anwesend"
                onClicked: markAllPresent()
            }
        }
        
        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium
            
            PageHeader {
                title: periodTitle
                description: formatTime(periodStartTime) + " - " + formatTime(periodEndTime)
            }
            
            // Lehrstoff
            TextField {
                id: topicField
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "Lehrstoff eingeben..."
                label: "Lehrstoff"
                // API returns topic with field name 'text'
                text: {
                    if (!periodData || !periodData.topic) {
                        console.log("topicField: no periodData or topic")
                        return ""
                    }
                    var t = periodData.topic
                    var topicText = t.text || t.lessonText || t.lessonTopic || ""
                    console.log("topicField: topic.text = '" + topicText + "'")
                    return topicText
                }
                EnterKey.onClicked: {
                    focus = false
                    saveTopic()
                }
                onFocusChanged: {
                    if (!focus) {
                        console.log("topicField lost focus, saving...")
                        saveTopic()
                    }
                }
            }
            
            // Notizen für Schüler*innen (alle sehen diese)
            TextArea {
                id: notesAllField
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "Notizen für Schüler*innen..."
                label: "Notizen (für alle sichtbar)"
                text: {
                    if (!periodData || !periodData.notesAll) return ""
                    return periodData.notesAll.text || ""
                }
                onFocusChanged: {
                    if (!focus && text !== (periodData && periodData.notesAll ? periodData.notesAll.text || "" : "")) {
                        saveNotesAll()
                    }
                }
            }
            
            // Notizen für Lehrer*innen (nur Lehrer sehen diese)
            TextArea {
                id: notesStaffField
                width: parent.width - 2 * Theme.horizontalPageMargin
                x: Theme.horizontalPageMargin
                placeholderText: "Notizen für Lehrer*innen..."
                label: "Notizen (nur für Lehrer*innen)"
                text: {
                    if (!periodData || !periodData.notesStaff) return ""
                    return periodData.notesStaff.text || ""
                }
                onFocusChanged: {
                    if (!focus && text !== (periodData && periodData.notesStaff ? periodData.notesStaff.text || "" : "")) {
                        saveNotesStaff()
                    }
                }
            }
            
            // Klassenbucheinträge anzeigen (wenn vorhanden)
            SectionHeader {
                text: "Klassenbucheinträge"
                visible: periodData && periodData.classRegEvents && periodData.classRegEvents.length > 0
            }
            
            Repeater {
                model: periodData && periodData.classRegEvents ? periodData.classRegEvents : []
                
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
            
            // Hausübungen anzeigen (wenn vorhanden)
            SectionHeader {
                text: "Hausübungen"
                visible: periodData && periodData.homeworks && periodData.homeworks.length > 0
            }
            
            Repeater {
                model: periodData && periodData.homeworks ? periodData.homeworks : []
                
                delegate: Item {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    x: Theme.horizontalPageMargin
                    height: hwLabel.height + Theme.paddingSmall
                    
                    Label {
                        id: hwLabel
                        width: parent.width
                        text: {
                            var hw = modelData
                            var hwText = hw.text || hw.description || ""
                            var dueDate = hw.endDate || hw.dueDate || ""
                            return "📝 " + hwText + (dueDate ? " (bis " + dueDate + ")" : "")
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryColor
                    }
                }
            }
            
            // Links zu den Einträge-Seiten
            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                visible: periodData && periodData.can && 
                         (periodData.can.indexOf("WRITE_HOMEWORK") !== -1 || 
                          periodData.can.indexOf("WRITE_CLASSREGEVENT") !== -1)
                
                BackgroundItem {
                    width: (parent.width - Theme.paddingMedium) / 2
                    height: Theme.itemSizeSmall
                    visible: periodData && periodData.can && periodData.can.indexOf("WRITE_CLASSREGEVENT") !== -1
                    
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                        radius: Theme.paddingSmall
                        
                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.paddingSmall
                            
                            Label {
                                text: "📋"
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Label {
                                text: "Klassenbuch"
                                color: Theme.highlightColor
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                    
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("ClassregPage.qml"), {
                            periodId: periodId,
                            periodTitle: periodTitle,
                            periodData: periodData
                        })
                    }
                }
                
                BackgroundItem {
                    width: (parent.width - Theme.paddingMedium) / 2
                    height: Theme.itemSizeSmall
                    visible: periodData && periodData.can && periodData.can.indexOf("WRITE_HOMEWORK") !== -1
                    
                    Rectangle {
                        anchors.fill: parent
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                        radius: Theme.paddingSmall
                        
                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.paddingSmall
                            
                            Label {
                                text: "📝"
                                font.pixelSize: Theme.fontSizeSmall
                            }
                            Label {
                                text: "Hausübungen"
                                color: Theme.highlightColor
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }
                    }
                    
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("HomeworkPage.qml"), {
                            periodId: periodId,
                            periodTitle: periodTitle,
                            periodData: periodData
                        })
                    }
                }
            }
            
            SectionHeader {
                text: "Schüler (" + (studentList.count) + ")"
            }
            
            // Save status indicator
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: saveStatus
                color: saveError ? Theme.errorColor : Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                visible: saveStatus !== ""
                wrapMode: Text.WordWrap
            }
            
            // Student list
            Repeater {
                id: studentList
                model: periodData ? periodData.students : []
                
                delegate: ListItem {
                    id: studentItem
                    width: parent.width
                    contentHeight: Theme.itemSizeMedium
                    
                    property var student: modelData
                    // Use studId (renamed from 'id' in backend to avoid QML issues)
                    property int studId: student ? (student.studId || 0) : 0
                    property bool isAbsent: checkAbsentSafe(studId)
                    property bool isLate: checkLateSafe(studId)
                    property int lateMinutes: getLateMinutesSafe(studId)
                    
                    // Context menu
                    menu: ContextMenu {
                        MenuItem {
                            text: isAbsent ? "Anwesend" : "Fehlt"
                            onClicked: toggleAbsent(studId)
                        }
                        MenuItem {
                            text: isLate ? ("Verspätung ändern (" + lateMinutes + " min)") : "Zu spät gekommen..."
                            onClicked: openLatenessDialog(studId, student.firstName + " " + student.lastName)
                        }
                        MenuItem {
                            text: "Krank"
                            onClicked: setAbsenceReason(studId, 51)
                        }
                        MenuItem {
                            text: "Arzt/Behörde"
                            onClicked: setAbsenceReason(studId, 74)
                        }
                        MenuItem {
                            text: "Klassenbucheintrag..."
                            visible: periodData && periodData.can && periodData.can.indexOf("WRITE_CLASSREGEVENT") !== -1
                            onClicked: openClassregDialog(studId, student.firstName + " " + student.lastName)
                        }
                    }
                    
                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.paddingMedium
                        
                        // Student photo (circular) with rounded corners
                        Rectangle {
                            id: photoContainer
                            width: Theme.iconSizeMedium
                            height: width
                            radius: width / 2
                            color: "transparent"
                            clip: true
                            anchors.verticalCenter: parent.verticalCenter
                            visible: studentPhoto.status === Image.Ready
                            
                            Image {
                                id: studentPhoto
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                source: student && student.imageUrl ? student.imageUrl : ""
                            }
                        }
                        
                        // Fallback: Status indicator with initials (when no photo)
                        Rectangle {
                            width: Theme.iconSizeMedium
                            height: width
                            radius: width / 2
                            color: isAbsent ? Theme.errorColor : 
                                   (isLate ? "#d32f2f" : Theme.highlightDimmerColor)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: studentPhoto.status !== Image.Ready
                            
                            Label {
                                anchors.centerIn: parent
                                text: student ? (student.firstName.charAt(0) + student.lastName.charAt(0)) : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: "white"
                            }
                        }
                        
                        // Roter Verspätungs-Button (wenn verspätet)
                        Rectangle {
                            width: Theme.iconSizeMedium * 1.2
                            height: Theme.iconSizeSmall
                            radius: Theme.paddingSmall
                            color: "#d32f2f"
                            visible: isLate
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                anchors.centerIn: parent
                                text: "+" + lateMinutes + " min"
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                                color: "white"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: openLatenessDialog(studId, student.firstName + " " + student.lastName)
                            }
                        }
                        
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                text: student ? (student.lastName + " " + student.firstName) : ""
                                color: isAbsent ? Theme.secondaryColor : Theme.primaryColor
                                font.strikeout: isAbsent
                            }
                            
                            Label {
                                text: isAbsent ? getAbsenceReasonName(studId) : ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.secondaryHighlightColor
                                visible: isAbsent && !isLate
                            }
                        }
                    }
                    
                    onClicked: toggleAbsent(studId)
                }
            }
        }
    }
    
    // Lateness dialog with analog clock
    Dialog {
        id: latenessDialog
        
        property int arrivalHour: 8
        property int arrivalMinute: 0
        
        Column {
            width: parent.width
            spacing: Theme.paddingMedium
            
            DialogHeader {
                title: selectedStudentName
                acceptText: "Speichern"
            }
            
            // Container für TimePicker mit digitaler Anzeige
            Item {
                width: parent.width
                height: timePicker.height + digitalTime.height + Theme.paddingMedium
                
                // Digitale Zeitanzeige oben
                Label {
                    id: digitalTime
                    anchors {
                        top: parent.top
                        horizontalCenter: parent.horizontalCenter
                    }
                    text: pad2(latenessDialog.arrivalHour) + ":" + pad2(latenessDialog.arrivalMinute)
                    font.pixelSize: Theme.fontSizeHuge * 1.5
                    font.bold: true
                    color: Theme.highlightColor
                }
                
                // Native Sailfish OS TimePicker
                TimePicker {
                    id: timePicker
                    anchors {
                        top: digitalTime.bottom
                        topMargin: Theme.paddingMedium
                        horizontalCenter: parent.horizontalCenter
                    }
                    hour: latenessDialog.arrivalHour
                    minute: latenessDialog.arrivalMinute
                    
                    onHourChanged: latenessDialog.arrivalHour = hour
                    onMinuteChanged: latenessDialog.arrivalMinute = minute
                }
            }
            
            // Verspätung anzeigen
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: {
                    var startH = Math.floor(periodStartTime / 100)
                    var startM = periodStartTime % 100
                    var arrivalTotal = latenessDialog.arrivalHour * 60 + latenessDialog.arrivalMinute
                    var startTotal = startH * 60 + startM
                    var diff = arrivalTotal - startTotal
                    if (diff > 0) {
                        return "Verspätung: " + diff + " Minuten"
                    } else {
                        return "Pünktlich (oder früher)"
                    }
                }
                color: Theme.secondaryHighlightColor
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeLarge
            }
            
            // Stundenbeginn Info
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "Stundenbeginn: " + formatTime(periodStartTime)
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeSmall
            }
        }
        
        onOpened: {
            // Prüfe ob bereits eine Verspätung existiert
            var existingAbsence = absenceMap[selectedStudentId]
            if (existingAbsence && existingAbsence.endTime) {
                // Bestehende Verspätung laden
                arrivalHour = Math.floor(existingAbsence.endTime / 100)
                arrivalMinute = existingAbsence.endTime % 100
            } else {
                // Initialize to lesson start time + 5 minutes
                var startH = Math.floor(periodStartTime / 100)
                var startM = periodStartTime % 100
                arrivalHour = startH
                arrivalMinute = Math.min(startM + 5, 59)
            }
            // TimePicker aktualisieren
            timePicker.hour = arrivalHour
            timePicker.minute = arrivalMinute
        }
        
        onAccepted: {
            var arrivalTime = arrivalHour * 100 + arrivalMinute
            setLateness(selectedStudentId, arrivalTime)
        }
    }
    
    // Absence tracking
    property var absenceMap: ({})
    
    // Safe check functions that always return proper boolean/int
    function checkAbsentSafe(studentId) {
        if (!studentId || studentId <= 0) return false
        var result = absenceMap[studentId] !== undefined
        return result === true
    }
    
    function checkLateSafe(studentId) {
        if (!studentId || studentId <= 0) return false
        var absence = absenceMap[studentId]
        if (!absence) return false
        var result = absence.startTime !== undefined && absence.startTime !== null
        return result === true
    }
    
    function getLateMinutesSafe(studentId) {
        if (!studentId || studentId <= 0) return 0
        var absence = absenceMap[studentId]
        if (!absence || !absence.endTime) return 0
        var startH = Math.floor(periodStartTime / 100)
        var startM = periodStartTime % 100
        var arrH = Math.floor(absence.endTime / 100)
        var arrM = absence.endTime % 100
        var diff = (arrH * 60 + arrM) - (startH * 60 + startM)
        return diff > 0 ? diff : 0
    }
    
    // Original functions kept for compatibility
    function checkAbsent(studentId) {
        return checkAbsentSafe(studentId)
    }
    
    function checkLate(studentId) {
        return checkLateSafe(studentId)
    }
    
    function getLateMinutes(studentId) {
        return getLateMinutesSafe(studentId)
    }
    
    function getAbsenceReasonName(studentId) {
        if (!studentId) return ""
        var absence = absenceMap[studentId]
        if (absence && absence.reasonId) {
            var reasons = app.absenceReasons || []
            for (var i = 0; i < reasons.length; i++) {
                if (reasons[i].id === absence.reasonId) {
                    return reasons[i].name
                }
            }
        }
        return "Fehlt"
    }
    
    function toggleAbsent(studentId) {
        console.log("toggleAbsent: studentId=" + studentId)
        if (!studentId || studentId <= 0) return
        
        if (absenceMap[studentId]) {
            delete absenceMap[studentId]
        } else {
            absenceMap[studentId] = { studentId: studentId, reasonId: 75 }
        }
        absenceMapChanged()
        autoSave()
    }
    
    function setAbsenceReason(studentId, reasonId) {
        if (!studentId) return
        absenceMap[studentId] = { studentId: studentId, reasonId: reasonId }
        absenceMapChanged()
        autoSave()
    }
    
    function setLateness(studentId, arrivalTime) {
        if (!studentId) return
        
        // Speichere lokal im absenceMap
        absenceMap[studentId] = { 
            studentId: studentId, 
            startTime: periodStartTime,
            endTime: arrivalTime
        }
        absenceMapChanged()
        
        // Verwende die neue createLatenessWithTime API für direkte Verspätung
        console.log("setLateness: studentId=" + studentId + ", arrivalTime=" + arrivalTime)
        saveStatus = "Speichere Verspätung..."
        saveError = false
        
        python.createLatenessWithTime(periodId, studentId, arrivalTime, null, function(result) {
            if (result.success) {
                console.log("setLateness: success")
                saveStatus = "✓ Verspätung gespeichert"
                saveError = false
                saveStatusTimer.restart()
            } else {
                // Fallback: sync_absences wird das später machen
                console.log("setLateness: API error, will sync later - " + result.error)
                autoSave()
            }
        })
    }
    
    function openLatenessDialog(studentId, name) {
        selectedStudentId = studentId
        selectedStudentName = name
        latenessDialog.open()
    }
    
    function markAllPresent() {
        absenceMap = {}
        absenceMapChanged()
        autoSave()
    }
    
    // Status für Benutzer
    property string saveStatus: ""
    property bool saveError: false
    
    // Auto-save to WebUntis
    function autoSave() {
        // Nicht speichern wenn Stunde bereits abgeschlossen
        if (periodLocked) {
            saveStatus = "⚠ Stunde gesperrt - Änderungen nicht möglich"
            saveError = true
            return
        }
        
        var absences = []
        for (var studentId in absenceMap) {
            absences.push(absenceMap[studentId])
        }
        
        console.log("autoSave: " + absences.length + " absences, period " + periodId)
        saveStatus = "Speichere..."
        saveError = false
        
        // Use syncAbsences which handles both creation AND deletion
        python.syncAbsences(periodId, absences, function(result) {
            if (result.success) {
                console.log("autoSave: success (created: " + (result.created || 0) + ", deleted: " + (result.deleted || 0) + ")")
                saveStatus = "✓ Gespeichert"
                if (result.warning) {
                    saveStatus += " (" + result.warning + ")"
                }
                saveError = false
                // Status nach 2 Sekunden ausblenden
                saveStatusTimer.restart()
            } else {
                console.log("autoSave: error - " + result.error)
                // Prüfe ob es ein Berechtigungsproblem ist
                if (result.error && result.error.indexOf("Schreibberechtigung") !== -1) {
                    periodLocked = true
                }
                saveStatus = "✗ " + (result.error || "Fehler beim Speichern")
                saveError = true
            }
        })
    }
    
    Timer {
        id: saveStatusTimer
        interval: 2000
        onTriggered: {
            if (!saveError) {
                saveStatus = ""
            }
        }
    }
    
    function saveTopic() {
        var topicText = topicField.text.trim()
        console.log("saveTopic called: text='" + topicText + "', periodId=" + periodId)
        if (topicText && periodId) {
            console.log("Calling python.submitTopic...")
            python.submitTopic(periodId, topicText, function(result) {
                if (result.success) {
                    console.log("Topic saved successfully")
                } else {
                    console.log("Topic save error: " + result.error)
                }
            })
        } else {
            console.log("saveTopic skipped: empty text or no periodId")
        }
    }
    
    function saveNotesAll() {
        var text = notesAllField.text.trim()
        if (periodId) {
            saveStatus = "Speichere Notizen..."
            saveError = false
            python.submitPeriodInfo(periodId, 'notesAll', text, function(result) {
                if (result.success) {
                    saveStatus = "Notizen gespeichert"
                    console.log("Notes (all) saved")
                } else {
                    saveStatus = "Fehler: " + result.error
                    saveError = true
                    console.log("Notes (all) save error: " + result.error)
                }
            })
        }
    }
    
    function saveNotesStaff() {
        var text = notesStaffField.text.trim()
        if (periodId) {
            saveStatus = "Speichere Lehrer-Notizen..."
            saveError = false
            python.submitPeriodInfo(periodId, 'notesStaff', text, function(result) {
                if (result.success) {
                    saveStatus = "Lehrer-Notizen gespeichert"
                    console.log("Notes (staff) saved")
                } else {
                    saveStatus = "Fehler: " + result.error
                    saveError = true
                    console.log("Notes (staff) save error: " + result.error)
                }
            })
        }
    }
    
    function saveHomework() {
        var text = newHomeworkField.text.trim()
        var dueDate = homeworkDueDateField.text.trim()
        
        if (!text) {
            saveStatus = "Bitte Hausübungstext eingeben"
            saveError = true
            return
        }
        
        if (periodId) {
            saveStatus = "Speichere Hausübung..."
            saveError = false
            python.submitHomework(periodId, text, dueDate || null, "", function(result) {
                if (result.success) {
                    saveStatus = "Hausübung gespeichert"
                    newHomeworkField.text = ""
                    homeworkDueDateField.text = ""
                    console.log("Homework saved")
                    // Reload period data to show new homework
                    reloadPeriodData()
                } else {
                    saveStatus = "Fehler: " + result.error
                    saveError = true
                    console.log("Homework save error: " + result.error)
                }
            })
        }
    }
    
    function reloadPeriodData() {
        // Save classIds before reload (they come from lesson, not periodData)
        var savedClassIds = periodData ? periodData.classIds : []
        
        python.getPeriodData(periodId, function(result) {
            if (!result.error) {
                // Restore classIds
                result.classIds = savedClassIds
                periodData = result
            }
        })
    }
    
    Component.onCompleted: {
        // Prüfe Schreibberechtigung - NICHT absenceChecked!
        // absenceChecked bedeutet nur "Anwesenheit bereits geprüft", nicht "gesperrt"
        var canWrite = periodData && periodData.can && 
                       periodData.can.indexOf("WRITE_STUD_ABSENCE") !== -1
        
        if (!canWrite) {
            periodLocked = true
            console.log("ClassbookPage: Period is LOCKED (no WRITE_STUD_ABSENCE permission)")
        } else {
            periodLocked = false
            console.log("ClassbookPage: Period is WRITABLE (has WRITE_STUD_ABSENCE)")
        }
        
        // Load existing absences into map
        console.log("ClassbookPage loading - absences: " + 
                    (periodData && periodData.absences ? periodData.absences.length : 0))
        
        if (periodData && periodData.absences && periodData.absences.length > 0) {
            for (var i = 0; i < periodData.absences.length; i++) {
                var a = periodData.absences[i]
                console.log("Loading absence: studentId=" + a.studentId)
                absenceMap[a.studentId] = a
            }
            absenceMapChanged()
        }
        
        console.log("ClassbookPage loaded for period " + periodId + " with " + 
                    (periodData && periodData.students ? periodData.students.length : 0) + " students")
        
        // Debug: show first student
        if (periodData && periodData.students && periodData.students.length > 0) {
            var s = periodData.students[0]
            console.log("First student: studId=" + s.studId + ", name=" + s.lastName + " " + s.firstName)
        }
    }
}
