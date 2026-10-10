/**
 * WebUntis for MeeGo Harmattan PR1.3
 * Ported from Sailfish OS harbour-webuntis
 */

import QtQuick 1.1
import com.nokia.meego 1.1
import com.nokia.extras 1.1

PageStackWindow {
    id: appWindow
    showStatusBar: true
    showToolBar: false
    initialPage: loginPage
    
    // Global state
    property bool loggedIn: false
    property string username: ""
    property variant todayLessons: []
    property variant absenceReasons: []
    
    // Entity selection for timetable
    property string pendingEntityType: ""
    property int pendingEntityId: 0
    property string pendingEntityName: ""
    
    signal entitySelected(string entityType, int entityId, string entityName)
    
    Component.onCompleted: {
        console.log("=== WebUntis MeeGo Starting ===")
        
        // Connect backend signals
        backend.loginSuccess.connect(onLoginSuccess)
        backend.loginFailed.connect(onLoginFailed)
        backend.loggedOut.connect(onLoggedOut)
        
        // Try auto-login
        if (backend.autoLogin()) {
            console.log("Auto-login successful")
        }
    }
    
    function onLoginSuccess(user) {
        loggedIn = true
        username = user
        console.log("Login success: " + user)
        
        // Load absence reasons
        try {
            var reasons = JSON.parse(backend.getAbsenceReasons())
            absenceReasons = reasons
        } catch(e) {
            console.log("Error loading absence reasons: " + e)
        }
        
        pageStack.replace(timetablePage)
    }
    
    function onLoginFailed(error) {
        loggedIn = false
        showBanner("Login fehlgeschlagen: " + error)
    }
    
    function onLoggedOut() {
        loggedIn = false
        username = ""
        pageStack.replace(loginPage)
    }
    
    function showBanner(text) {
        infoBanner.text = text
        infoBanner.show()
    }
    
    // Info Banner for notifications
    InfoBanner {
        id: infoBanner
        topMargin: 40
    }
    
    // ==================== LOGIN PAGE ====================
    Component {
        id: loginPage
        
        Page {
            id: loginPageRoot
            orientationLock: PageOrientation.LockPortrait
            
            // Black background
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property bool isLoading: false
            property string errorMessage: ""
            property bool schoolSelected: false
            property string selectedSchoolName: ""
            property string selectedServer: ""
            property string selectedLoginName: ""
            property variant searchResults: []
            property string searchHint: ""   // Meldung der Suche, kein Fehler
            
            Component.onCompleted: {
                backend.schoolsFound.connect(onSchoolsFound)
                
                // Check if already logged in
                if (appWindow.loggedIn) {
                    pageStack.replace(timetablePage)
                }
            }
            
            function onSchoolsFound(resultJson) {
                isLoading = false
                try {
                    var result = JSON.parse(resultJson)
                    if (result.error) {
                        // "Zu viele Treffer" ist ein Hinweis beim Tippen,
                        // kein Fehler - darum nicht in Rot.
                        searchHint = result.error
                        searchResults = []
                    } else if (result.schools) {
                        searchHint = ""
                        searchResults = result.schools
                    }
                } catch(e) {
                    errorMessage = "Antwort nicht lesbar: " + e
                }
            }
            
            function searchSchool() {
                var query = schoolSearchField.text.trim()
                if (query.length < 3) return
                
                isLoading = true
                errorMessage = ""
                backend.searchSchools(query)
            }
            
            function useManualSchool() {
                errorMessage = ""
                var answer = backend.parseSchoolUrl(manualUrlField.text, manualSchoolField.text)
                var result
                try {
                    result = JSON.parse(answer)
                } catch(e) {
                    errorMessage = "Antwort nicht lesbar: " + e
                    return
                }
                if (result.error) {
                    errorMessage = result.error
                    return
                }
                selectedSchoolName = result.loginName
                selectedServer = result.server
                selectedLoginName = result.loginName
                schoolSelected = true
                searchResults = []
                searchHint = ""
            }
            
            function doLogin() {
                if (isLoading) return
                
                var secret = secretField.text.trim()
                if (secret.length < 16) {
                    errorMessage = "Secret muss mindestens 16 Zeichen haben"
                    return
                }
                
                isLoading = true
                errorMessage = ""
                
                backend.login(usernameField.text.trim(), secret, saveSwitch.checked)
                
                backend.loginFailed.connect(function(error) {
                    isLoading = false
                    errorMessage = error
                })
                
                backend.loginSuccess.connect(function(user) {
                    isLoading = false
                })
            }
            
            tools: ToolBarLayout {
                ToolIcon {
                    iconId: "toolbar-view-menu"
                    onClicked: loginMenu.open()
                }
            }
            
            Menu {
                id: loginMenu
                MenuLayout {
                    MenuItem {
                        text: "Über WebUntis"
                        onClicked: pageStack.push(aboutPage)
                    }
                    MenuItem {
                        text: "Andere Schule wählen"
                        visible: schoolSelected
                        onClicked: {
                            schoolSelected = false
                            searchHint = ""
                            selectedSchoolName = ""
                            searchResults = []
                            errorMessage = ""
                        }
                    }
                }
            }
            
            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: mainColumn.height
                clip: true
                
                Column {
                    id: mainColumn
                    width: parent.width
                    spacing: 16
                    
                    // Header
                    Label {
                        width: parent.width
                        text: schoolSelected ? "Anmelden" : "Schule suchen"
                        font.pixelSize: 40
                        font.bold: true
                        color: "#cccccc"
                    }
                    
                    Label {
                        width: parent.width
                        text: "Secret-Only Version"
                        font.pixelSize: 22
                        color: "#888888"
                    }
                    
                    Item { width: 1; height: 20 }
                    
                    // === SCHOOL SEARCH ===
                    Column {
                        width: parent.width
                        spacing: 16
                        visible: !schoolSelected
                        
                        // Icon placeholder
                        Image {
                            source: "/opt/webuntis/icons/webuntis.png"
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 80; height: 80
                            smooth: true
                        }
                        
                        Label {
                            width: parent.width
                            text: "WebUntis Klassenbuch"
                            font.pixelSize: 32
                            horizontalAlignment: Text.AlignHCenter
                            color: "#4da6ff"
                        }
                        
                        Label {
                            width: parent.width
                            text: "Für Microsoft 365 Schulen"
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            color: "#aaaaaa"
                        }
                        
                        Item { width: 1; height: 20 }
                        
                        TextField {
                            id: schoolSearchField
                            width: parent.width
                            placeholderText: "Schulname eingeben..."
                            
                            onTextChanged: {
                                if (text.trim().length >= 3) {
                                    searchTimer.restart()
                                } else {
                                    searchResults = []
                                    searchHint = ""
                                }
                            }
                            
                            Keys.onReturnPressed: searchSchool()
                        }
                        
                        Timer {
                            id: searchTimer
                            interval: 500
                            onTriggered: searchSchool()
                        }
                        
                        // Search Results
                        Repeater {
                            model: searchResults
                            
                            delegate: Rectangle {
                                width: mainColumn.width
                                height: schoolItemCol.height + 20
                                color: mouseArea.pressed ? "#2a2a2a" : "#1a1a1a"
                                radius: 8
                                
                                Column {
                                    id: schoolItemCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    
                                    Label {
                                        width: parent.width
                                        text: modelData.displayName
                                        font.pixelSize: 24
                                        color: "#ffffff"
                                        elide: Text.ElideRight
                                    }
                                    
                                    Label {
                                        width: parent.width
                                        text: modelData.address || ""
                                        font.pixelSize: 18
                                        color: "#aaaaaa"
                                        elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }
                                
                                MouseArea {
                                    id: mouseArea
                                    anchors.fill: parent
                                    onClicked: {
                                        selectedSchoolName = modelData.displayName
                                        selectedServer = modelData.server
                                        selectedLoginName = modelData.loginName
                                        
                                        backend.setSchool(selectedServer, selectedLoginName)
                                        schoolSelected = true
                                        searchResults = []
                                        errorMessage = ""
                                    }
                                }
                            }
                        }
                        
                        // Info text
                        Label {
                            width: parent.width
                            text: searchHint.length > 0
                                  ? searchHint
                                  : (schoolSearchField.text.trim().length >= 3 && searchResults.length === 0 && !isLoading
                                     ? "Keine Schulen gefunden"
                                     : "Gib mindestens 3 Zeichen ein")
                            font.pixelSize: 20
                            color: "#888888"
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: searchResults.length === 0
                        }
                        
                        // === Rueckfall: Adresse von Hand eintragen ===
                        Item { width: 1; height: 20 }
                        
                        Label {
                            width: parent.width
                            text: "Oder Adresse von Hand"
                            font.pixelSize: 24
                            color: "#4da6ff"
                        }
                        
                        Label {
                            width: parent.width
                            text: "Findet die Suche die Schule nicht, die WebUntis-Adresse aus dem Browser hier einsetzen."
                            font.pixelSize: 18
                            color: "#aaaaaa"
                            wrapMode: Text.WordWrap
                        }
                        
                        TextField {
                            id: manualUrlField
                            width: parent.width
                            placeholderText: "xyz.webuntis.com/WebUntis/?school=kennung"
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            Keys.onReturnPressed: manualSchoolField.focus = true
                        }
                        
                        TextField {
                            id: manualSchoolField
                            width: parent.width
                            placeholderText: "Schulkennung (nur wenn nicht in der Adresse)"
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            Keys.onReturnPressed: useManualSchool()
                        }
                        
                        Button {
                            text: "Übernehmen"
                            anchors.horizontalCenter: parent.horizontalCenter
                            enabled: !isLoading && manualUrlField.text.trim().length > 0
                            onClicked: useManualSchool()
                        }
                    }
                    
                    // === LOGIN FORM ===
                    Column {
                        width: parent.width
                        spacing: 16
                        visible: schoolSelected
                        
                        // Selected school info
                        Rectangle {
                            width: parent.width
                            height: schoolInfoCol.height + 24
                            color: "#1a2530"
                            radius: 8
                            
                            Column {
                                id: schoolInfoCol
                                anchors.centerIn: parent
                                width: parent.width - 24
                                spacing: 4
                                
                                Label {
                                    width: parent.width
                                    text: selectedSchoolName
                                    font.pixelSize: 24
                                    font.bold: true
                                    color: "#4da6ff"
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                                
                                Label {
                                    width: parent.width
                                    text: selectedServer
                                    font.pixelSize: 18
                                    color: "#aaaaaa"
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                        
                        Item { width: 1; height: 10 }
                        
                        Label {
                            text: "Benutzer (aus QR-Code)"
                            font.pixelSize: 20
                            color: "#aaaaaa"
                        }
                        
                        TextField {
                            id: usernameField
                            width: parent.width
                            placeholderText: "z.B. MATKO"
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            
                            Keys.onReturnPressed: secretField.focus = true
                        }
                        
                        Label {
                            text: "Secret / Schlüssel"
                            font.pixelSize: 20
                            color: "#aaaaaa"
                        }
                        
                        TextField {
                            id: secretField
                            width: parent.width
                            placeholderText: "16-stellig (aus QR-Code)"
                            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                            echoMode: TextInput.Password
                            
                            Keys.onReturnPressed: doLogin()
                        }
                        
                        Label {
                            width: parent.width
                            text: "Benutzer & Secret findest du im QR-Code:\nWebUntis → Profil → Freigaben → Anzeigen"
                            font.pixelSize: 18
                            color: "#888888"
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                        
                        Item { width: 1; height: 10 }
                        
                        Row {
                            spacing: 12
                            anchors.horizontalCenter: parent.horizontalCenter
                            
                            Switch {
                                id: saveSwitch
                                checked: true
                            }
                            
                            Label {
                                text: "Zugangsdaten speichern"
                                font.pixelSize: 22
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        
                        Item { width: 1; height: 20 }
                        
                        Button {
                            width: parent.width
                            text: isLoading ? "Verbinde..." : "Anmelden"
                            enabled: !isLoading && usernameField.text.length > 0 && secretField.text.length >= 16
                            onClicked: doLogin()
                        }
                    }
                    
                    // Error message
                    Label {
                        width: parent.width
                        text: errorMessage
                        font.pixelSize: 20
                        color: "#f44336"
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        visible: errorMessage.length > 0
                    }
                    
                    // Loading indicator
                    BusyIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: isLoading
                        visible: isLoading
                        platformStyle: BusyIndicatorStyle { size: "large" }
                    }
                }
            }
        }
    }
    
    // ==================== TIMETABLE PAGE ====================
    Component {
        id: timetablePage
        
        Page {
            id: timetablePageRoot
            orientationLock: PageOrientation.LockPortrait
            
            // Black background
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property bool isLoading: false
            property variant lessons: []
            property int selectedDate: 0
            property int weekOffset: 0
            property variant weekDates: []  // Array of YYYYMMDD for Mo-Fr
            property string viewingEntity: "own"  // "own", "CLASS", "TEACHER", "ROOM"
            property int viewingEntityId: 0
            property string viewingEntityName: ""
            
            Component.onCompleted: {
                backend.timetableReady.connect(onTimetableReady)
                appWindow.entitySelected.connect(onEntitySelected)
                calculateWeekDates()
                loadTimetable()
            }
            
            function onEntitySelected(entityType, entityId, entityName) {
                console.log("onEntitySelected: type=" + entityType + ", id=" + entityId + ", name=" + entityName)
                viewingEntity = entityType
                viewingEntityId = entityId
                viewingEntityName = entityName
                loadTimetable()
            }
            
            function calculateWeekDates() {
                var d = new Date()
                // Add weekOffset weeks
                d.setDate(d.getDate() + (weekOffset * 7))
                // Go to Monday of that week
                var day = d.getDay()
                var diff = d.getDate() - day + (day === 0 ? -6 : 1)
                d.setDate(diff)
                
                var dates = []
                for (var i = 0; i < 5; i++) {
                    var dateInt = d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate()
                    dates.push(dateInt)
                    d.setDate(d.getDate() + 1)
                }
                weekDates = dates
                
                // Select today if in this week, otherwise Monday
                var now = new Date()
                var today = now.getFullYear() * 10000 + (now.getMonth() + 1) * 100 + now.getDate()
                var found = false
                for (var j = 0; j < dates.length; j++) {
                    if (dates[j] === today) {
                        selectedDate = today
                        found = true
                        break
                    }
                }
                if (!found) {
                    selectedDate = dates[0]  // Monday
                }
            }
            
            function previousWeek() {
                weekOffset--
                calculateWeekDates()
                loadTimetable()
            }
            
            function nextWeek() {
                weekOffset++
                calculateWeekDates()
                loadTimetable()
            }
            
            function goToCurrentWeek() {
                weekOffset = 0
                calculateWeekDates()
                loadTimetable()
            }
            
            function viewOwnTimetable() {
                viewingEntity = "own"
                viewingEntityId = 0
                viewingEntityName = ""
                loadTimetable()
            }
            
            function viewEntityTimetable(entityType, entityId, entityName) {
                console.log("viewEntityTimetable: type=" + entityType + ", id=" + entityId + ", name=" + entityName)
                viewingEntity = entityType
                viewingEntityId = parseInt(entityId)
                viewingEntityName = entityName
                console.log("Set viewingEntityId to: " + viewingEntityId)
                loadTimetable()
            }
            
            function onTimetableReady(resultJson) {
                console.log("onTimetableReady called, length: " + resultJson.length)
                isLoading = false
                try {
                    var result = JSON.parse(resultJson)
                    console.log("Parsed result, has lessons: " + (result.lessons ? result.lessons.length : "no"))
                    if (result.error) {
                        console.log("Error: " + result.error)
                        appWindow.showBanner(result.error)
                        lessons = []
                    } else if (result.lessons) {
                        console.log("Total lessons: " + result.lessons.length + ", selectedDate: " + selectedDate)
                        if (result.lessons.length > 0) {
                            console.log("First lesson date: " + result.lessons[0].date)
                        }
                        // Filter for selected date
                        var filtered = []
                        for (var i = 0; i < result.lessons.length; i++) {
                            var lesson = result.lessons[i]
                            if (lesson.date === selectedDate) {
                                filtered.push(lesson)
                            }
                        }
                        console.log("Filtered lessons for date " + selectedDate + ": " + filtered.length)
                        // Sort by start time
                        filtered.sort(function(a, b) {
                            return a.startTime - b.startTime
                        })
                        lessons = filtered
                        console.log("Set lessons, count: " + lessons.length)
                    }
                } catch(e) {
                    console.log("Parse error: " + e)
                }
            }
            
            function loadTimetable() {
                isLoading = true
                
                if (weekDates.length < 5) {
                    calculateWeekDates()
                }
                
                // Convert first and last date to YYYY-MM-DD
                var startInt = weekDates[0]
                var endInt = weekDates[4]
                
                var startDate = Math.floor(startInt / 10000) + "-" + 
                               String(Math.floor((startInt % 10000) / 100)).replace(/^(\d)$/, "0$1") + "-" +
                               String(startInt % 100).replace(/^(\d)$/, "0$1")
                
                var endDate = Math.floor(endInt / 10000) + "-" + 
                             String(Math.floor((endInt % 10000) / 100)).replace(/^(\d)$/, "0$1") + "-" +
                             String(endInt % 100).replace(/^(\d)$/, "0$1")
                
                if (viewingEntity === "own") {
                    console.log("loadTimetable: own timetable")
                    backend.getTimetable(startDate, endDate)
                } else {
                    console.log("loadTimetable: entity=" + viewingEntity + ", id=" + viewingEntityId + ", dates=" + startDate + " to " + endDate)
                    backend.getTimetableFor(viewingEntity, viewingEntityId, startDate, endDate)
                }
            }
            
            function formatTime(t) {
                var h = Math.floor(t / 100)
                var m = t % 100
                return String(h).replace(/^(\d)$/, "0$1") + ":" + String(m).replace(/^(\d)$/, "0$1")
            }
            
            function formatDate(d) {
                var year = Math.floor(d / 10000)
                var month = Math.floor((d % 10000) / 100)
                var day = d % 100
                return day + "." + month + "." + year
            }
            
            function formatWeekRange() {
                if (weekDates.length < 5) return ""
                var mon = weekDates[0] % 100
                var monMonth = Math.floor((weekDates[0] % 10000) / 100)
                var fri = weekDates[4] % 100
                var friMonth = Math.floor((weekDates[4] % 10000) / 100)
                var year = Math.floor(weekDates[4] / 10000)
                if (monMonth === friMonth) {
                    return mon + ".-" + fri + "." + monMonth + "." + year
                } else {
                    return mon + "." + monMonth + ".-" + fri + "." + friMonth + "." + year
                }
            }
            
            function getDayName(idx) {
                var names = ["Mo", "Di", "Mi", "Do", "Fr"]
                return names[idx] || ""
            }
            
            function getDayNumber(dateInt) {
                return dateInt % 100
            }
            
            tools: ToolBarLayout {
                ToolIcon {
                    iconId: "toolbar-back"
                    visible: false
                }
                ToolIcon {
                    iconId: "toolbar-refresh"
                    onClicked: loadTimetable()
                }
                ToolIcon {
                    iconId: "toolbar-view-menu"
                    onClicked: timetableMenu.open()
                }
            }
            
            Menu {
                id: timetableMenu
                MenuLayout {
                    MenuItem {
                        text: "Mein Stundenplan"
                        onClicked: viewOwnTimetable()
                    }
                    MenuItem {
                        text: "Klassen..."
                        onClicked: pageStack.push(entitySelectPage, {entityType: "CLASS", title: "Klasse wählen"})
                    }
                    MenuItem {
                        text: "Lehrer/innen..."
                        onClicked: pageStack.push(entitySelectPage, {entityType: "TEACHER", title: "Lehrer/in wählen"})
                    }
                    MenuItem {
                        text: "Räume..."
                        onClicked: pageStack.push(entitySelectPage, {entityType: "ROOM", title: "Raum wählen"})
                    }
                    MenuItem {
                        text: "Abmelden"
                        onClicked: backend.logout()
                    }
                    MenuItem {
                        text: "Über WebUntis"
                        onClicked: pageStack.push(aboutPage)
                    }
                }
            }
            
            // Header
            Column {
                id: header
                width: parent.width
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 8
                
                // Title row with menu button
                Row {
                    width: parent.width
                    spacing: 12
                    
                    Label {
                        width: parent.width - 56
                        text: viewingEntity === "own" ? "Stundenplan" : viewingEntityName
                        font.pixelSize: 32
                        font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    // Menu button
                    Rectangle {
                        width: 44; height: 44
                        radius: 22
                        color: menuButtonMA.pressed ? "#333333" : "#222222"
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Label {
                            anchors.centerIn: parent
                            text: "☰"
                            font.pixelSize: 24
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: menuButtonMA
                            anchors.fill: parent
                            onClicked: timetableMenu.open()
                        }
                    }
                }
                
                // Subtitle showing entity type if viewing other
                Label {
                    text: {
                        if (viewingEntity === "CLASS") return "Klasse"
                        if (viewingEntity === "TEACHER") return "Lehrer/in"
                        if (viewingEntity === "ROOM") return "Raum"
                        return ""
                    }
                    font.pixelSize: 18
                    color: "#888888"
                    visible: viewingEntity !== "own"
                }
                
                // Back to own timetable button
                Rectangle {
                    width: parent.width
                    height: 40
                    radius: 8
                    color: backToOwnMA.pressed ? "#2a4a2a" : "#1a3a1a"
                    visible: viewingEntity !== "own"
                    
                    Label {
                        anchors.centerIn: parent
                        text: "← Zurück zu meinem Stundenplan"
                        font.pixelSize: 16
                        color: "#4caf50"
                    }
                    
                    MouseArea {
                        id: backToOwnMA
                        anchors.fill: parent
                        onClicked: viewOwnTimetable()
                    }
                }
                
                // Week navigation
                Row {
                    width: parent.width
                    spacing: 8
                    
                    // Previous week
                    Rectangle {
                        width: 44; height: 44
                        radius: 22
                        color: prevWeekMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "◀"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: prevWeekMA
                            anchors.fill: parent
                            onClicked: previousWeek()
                        }
                    }
                    
                    // Week range
                    Rectangle {
                        width: parent.width - 44 - 44 - 44 - 24
                        height: 44
                        radius: 8
                        color: weekOffset === 0 ? "#1a3a1a" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: formatWeekRange()
                            font.pixelSize: 18
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: goToCurrentWeek()
                        }
                    }
                    
                    // Next week
                    Rectangle {
                        width: 44; height: 44
                        radius: 22
                        color: nextWeekMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "▶"
                            font.pixelSize: 20
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: nextWeekMA
                            anchors.fill: parent
                            onClicked: nextWeek()
                        }
                    }
                    
                    // Today button
                    Rectangle {
                        width: 44; height: 44
                        radius: 22
                        color: todayMA.pressed ? "#333333" : "#222222"
                        visible: weekOffset !== 0
                        
                        Label {
                            anchors.centerIn: parent
                            text: "⌂"
                            font.pixelSize: 20
                            color: "#4da6ff"
                        }
                        
                        MouseArea {
                            id: todayMA
                            anchors.fill: parent
                            onClicked: goToCurrentWeek()
                        }
                    }
                }
                
                Item { width: 1; height: 4 }
                
                // Day selector
                Row {
                    width: parent.width
                    spacing: 6
                    
                    Repeater {
                        model: 5
                        
                        Rectangle {
                            width: (timetablePageRoot.width - 32 - 24) / 5
                            height: 56
                            radius: 8
                            color: weekDates[index] === selectedDate ? "#4da6ff" : "#2a2a2a"
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: 2
                                
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: getDayName(index)
                                    font.pixelSize: 14
                                    color: weekDates[index] === selectedDate ? "#ffffff" : "#aaaaaa"
                                }
                                
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: weekDates.length > index ? getDayNumber(weekDates[index]) : ""
                                    font.pixelSize: 22
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (weekDates.length > index) {
                                        selectedDate = weekDates[index]
                                        loadTimetable()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Lessons list
            ListView {
                id: lessonsList
                anchors.top: header.bottom
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                clip: true
                spacing: 12
                
                model: lessons
                
                delegate: Rectangle {
                    width: lessonsList.width
                    height: lessonCol.height + 24
                    radius: 12
                    color: {
                        var code = modelData.code || ""
                        if (code === "cancelled") return "#2a1515"
                        if (code === "irregular") return "#2a2510"
                        return "#1a1a1a"
                    }
                    border.width: 1
                    border.color: {
                        var code = modelData.code || ""
                        if (code === "cancelled") return "#f44336"
                        if (code === "irregular") return "#ff9800"
                        return "#2a2a2a"
                    }
                    
                    Column {
                        id: lessonCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        
                        Row {
                            width: parent.width
                            spacing: 12
                            
                            // Time
                            Column {
                                width: 60
                                
                                Label {
                                    text: formatTime(modelData.startTime)
                                    font.pixelSize: 22
                                    font.bold: true
                                    color: "#ffffff"
                                }
                                
                                Label {
                                    text: formatTime(modelData.endTime)
                                    font.pixelSize: 18
                                    color: "#aaaaaa"
                                }
                            }
                            
                            // Separator
                            Rectangle {
                                width: 4
                                height: parent.height
                                radius: 2
                                color: "#4da6ff"
                            }
                            
                            // Content
                            Column {
                                width: parent.width - 80
                                spacing: 4
                                
                                Label {
                                    width: parent.width
                                    text: {
                                        // Try different sources for subject name
                                        if (modelData.subjects && modelData.subjects.length > 0) {
                                            return modelData.subjects.join(", ")
                                        }
                                        return modelData.subjectLongName || modelData.subjectName || modelData.activityType || "Stunde"
                                    }
                                    font.pixelSize: 24
                                    font.bold: true
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                }
                                
                                Label {
                                    width: parent.width
                                    text: {
                                        var parts = []
                                        // Classes
                                        if (modelData.classes && modelData.classes.length > 0) {
                                            parts.push(modelData.classes.join(", "))
                                        } else if (modelData.className) {
                                            parts.push(modelData.className)
                                        }
                                        // Rooms
                                        if (modelData.rooms && modelData.rooms.length > 0) {
                                            parts.push(modelData.rooms.join(", "))
                                        } else if (modelData.roomName) {
                                            parts.push(modelData.roomName)
                                        }
                                        return parts.join(" • ")
                                    }
                                    font.pixelSize: 18
                                    color: "#aaaaaa"
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                                
                                // Status badge
                                Rectangle {
                                    visible: modelData.code === "cancelled"
                                    width: cancelledLabel.width + 16
                                    height: 24
                                    radius: 12
                                    color: "#f44336"
                                    
                                    Label {
                                        id: cancelledLabel
                                        anchors.centerIn: parent
                                        text: "Entfall"
                                        font.pixelSize: 16
                                        color: "#ffffff"
                                    }
                                }
                            }
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            pageStack.push(periodDetailPage, {periodId: modelData.id, periodData: modelData})
                        }
                    }
                }
            }
            
            // Empty state
            Label {
                anchors.centerIn: parent
                text: "Keine Stunden"
                font.pixelSize: 28
                color: "#888888"
                visible: !isLoading && lessons.length === 0
            }
            
            // Loading
            BusyIndicator {
                anchors.centerIn: parent
                running: isLoading
                visible: isLoading
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
        }
    }
    
    // ==================== PERIOD DETAIL PAGE ====================
    Component {
        id: periodDetailPage
        
        Page {
            id: periodDetailRoot
            orientationLock: PageOrientation.LockPortrait
            
            // Black background
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property int periodId: 0
            property variant periodData: null
            property variant detailData: null
            property bool isLoading: false
            property string saveStatus: ""
            property bool topicEditing: false
            
            Component.onCompleted: {
                backend.periodDataReady.connect(onPeriodDataReady)
                backend.operationResult.connect(onOperationResult)
                loadPeriodData()
            }
            
            function onPeriodDataReady(resultJson) {
                isLoading = false
                try {
                    var result = JSON.parse(resultJson)
                    if (result.error) {
                        appWindow.showBanner(result.error)
                    } else {
                        detailData = result
                        // Set topic field
                        if (result.topic && (result.topic.text || result.topic.lessonText)) {
                            topicField.text = result.topic.text || result.topic.lessonText
                        }
                    }
                } catch(e) {
                    console.log("Parse error: " + e)
                }
            }
            
            function onOperationResult(resultJson) {
                try {
                    var result = JSON.parse(resultJson)
                    if (result.success) {
                        saveStatus = "Gespeichert"
                        loadPeriodData()
                    } else {
                        saveStatus = "Fehler: " + (result.error || "")
                    }
                } catch(e) {}
            }
            
            function loadPeriodData() {
                isLoading = true
                backend.getPeriodData(periodId)
            }
            
            function formatTime(t) {
                var h = Math.floor(t / 100)
                var m = t % 100
                return String(h).replace(/^(\d)$/, "0$1") + ":" + String(m).replace(/^(\d)$/, "0$1")
            }
            
            function isStudentAbsent(studentId) {
                if (!detailData || !detailData.absences) return false
                for (var i = 0; i < detailData.absences.length; i++) {
                    if (detailData.absences[i].studentId === studentId) return true
                }
                return false
            }
            
            function getAbsenceId(studentId) {
                if (!detailData || !detailData.absences) return 0
                for (var i = 0; i < detailData.absences.length; i++) {
                    if (detailData.absences[i].studentId === studentId) {
                        return detailData.absences[i].id
                    }
                }
                return 0
            }
            
            function toggleAbsence(studentId) {
                if (isStudentAbsent(studentId)) {
                    var absId = getAbsenceId(studentId)
                    if (absId) {
                        saveStatus = "Lösche Abwesenheit..."
                        backend.deleteAbsence(absId)
                    }
                } else {
                    saveStatus = "Erstelle Abwesenheit..."
                    backend.createAbsence(periodId, studentId, 0, "")
                }
            }
            
            function saveTopic() {
                console.log("saveTopic called, periodId: " + periodId + ", text: " + topicField.text)
                if (periodId > 0) {
                    saveStatus = "Speichere Thema..."
                    backend.submitTopic(periodId, topicField.text)
                    topicEditing = false
                } else {
                    console.log("ERROR: periodId is invalid: " + periodId)
                    saveStatus = "Fehler: Keine Period ID"
                }
            }
            
            tools: ToolBarLayout {
                ToolIcon {
                    iconId: "toolbar-back"
                    onClicked: pageStack.pop()
                }
                ToolIcon {
                    iconId: "toolbar-refresh"
                    onClicked: loadPeriodData()
                }
                ToolIcon {
                    iconId: "toolbar-view-menu"
                    onClicked: detailMenu.open()
                }
            }
            
            Menu {
                id: detailMenu
                MenuLayout {
                    MenuItem {
                        text: "Thema bearbeiten"
                        onClicked: {
                            // Copy existing text to edit field
                            if (detailData && detailData.topic) {
                                topicField.text = detailData.topic.text || detailData.topic.lessonText || ""
                            } else {
                                topicField.text = ""
                            }
                            topicEditing = true
                        }
                    }
                    MenuItem {
                        text: "Alle anwesend"
                        onClicked: {
                            // Delete all absences
                            if (detailData && detailData.absences) {
                                for (var i = 0; i < detailData.absences.length; i++) {
                                    backend.deleteAbsence(detailData.absences[i].id)
                                }
                            }
                        }
                    }
                }
            }
            
            // Top header with back button
            Rectangle {
                id: headerBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56
                color: "#111111"
                z: 10
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 12
                    
                    // Back button
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: backMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: backMA
                            anchors.fill: parent
                            onClicked: pageStack.pop()
                        }
                    }
                    
                    // Title
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: periodData ? (periodData.subjects ? periodData.subjects.join(", ") : "Stunde") : "Stunde"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                        width: parent.width - 120
                    }
                    
                    // Refresh button
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: refreshMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "↻"
                            font.pixelSize: 24
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: refreshMA
                            anchors.fill: parent
                            onClicked: loadPeriodData()
                        }
                    }
                }
            }
            
            Flickable {
                anchors.top: headerBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                contentHeight: detailColumn.height
                clip: true
                
                Column {
                    id: detailColumn
                    width: parent.width
                    spacing: 16
                    
                    // Header
                    Label {
                        text: periodData ? (periodData.subjectLongName || periodData.subjectName || periodData.subjects.join(", ") || "Stunde") : "Stunde"
                        font.pixelSize: 32
                        font.bold: true
                        color: "#ffffff"
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                    
                    Label {
                        text: periodData ? (formatTime(periodData.startTime) + " - " + formatTime(periodData.endTime)) : ""
                        font.pixelSize: 22
                        color: "#aaaaaa"
                    }
                    
                    // Class & Room badges
                    Row {
                        spacing: 12
                        
                        Rectangle {
                            width: classLabel.width + 20
                            height: 28
                            radius: 14
                            color: "#1a2530"
                            visible: periodData && periodData.classes && periodData.classes.length > 0
                            
                            Label {
                                id: classLabel
                                anchors.centerIn: parent
                                text: periodData && periodData.classes ? periodData.classes.join(", ") : ""
                                font.pixelSize: 16
                                color: "#4da6ff"
                            }
                        }
                        
                        Rectangle {
                            width: roomLabel.width + 20
                            height: 28
                            radius: 14
                            color: "#2a1a2a"
                            visible: periodData && periodData.rooms && periodData.rooms.length > 0
                            
                            Label {
                                id: roomLabel
                                anchors.centerIn: parent
                                text: periodData && periodData.rooms ? periodData.rooms.join(", ") : ""
                                font.pixelSize: 16
                                color: "#ba68c8"
                            }
                        }
                    }
                    
                    // Save status
                    Label {
                        text: saveStatus
                        font.pixelSize: 16
                        color: saveStatus.indexOf("Fehler") >= 0 ? "#f44336" : "#4caf50"
                        visible: saveStatus.length > 0
                    }
                    
                    Item { width: 1; height: 8 }
                    
                    // ===== TOPIC SECTION =====
                    Label {
                        text: "Stundenthema"
                        font.pixelSize: 22
                        font.bold: true
                        color: "#ffffff"
                    }
                    
                    // Display mode
                    Rectangle {
                        width: parent.width
                        height: topicDisplay.height + 20
                        radius: 8
                        color: "#1a1a1a"
                        visible: !topicEditing
                        
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                // Copy existing text to edit field
                                if (detailData && detailData.topic) {
                                    topicField.text = detailData.topic.text || detailData.topic.lessonText || ""
                                } else {
                                    topicField.text = ""
                                }
                                topicEditing = true
                            }
                        }
                        
                        Label {
                            id: topicDisplay
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (detailData && detailData.topic) {
                                    return detailData.topic.text || detailData.topic.lessonText || "(tippen zum Bearbeiten)"
                                }
                                return "(tippen zum Bearbeiten)"
                            }
                            font.pixelSize: 18
                            color: detailData && detailData.topic && (detailData.topic.text || detailData.topic.lessonText) ? "#ffffff" : "#666666"
                            wrapMode: Text.WordWrap
                        }
                    }
                    
                    // Edit mode
                    Column {
                        width: parent.width
                        spacing: 8
                        visible: topicEditing
                        
                        TextArea {
                            id: topicField
                            width: parent.width
                            height: 120
                            placeholderText: "Stundenthema eingeben..."
                        }
                        
                        Row {
                            spacing: 12
                            
                            Button {
                                text: "Speichern"
                                onClicked: saveTopic()
                            }
                            
                            Button {
                                text: "Abbrechen"
                                onClicked: topicEditing = false
                            }
                        }
                    }
                    
                    Item { width: 1; height: 16 }
                    
                    // ===== STUDENTS SECTION =====
                    Label {
                        text: "Schüler/innen (" + (detailData && detailData.students ? detailData.students.length : 0) + ")"
                        font.pixelSize: 22
                        font.bold: true
                        color: "#ffffff"
                        visible: detailData ? (detailData.students ? detailData.students.length > 0 : false) : false
                    }
                    
                    Label {
                        text: "Tippen zum Umschalten der Anwesenheit"
                        font.pixelSize: 14
                        color: "#666666"
                        visible: detailData ? (detailData.students ? detailData.students.length > 0 : false) : false
                    }
                    
                    Repeater {
                        model: detailData && detailData.students ? detailData.students : []
                        
                        Rectangle {
                            id: studentItem
                            width: detailColumn.width
                            height: 72
                            radius: 8
                            color: isStudentAbsent(modelData.studId) ? "#2a1515" : "#1a1a1a"
                            
                            property string avatarPath: backend.getAvatarPath(modelData.studId)
                            property bool hasAvatar: avatarPath.length > 0
                            
                            Component.onCompleted: {
                                // Load avatar if URL available and not cached
                                if (!hasAvatar && modelData.imageUrl && modelData.imageUrl.length > 0) {
                                    backend.fetchAvatar(modelData.studId, modelData.imageUrl)
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: toggleAbsence(modelData.studId)
                            }
                            
                            // Avatar - full height
                            Rectangle {
                                id: avatarRect
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 8
                                width: 56; height: 56
                                radius: 6
                                color: studentItem.hasAvatar ? "transparent" : "#333333"
                                clip: true
                                
                                Image {
                                    anchors.fill: parent
                                    source: studentItem.avatarPath
                                    visible: studentItem.hasAvatar
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                }
                                
                                // Fallback: Initials
                                Label {
                                    anchors.centerIn: parent
                                    text: {
                                        var fn = modelData.firstName || ""
                                        var ln = modelData.lastName || ""
                                        return (ln.length > 0 ? ln[0] : "") + (fn.length > 0 ? fn[0] : "")
                                    }
                                    font.pixelSize: 20
                                    font.bold: true
                                    color: "#888888"
                                    visible: !studentItem.hasAvatar
                                }
                            }
                            
                            // Status indicator on right
                            Rectangle {
                                id: statusRect
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 8
                                width: 32; height: 32
                                radius: 16
                                color: isStudentAbsent(modelData.studId) ? "#f44336" : "#4caf50"
                                
                                Label {
                                    anchors.centerIn: parent
                                    text: isStudentAbsent(modelData.studId) ? "✗" : "✓"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }
                            
                            // Name and status in middle
                            Column {
                                anchors.left: avatarRect.right
                                anchors.right: statusRect.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 2
                                
                                Label {
                                    text: (modelData.lastName || "") + " " + (modelData.firstName || "")
                                    font.pixelSize: 20
                                    color: "#ffffff"
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                
                                Label {
                                    text: isStudentAbsent(modelData.studId) ? "Abwesend" : "Anwesend"
                                    font.pixelSize: 16
                                    color: isStudentAbsent(modelData.studId) ? "#f44336" : "#4caf50"
                                }
                            }
                        }
                    }
                    
                    // No students
                    Label {
                        width: parent.width
                        text: isLoading ? "Lade..." : "Keine Schülerdaten"
                        font.pixelSize: 18
                        color: "#666666"
                        horizontalAlignment: Text.AlignHCenter
                        visible: !detailData || !detailData.students || detailData.students.length === 0
                    }
                    
                    Item { width: 1; height: 24 }
                    
                    // ===== NAVIGATION BUTTONS =====
                    Label {
                        text: "Weitere Optionen"
                        font.pixelSize: 22
                        font.bold: true
                        color: "#ffffff"
                    }
                    
                    // Notes button
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 8
                        color: notesMA.pressed ? "#2a2a3a" : "#1a1a2a"
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12
                            
                            Label {
                                text: "📝"
                                font.pixelSize: 24
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                
                                Label {
                                    text: "Notizen"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#ffffff"
                                }
                                
                                Label {
                                    text: "Für Lehrkräfte & Schüler/innen"
                                    font.pixelSize: 14
                                    color: "#888888"
                                }
                            }
                            
                            Label {
                                text: "›"
                                font.pixelSize: 28
                                color: "#666666"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        
                        MouseArea {
                            id: notesMA
                            anchors.fill: parent
                            onClicked: pageStack.push(notesSubPage, {periodId: periodId, periodData: periodData})
                        }
                    }
                    
                    // Homework button
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 8
                        color: homeworkMA.pressed ? "#2a3a2a" : "#1a2a1a"
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12
                            
                            Label {
                                text: "📚"
                                font.pixelSize: 24
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                
                                Label {
                                    text: "Hausübungen"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#ffffff"
                                }
                                
                                Label {
                                    text: "Aufgaben verwalten"
                                    font.pixelSize: 14
                                    color: "#888888"
                                }
                            }
                        }
                        
                        MouseArea {
                            id: homeworkMA
                            anchors.fill: parent
                            onClicked: pageStack.push(homeworkSubPage, {periodId: periodId, periodData: periodData})
                        }
                    }
                    
                    // Class register button
                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 8
                        color: classRegMA.pressed ? "#3a2a2a" : "#2a1a1a"
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 12
                            
                            Label {
                                text: "📋"
                                font.pixelSize: 24
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                
                                Label {
                                    text: "Klassenbucheinträge"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#ffffff"
                                }
                                
                                Label {
                                    text: "Einträge erstellen & anzeigen"
                                    font.pixelSize: 14
                                    color: "#888888"
                                }
                            }
                        }
                        
                        MouseArea {
                            id: classRegMA
                            anchors.fill: parent
                            onClicked: pageStack.push(classRegSubPage, {periodId: periodId, periodData: periodData, students: detailData ? detailData.students : []})
                        }
                    }
                    
                    Item { width: 1; height: 40 }
                }
            }
            
            // Loading
            BusyIndicator {
                anchors.centerIn: parent
                running: isLoading
                visible: isLoading
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
        }
    }
    
    // ==================== NOTES SUB PAGE ====================
    Component {
        id: notesSubPage
        
        Page {
            id: notesRoot
            orientationLock: PageOrientation.LockPortrait
            
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property int periodId: 0
            property variant periodData: null
            property bool isLoading: true
            property variant notesData: null
            property bool editingStaff: false
            property bool editingAll: false
            
            Component.onCompleted: {
                backend.notesDataReady.connect(onNotesDataReady)
                backend.operationResult.connect(onOperationResult)
                loadNotes()
            }
            
            function loadNotes() {
                isLoading = true
                backend.getNotesData(periodId)
            }
            
            function onNotesDataReady(resultJson) {
                isLoading = false
                try {
                    notesData = JSON.parse(resultJson)
                } catch(e) {
                    console.log("Parse error: " + e)
                }
            }
            
            function onOperationResult(resultJson) {
                try {
                    var result = JSON.parse(resultJson)
                    if (result.success) {
                        appWindow.showBanner("Gespeichert")
                        loadNotes()
                    } else {
                        appWindow.showBanner("Fehler: " + (result.error || ""))
                    }
                } catch(e) {}
                editingStaff = false
                editingAll = false
            }
            
            // Header
            Rectangle {
                id: notesHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56
                color: "#111111"
                z: 10
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 12
                    
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: notesBackMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: notesBackMA
                            anchors.fill: parent
                            onClicked: pageStack.pop()
                        }
                    }
                    
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notizen"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#ffffff"
                    }
                }
            }
            
            Flickable {
                anchors.top: notesHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                contentHeight: notesColumn.height
                clip: true
                
                Column {
                    id: notesColumn
                    width: parent.width
                    spacing: 20
                    
                    // Staff notes
                    Label {
                        text: "Notizen für Lehrkräfte"
                        font.pixelSize: 20
                        font.bold: true
                        color: "#ff9800"
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: editingStaff ? 160 : (staffNotesLabel.height + 24)
                        radius: 8
                        color: "#1a1a1a"
                        border.width: 1
                        border.color: "#ff9800"
                        
                        Label {
                            id: staffNotesLabel
                            anchors.fill: parent
                            anchors.margins: 12
                            text: notesData && notesData.staffInfo ? notesData.staffInfo : "(keine Notizen)"
                            font.pixelSize: 16
                            color: notesData && notesData.staffInfo ? "#ffffff" : "#666666"
                            wrapMode: Text.WordWrap
                            visible: !editingStaff
                        }
                        
                        TextArea {
                            id: staffNotesField
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: editingStaff
                            text: notesData && notesData.staffInfo ? notesData.staffInfo : ""
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            visible: !editingStaff
                            onClicked: {
                                staffNotesField.text = notesData && notesData.staffInfo ? notesData.staffInfo : ""
                                editingStaff = true
                            }
                        }
                    }
                    
                    Row {
                        spacing: 12
                        visible: editingStaff
                        
                        Button {
                            text: "Speichern"
                            onClicked: backend.submitPeriodInfo(periodId, "notesStaff", staffNotesField.text)
                        }
                        
                        Button {
                            text: "Abbrechen"
                            onClicked: editingStaff = false
                        }
                    }
                    
                    Item { width: 1; height: 16 }
                    
                    // All notes
                    Label {
                        text: "Notizen für alle"
                        font.pixelSize: 20
                        font.bold: true
                        color: "#4caf50"
                    }
                    
                    Rectangle {
                        width: parent.width
                        height: editingAll ? 160 : (allNotesLabel.height + 24)
                        radius: 8
                        color: "#1a1a1a"
                        border.width: 1
                        border.color: "#4caf50"
                        
                        Label {
                            id: allNotesLabel
                            anchors.fill: parent
                            anchors.margins: 12
                            text: notesData && notesData.info ? notesData.info : "(keine Notizen)"
                            font.pixelSize: 16
                            color: notesData && notesData.info ? "#ffffff" : "#666666"
                            wrapMode: Text.WordWrap
                            visible: !editingAll
                        }
                        
                        TextArea {
                            id: allNotesField
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: editingAll
                            text: notesData && notesData.info ? notesData.info : ""
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            visible: !editingAll
                            onClicked: {
                                allNotesField.text = notesData && notesData.info ? notesData.info : ""
                                editingAll = true
                            }
                        }
                    }
                    
                    Row {
                        spacing: 12
                        visible: editingAll
                        
                        Button {
                            text: "Speichern"
                            onClicked: backend.submitPeriodInfo(periodId, "notesAll", allNotesField.text)
                        }
                        
                        Button {
                            text: "Abbrechen"
                            onClicked: editingAll = false
                        }
                    }
                    
                    Item { width: 1; height: 40 }
                }
            }
            
            BusyIndicator {
                anchors.centerIn: parent
                running: isLoading
                visible: isLoading
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
        }
    }
    
    // ==================== HOMEWORK SUB PAGE ====================
    Component {
        id: homeworkSubPage
        
        Page {
            id: homeworkRoot
            orientationLock: PageOrientation.LockPortrait
            
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property int periodId: 0
            property variant periodData: null
            property bool isLoading: true
            property variant homeworkList: []
            property bool addingNew: false
            
            Component.onCompleted: {
                backend.homeworkDataReady.connect(onHomeworkDataReady)
                backend.operationResult.connect(onOperationResult)
                loadHomework()
            }
            
            function loadHomework() {
                isLoading = true
                backend.getHomeworkData(periodId)
            }
            
            function onHomeworkDataReady(resultJson) {
                isLoading = false
                try {
                    var result = JSON.parse(resultJson)
                    homeworkList = result.homework || []
                } catch(e) {
                    console.log("Parse error: " + e)
                }
            }
            
            function onOperationResult(resultJson) {
                try {
                    var result = JSON.parse(resultJson)
                    if (result.success) {
                        appWindow.showBanner("Gespeichert")
                        loadHomework()
                    } else {
                        appWindow.showBanner("Fehler: " + (result.error || ""))
                    }
                } catch(e) {}
                addingNew = false
            }
            
            // Header
            Rectangle {
                id: homeworkHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56
                color: "#111111"
                z: 10
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 12
                    
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: hwBackMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: hwBackMA
                            anchors.fill: parent
                            onClicked: pageStack.pop()
                        }
                    }
                    
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Hausübungen"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#ffffff"
                        width: parent.width - 120
                    }
                    
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: hwAddMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 28
                            color: "#4caf50"
                        }
                        
                        MouseArea {
                            id: hwAddMA
                            anchors.fill: parent
                            onClicked: addingNew = true
                        }
                    }
                }
            }
            
            Flickable {
                anchors.top: homeworkHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                contentHeight: homeworkColumn.height
                clip: true
                
                Column {
                    id: homeworkColumn
                    width: parent.width
                    spacing: 12
                    
                    // Add new homework form
                    Rectangle {
                        width: parent.width
                        height: newHwColumn.height + 24
                        radius: 8
                        color: "#1a2a1a"
                        border.width: 1
                        border.color: "#4caf50"
                        visible: addingNew
                        
                        Column {
                            id: newHwColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            
                            Label {
                                text: "Neue Hausübung"
                                font.pixelSize: 18
                                font.bold: true
                                color: "#4caf50"
                            }
                            
                            TextArea {
                                id: newHwText
                                width: parent.width
                                height: 80
                                placeholderText: "Aufgabenstellung..."
                            }
                            
                            Row {
                                spacing: 12
                                
                                Button {
                                    text: "Speichern"
                                    onClicked: {
                                        if (newHwText.text.length > 0) {
                                            backend.submitHomework(periodId, newHwText.text, "", "", 0)
                                            newHwText.text = ""
                                        }
                                    }
                                }
                                
                                Button {
                                    text: "Abbrechen"
                                    onClicked: {
                                        addingNew = false
                                        newHwText.text = ""
                                    }
                                }
                            }
                        }
                    }
                    
                    // Existing homework
                    Repeater {
                        model: homeworkList
                        
                        Rectangle {
                            width: parent.width
                            height: hwItemCol.height + 20
                            radius: 8
                            color: "#1a1a1a"
                            
                            Column {
                                id: hwItemCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Label {
                                    width: parent.width
                                    text: modelData.text || ""
                                    font.pixelSize: 18
                                    color: "#ffffff"
                                    wrapMode: Text.WordWrap
                                }
                                
                                Label {
                                    text: modelData.dueDate ? "Fällig: " + modelData.dueDate : ""
                                    font.pixelSize: 14
                                    color: "#ff9800"
                                    visible: modelData.dueDate
                                }
                                
                                Label {
                                    text: modelData.remark || ""
                                    font.pixelSize: 14
                                    color: "#888888"
                                    visible: modelData.remark
                                }
                            }
                        }
                    }
                    
                    // Empty state
                    Label {
                        width: parent.width
                        text: "Keine Hausübungen"
                        font.pixelSize: 18
                        color: "#666666"
                        horizontalAlignment: Text.AlignHCenter
                        visible: !isLoading && homeworkList.length === 0 && !addingNew
                    }
                    
                    Item { width: 1; height: 40 }
                }
            }
            
            BusyIndicator {
                anchors.centerIn: parent
                running: isLoading
                visible: isLoading
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
        }
    }
    
    // ==================== CLASS REGISTER SUB PAGE ====================
    Component {
        id: classRegSubPage
        
        Page {
            id: classRegRoot
            orientationLock: PageOrientation.LockPortrait
            
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property int periodId: 0
            property variant periodData: null
            property variant students: []
            property bool isLoading: true
            property variant entries: []
            property variant eventReasons: []
            property bool addingNew: false
            property variant selectedStudentIds: []
            property int selectedReasonId: -1
            
            Component.onCompleted: {
                backend.classRegDataReady.connect(onClassRegDataReady)
                backend.operationResult.connect(onOperationResult)
                loadClassRegData()
            }
            
            function loadClassRegData() {
                isLoading = true
                backend.getClassRegData(periodId)
            }
            
            function onClassRegDataReady(resultJson) {
                isLoading = false
                try {
                    var result = JSON.parse(resultJson)
                    entries = result.events || []
                    eventReasons = result.eventReasons || []
                } catch(e) {
                    console.log("Parse error: " + e)
                }
            }
            
            function onOperationResult(resultJson) {
                try {
                    var result = JSON.parse(resultJson)
                    if (result.success) {
                        appWindow.showBanner("Gespeichert")
                        loadClassRegData()
                    } else {
                        appWindow.showBanner("Fehler: " + (result.error || ""))
                    }
                } catch(e) {}
                addingNew = false
                selectedStudentIds = []
                selectedReasonId = -1
            }
            
            function isStudentSelected(studentId) {
                for (var i = 0; i < selectedStudentIds.length; i++) {
                    if (selectedStudentIds[i] === studentId) return true
                }
                return false
            }
            
            function toggleStudent(studentId) {
                var newList = []
                var found = false
                for (var i = 0; i < selectedStudentIds.length; i++) {
                    if (selectedStudentIds[i] === studentId) {
                        found = true
                    } else {
                        newList.push(selectedStudentIds[i])
                    }
                }
                if (!found) newList.push(studentId)
                selectedStudentIds = newList
            }
            
            // Header
            Rectangle {
                id: classRegHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56
                color: "#111111"
                z: 10
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 12
                    
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: crBackMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: crBackMA
                            anchors.fill: parent
                            onClicked: pageStack.pop()
                        }
                    }
                    
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Klassenbuch"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#ffffff"
                        width: parent.width - 120
                    }
                    
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: crAddMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 28
                            color: "#f44336"
                        }
                        
                        MouseArea {
                            id: crAddMA
                            anchors.fill: parent
                            onClicked: addingNew = true
                        }
                    }
                }
            }
            
            Flickable {
                anchors.top: classRegHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                contentHeight: classRegColumn.height
                clip: true
                
                Column {
                    id: classRegColumn
                    width: parent.width
                    spacing: 12
                    
                    // Add new entry form
                    Rectangle {
                        width: parent.width
                        height: newEntryColumn.height + 24
                        radius: 8
                        color: "#2a1a1a"
                        border.width: 1
                        border.color: "#f44336"
                        visible: addingNew
                        
                        Column {
                            id: newEntryColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 12
                            anchors.top: parent.top
                            anchors.topMargin: 12
                            spacing: 12
                            
                            Label {
                                text: "Neuer Eintrag"
                                font.pixelSize: 18
                                font.bold: true
                                color: "#f44336"
                            }
                            
                            TextArea {
                                id: newEntryText
                                width: parent.width
                                height: 80
                                placeholderText: "Eintrag..."
                            }
                            
                            // Reason selection
                            Label {
                                text: "Grund (optional)"
                                font.pixelSize: 14
                                color: "#aaaaaa"
                            }
                            
                            Flow {
                                width: parent.width
                                spacing: 6
                                
                                Repeater {
                                    model: eventReasons
                                    
                                    Rectangle {
                                        width: reasonLbl.width + 16
                                        height: 32
                                        radius: 16
                                        color: selectedReasonId === modelData.id ? "#4da6ff" : "#333333"
                                        
                                        Label {
                                            id: reasonLbl
                                            anchors.centerIn: parent
                                            text: modelData.name || modelData.longName || ""
                                            font.pixelSize: 12
                                            color: "#ffffff"
                                        }
                                        
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (selectedReasonId === modelData.id) {
                                                    selectedReasonId = -1
                                                } else {
                                                    selectedReasonId = modelData.id
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            // Student selection
                            Label {
                                text: "Schüler/innen (optional)"
                                font.pixelSize: 14
                                color: "#aaaaaa"
                            }
                            
                            Column {
                                width: parent.width
                                spacing: 4
                                
                                Repeater {
                                    model: students
                                    
                                    Rectangle {
                                        width: parent.width
                                        height: 40
                                        radius: 6
                                        color: isStudentSelected(modelData.studId) ? "#2a3a4a" : "#1a1a1a"
                                        
                                        Row {
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 8
                                            
                                            Rectangle {
                                                width: 20; height: 20
                                                radius: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: isStudentSelected(modelData.studId) ? "#4da6ff" : "#333333"
                                                
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "✓"
                                                    font.pixelSize: 12
                                                    color: "#ffffff"
                                                    visible: isStudentSelected(modelData.studId)
                                                }
                                            }
                                            
                                            Label {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: (modelData.lastName || "") + " " + (modelData.firstName || "")
                                                font.pixelSize: 14
                                                color: "#ffffff"
                                            }
                                        }
                                        
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: toggleStudent(modelData.studId)
                                        }
                                    }
                                }
                            }
                            
                            Row {
                                spacing: 12
                                
                                Button {
                                    text: "Speichern"
                                    onClicked: {
                                        if (newEntryText.text.length > 0) {
                                            var ids = selectedStudentIds.length > 0 ? selectedStudentIds.join(",") : "0"
                                            backend.submitClassRegEvent(periodId, ids, selectedReasonId, newEntryText.text, "STUDENT")
                                            newEntryText.text = ""
                                        } else {
                                            appWindow.showBanner("Bitte Text eingeben")
                                        }
                                    }
                                }
                                
                                Button {
                                    text: "Abbrechen"
                                    onClicked: {
                                        addingNew = false
                                        newEntryText.text = ""
                                        selectedStudentIds = []
                                        selectedReasonId = -1
                                    }
                                }
                            }
                        }
                    }
                    
                    // Existing entries
                    Repeater {
                        model: entries
                        
                        Rectangle {
                            width: parent.width
                            height: entryItemCol.height + 16
                            radius: 8
                            color: "#1a1a2a"
                            border.width: 1
                            border.color: "#3a3a5a"
                            
                            Column {
                                id: entryItemCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                
                                Label {
                                    width: parent.width
                                    text: modelData.text || ""
                                    font.pixelSize: 16
                                    color: "#ffffff"
                                    wrapMode: Text.WordWrap
                                }
                                
                                Label {
                                    text: (modelData.reasonName || modelData.categoryName || "") + 
                                          (modelData.studentName ? " • " + modelData.studentName : "")
                                    font.pixelSize: 12
                                    color: "#888888"
                                    visible: text.length > 0
                                }
                            }
                        }
                    }
                    
                    // Empty state
                    Label {
                        width: parent.width
                        text: "Keine Einträge"
                        font.pixelSize: 18
                        color: "#666666"
                        horizontalAlignment: Text.AlignHCenter
                        visible: !isLoading && entries.length === 0 && !addingNew
                    }
                    
                    Item { width: 1; height: 40 }
                }
            }
            
            BusyIndicator {
                anchors.centerIn: parent
                running: isLoading
                visible: isLoading
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
        }
    }
    
    // ==================== ENTITY SELECT PAGE ====================
    Component {
        id: entitySelectPage
        
        Page {
            id: entitySelectRoot
            orientationLock: PageOrientation.LockPortrait
            
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            property string entityType: "CLASS"
            property string title: "Auswählen"
            property variant entityList: []
            property bool isLoading: true
            property string searchText: ""
            
            Component.onCompleted: {
                backend.classesReady.connect(onClassesReady)
                backend.teachersReady.connect(onTeachersReady)
                backend.roomsReady.connect(onRoomsReady)
                loadEntities()
            }
            
            function loadEntities() {
                isLoading = true
                if (entityType === "CLASS") {
                    backend.getClassesList()
                } else if (entityType === "TEACHER") {
                    backend.getTeachersList()
                } else if (entityType === "ROOM") {
                    backend.getRoomsList()
                }
            }
            
            function onClassesReady(resultJson) {
                if (entityType !== "CLASS") return
                processResult(resultJson)
            }
            
            function onTeachersReady(resultJson) {
                if (entityType !== "TEACHER") return
                processResult(resultJson)
            }
            
            function onRoomsReady(resultJson) {
                if (entityType !== "ROOM") return
                processResult(resultJson)
            }
            
            function processResult(resultJson) {
                isLoading = false
                try {
                    entityList = JSON.parse(resultJson)
                } catch(e) {
                    console.log("Parse error: " + e)
                    entityList = []
                }
            }
            
            function selectEntity(entityId, entityName) {
                console.log("selectEntity: type=" + entityType + ", id=" + entityId + ", name=" + entityName)
                // Go back to timetable and emit signal
                pageStack.pop()
                appWindow.entitySelected(entityType, parseInt(entityId), entityName)
            }
            
            function filteredList() {
                if (!searchText || searchText.length === 0) {
                    return entityList
                }
                var filtered = []
                var search = searchText.toLowerCase()
                for (var i = 0; i < entityList.length; i++) {
                    var item = entityList[i]
                    if (item.name && item.name.toLowerCase().indexOf(search) >= 0) {
                        filtered.push(item)
                    }
                }
                return filtered
            }
            
            // Header
            Rectangle {
                id: selectHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 56
                color: "#111111"
                z: 10
                
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 12
                    
                    // Back button
                    Rectangle {
                        width: 44; height: 44
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 22
                        color: selectBackMA.pressed ? "#333333" : "#222222"
                        
                        Label {
                            anchors.centerIn: parent
                            text: "←"
                            font.pixelSize: 28
                            color: "#ffffff"
                        }
                        
                        MouseArea {
                            id: selectBackMA
                            anchors.fill: parent
                            onClicked: pageStack.pop()
                        }
                    }
                    
                    // Title
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: title
                        font.pixelSize: 24
                        font.bold: true
                        color: "#ffffff"
                    }
                }
            }
            
            // Search field
            Rectangle {
                id: searchBar
                anchors.top: selectHeader.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                height: 44
                radius: 8
                color: "#222222"
                
                TextField {
                    id: searchField
                    anchors.fill: parent
                    anchors.margins: 4
                    placeholderText: "Suchen..."
                    onTextChanged: searchText = text
                }
            }
            
            // Entity list
            ListView {
                anchors.top: searchBar.bottom
                anchors.topMargin: 12
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                clip: true
                spacing: 4
                
                model: filteredList()
                
                delegate: Rectangle {
                    width: parent.width
                    height: 52
                    radius: 8
                    color: entityItemMA.pressed ? "#333333" : "#1a1a1a"
                    
                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name || ""
                        font.pixelSize: 20
                        color: "#ffffff"
                    }
                    
                    MouseArea {
                        id: entityItemMA
                        anchors.fill: parent
                        onClicked: selectEntity(modelData.id, modelData.name)
                    }
                }
            }
            
            // Loading
            BusyIndicator {
                anchors.centerIn: parent
                running: isLoading
                visible: isLoading
                platformStyle: BusyIndicatorStyle { size: "large" }
            }
            
            // Empty state
            Label {
                anchors.centerIn: parent
                text: "Keine Einträge gefunden"
                font.pixelSize: 20
                color: "#666666"
                visible: !isLoading && filteredList().length === 0
            }
        }
    }
    
    // ==================== ABOUT PAGE ====================
    Component {
        id: aboutPage
        
        Page {
            orientationLock: PageOrientation.LockPortrait
            
            // Black background
            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }
            
            tools: ToolBarLayout {
                ToolIcon {
                    iconId: "toolbar-back"
                    onClicked: pageStack.pop()
                }
            }
            
            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentHeight: aboutColumn.height
                
                Column {
                    id: aboutColumn
                    width: parent.width
                    spacing: 20
                    
                    Image {
                        source: "/opt/webuntis/icons/webuntis.png"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 128; height: 128
                        smooth: true
                    }
                    
                    Label {
                        width: parent.width
                        text: "WebUntis"
                        font.pixelSize: 40
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        color: "#ffffff"
                    }
                    
                    Label {
                        width: parent.width
                        text: "Version 1.0.0"
                        font.pixelSize: 24
                        horizontalAlignment: Text.AlignHCenter
                        color: "#aaaaaa"
                    }
                    
                    Label {
                        width: parent.width
                        text: "for MeeGo Harmattan PR1.3"
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        color: "#888888"
                    }
                    
                    Item { width: 1; height: 30 }
                    
                    Label {
                        width: parent.width
                        text: "Ported from Sailfish OS\nharbour-webuntis-secret"
                        font.pixelSize: 22
                        horizontalAlignment: Text.AlignHCenter
                        color: "#aaaaaa"
                        wrapMode: Text.WordWrap
                    }
                    
                    Item { width: 1; height: 20 }
                    
                    Label {
                        width: parent.width
                        text: "Secret-Only Version für Microsoft 365 Schulen. Verwendet TOTP-Authentifizierung."
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        color: "#888888"
                        wrapMode: Text.WordWrap
                    }
                    
                    Item { width: 1; height: 40 }
                    
                    Label {
                        width: parent.width
                        text: "© 2024"
                        font.pixelSize: 18
                        horizontalAlignment: Text.AlignHCenter
                        color: "#aaaaaa"
                    }
                }
            }
        }
    }
}
