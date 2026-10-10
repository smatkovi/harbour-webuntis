import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: loginPage
    allowedOrientations: Orientation.All
    
    property bool isLoading: false
    property string errorMessage: ""
    property bool schoolSelected: false
    property string selectedSchoolName: ""
    property string selectedServer: ""
    property string selectedLoginName: ""
    property var searchResults: []
    property string searchHint: ""   // Meldung der Schulsuche, kein Fehler
    
    // Watch for auto-login success from main app
    Connections {
        target: app
        onLoggedInChanged: {
            if (app.loggedIn) {
                console.log("LoginPage: auto-login detected, switching to TimetablePage")
                pageStack.replace(Qt.resolvedUrl("TimetablePage.qml"))
            }
        }
    }
    
    Component.onCompleted: {
        // If already logged in, go to timetable immediately
        if (app.loggedIn) {
            console.log("LoginPage: already logged in, switching to TimetablePage")
            pageStack.replace(Qt.resolvedUrl("TimetablePage.qml"))
        }
    }
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge
        
        PullDownMenu {
            MenuItem {
                text: "Über WebUntis"
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: "Andere Schule wählen"
                visible: schoolSelected
                onClicked: {
                    schoolSelected = false
                    selectedSchoolName = ""
                    selectedServer = ""
                    selectedLoginName = ""
                    searchResults = []
                    searchHint = ""
                    errorMessage = ""
                }
            }
        }
        
        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium
            
            PageHeader {
                title: schoolSelected ? "Anmelden" : "Schule suchen"
                description: "Secret-Only Version"
            }
            
            // === SCHULSUCHE ===
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: !schoolSelected
                
                // Icon
                Image {
                    source: "image://theme/icon-l-people"
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: 0.6
                }
                
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: "WebUntis Klassenbuch"
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: "Für Microsoft 365 Schulen"
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                }
                
                Item { height: Theme.paddingLarge; width: 1 }
                
                SearchField {
                    id: schoolSearchField
                    width: parent.width
                    placeholderText: "Schulname eingeben..."
                    EnterKey.enabled: text.trim().length >= 3
                    EnterKey.iconSource: "image://theme/icon-m-search"
                    EnterKey.onClicked: searchSchool()
                    
                    onTextChanged: {
                        if (text.trim().length >= 3) {
                            searchTimer.restart()
                        } else {
                            searchResults = []
                            searchHint = ""
                        }
                    }
                }
                
                Timer {
                    id: searchTimer
                    interval: 500
                    onTriggered: searchSchool()
                }
                
                // Suchergebnisse
                Repeater {
                    model: searchResults
                    
                    delegate: BackgroundItem {
                        width: parent.width
                        height: schoolItem.height + 2 * Theme.paddingSmall
                        
                        Column {
                            id: schoolItem
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2*x
                            anchors.verticalCenter: parent.verticalCenter
                            
                            Label {
                                width: parent.width
                                text: modelData.displayName
                                color: highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                            }
                            
                            Label {
                                width: parent.width
                                text: modelData.address || ""
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                truncationMode: TruncationMode.Fade
                                visible: text.length > 0
                            }
                        }
                        
                        onClicked: {
                            selectedSchoolName = modelData.displayName
                            selectedServer = modelData.server
                            selectedLoginName = modelData.loginName
                            
                            // Schule im Backend setzen
                            var page = loginPage  // Capture reference
                            python.setSchool(selectedServer, selectedLoginName, function() {
                                page.schoolSelected = true
                                page.searchResults = []
                                page.searchHint = ""
                                page.errorMessage = ""
                            })
                        }
                    }
                }
                
                // === Rueckfall: Adresse von Hand eintragen ===
                Item { height: Theme.paddingLarge; width: 1 }

                SectionHeader { text: "Oder Adresse von Hand" }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: "Wenn die Suche die Schule nicht findet: die WebUntis-Adresse aus dem Browser hier einsetzen."
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.WordWrap
                }

                TextField {
                    id: manualUrlField
                    width: parent.width
                    placeholderText: "xyz.webuntis.com/WebUntis/?school=kennung"
                    label: "WebUntis-Adresse"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhUrlCharactersOnly
                    EnterKey.enabled: text.trim().length > 0
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: manualSchoolField.focus = true
                }

                TextField {
                    id: manualSchoolField
                    width: parent.width
                    placeholderText: "nur nötig, wenn nicht in der Adresse"
                    label: "Schulkennung"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    EnterKey.enabled: manualUrlField.text.trim().length > 0
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: useManualSchool()
                }

                Button {
                    text: "Übernehmen"
                    anchors.horizontalCenter: parent.horizontalCenter
                    enabled: !isLoading && manualUrlField.text.trim().length > 0
                    onClicked: useManualSchool()
                }

                // Info Text
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: searchHint.length > 0
                          ? searchHint
                          : (schoolSearchField.text.trim().length >= 3 && searchResults.length === 0 && !isLoading
                             ? "Keine Schulen gefunden"
                             : "Gib mindestens 3 Zeichen ein um zu suchen")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: searchResults.length === 0 && errorMessage.length === 0
                }
            }
            
            // === LOGIN FORMULAR ===
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: schoolSelected
                
                // Ausgewählte Schule anzeigen
                Rectangle {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    height: schoolInfoColumn.height + 2 * Theme.paddingMedium
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    radius: Theme.paddingSmall
                    
                    Column {
                        id: schoolInfoColumn
                        anchors.centerIn: parent
                        width: parent.width - 2 * Theme.paddingMedium
                        
                        Label {
                            width: parent.width
                            text: selectedSchoolName
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                        
                        Label {
                            width: parent.width
                            text: selectedServer
                            color: Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
                
                Item { height: Theme.paddingMedium; width: 1 }
                
                TextField {
                    id: usernameField
                    width: parent.width
                    placeholderText: "z.B. MATKO"
                    label: "Benutzer (aus QR-Code)"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    EnterKey.enabled: text.length > 0
                    EnterKey.iconSource: "image://theme/icon-m-enter-next"
                    EnterKey.onClicked: secretField.focus = true
                }
                
                TextField {
                    id: secretField
                    width: parent.width
                    placeholderText: "16-stellig (Schlüssel aus QR-Code)"
                    label: "Secret / Schlüssel"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    echoMode: TextInput.Password
                    EnterKey.enabled: text.length >= 16
                    EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                    EnterKey.onClicked: doLogin()
                }
                
                // QR-Code Info
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2*x
                    text: "Benutzer & Secret findest du im QR-Code:\nWebUntis → Profil → Freigaben → Anzeigen"
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
                
                TextSwitch {
                    id: saveCredentials
                    text: "Zugangsdaten speichern"
                    description: "Automatisch einloggen beim nächsten Start"
                    checked: true
                }
                
                Item { height: Theme.paddingLarge; width: 1 }
                
                Button {
                    id: loginButton
                    text: isLoading ? "Verbinde..." : "Anmelden"
                    anchors.horizontalCenter: parent.horizontalCenter
                    enabled: !isLoading && usernameField.text.length > 0 && secretField.text.length >= 16
                    onClicked: doLogin()
                }
            }
            
            // Fehleranzeige
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: errorMessage.length > 0 ? errorMessage : app.pythonError
                color: Theme.errorColor
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: text.length > 0
                font.pixelSize: Theme.fontSizeSmall
            }
            
            // Loading Indicator
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: isLoading
                visible: isLoading
            }
        }
    }
    
    function useManualSchool() {
        var page = loginPage  // Capture reference
        page.errorMessage = ""
        python.parseSchoolUrl(manualUrlField.text, manualSchoolField.text, function(result) {
            if (!result || result.error) {
                page.errorMessage = (result && result.error) ? result.error : "Adresse nicht verstanden"
                return
            }
            page.selectedSchoolName = result.loginName
            page.selectedServer = result.server
            page.selectedLoginName = result.loginName
            python.setSchool(result.server, result.loginName, function() {
                page.schoolSelected = true
                page.searchResults = []
                page.errorMessage = ""
            })
        })
    }

    function searchSchool() {
        var query = schoolSearchField.text.trim()
        if (query.length < 3) return
        
        var page = loginPage  // Capture reference
        page.isLoading = true
        page.errorMessage = ""
        
        python.searchSchools(query, function(result) {
            page.isLoading = false
            
            if (!result) {
                page.searchHint = "Keine Antwort von der Schulsuche"
                page.searchResults = []
            } else if (result.error) {
                // "Zu viele Treffer" ist ein Hinweis beim Tippen, kein Fehler
                page.searchHint = result.error
                page.searchResults = []
            } else if (result.schools) {
                page.searchHint = ""
                page.searchResults = result.schools
            }
        })
    }
    
    function doLogin() {
        var page = loginPage  // Capture reference
        if (page.isLoading) return
        
        var secret = secretField.text.trim()
        
        if (secret.length < 16) {
            page.errorMessage = "Secret muss mindestens 16 Zeichen haben"
            return
        }
        
        page.isLoading = true
        page.errorMessage = ""
        
        python.doLogin(selectedServer, selectedLoginName, usernameField.text, secret, saveCredentials.checked, function(result) {
            page.isLoading = false
            
            if (result === true || (result && result.success)) {
                app.loggedIn = true
                app.username = usernameField.text
                // Load absence reasons
                python.loadAbsenceReasons()
                pageStack.replace(Qt.resolvedUrl("TimetablePage.qml"))
            } else {
                page.errorMessage = (result && result.error) ? result.error : "Login fehlgeschlagen"
            }
        })
    }
}
