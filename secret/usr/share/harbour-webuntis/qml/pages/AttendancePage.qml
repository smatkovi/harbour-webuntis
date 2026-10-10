import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: attendancePage
    allowedOrientations: Orientation.All
    
    property var lesson: ({})
    property var students: []
    property var attendance: ({})  // student_name -> true (anwesend) / false (abwesend)
    property string className: lesson.classes ? lesson.classes[0] : ""
    
    Component.onCompleted: {
        loadStudents()
    }
    
    SilicaListView {
        id: studentList
        anchors.fill: parent
        model: students
        
        header: Column {
            width: parent.width
            spacing: Theme.paddingSmall
            
            PageHeader {
                title: "Anwesenheit"
                description: (lesson.subjects || []).join(", ") + " • " + className
            }
            
            // Statistik
            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingLarge
                
                Label {
                    text: countPresent() + " ✓"
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Label {
                    text: countAbsent() + " ✗"
                    color: Theme.errorColor
                    font.pixelSize: Theme.fontSizeLarge
                }
                Label {
                    text: "von " + students.length
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeLarge
                }
            }
            
            Item { height: Theme.paddingMedium; width: 1 }
        }
        
        PullDownMenu {
            MenuItem {
                text: "Schüler bearbeiten"
                onClicked: pageStack.push(Qt.resolvedUrl("EditStudentsPage.qml"), {
                    className: className,
                    onSaved: function() { loadStudents() }
                })
            }
            MenuItem {
                text: "Alle anwesend"
                onClicked: {
                    for (var i = 0; i < students.length; i++) {
                        attendance[students[i]] = true
                    }
                    attendanceChanged()
                }
            }
            MenuItem {
                text: "Zusammenfassung"
                onClicked: showSummary()
            }
        }
        
        delegate: ListItem {
            id: studentItem
            contentHeight: Theme.itemSizeMedium
            
            property string studentName: modelData
            property bool isPresent: attendance[studentName] !== false  // Default: anwesend
            
            onClicked: {
                attendance[studentName] = !isPresent
                attendanceChanged()
            }
            
            Row {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.paddingMedium
                width: parent.width - 2*x
                
                // Status Icon
                Label {
                    text: isPresent ? "✓" : "✗"
                    font.pixelSize: Theme.fontSizeLarge
                    color: isPresent ? Theme.highlightColor : Theme.errorColor
                    width: Theme.iconSizeMedium
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                // Name
                Label {
                    text: studentName
                    color: isPresent ? Theme.primaryColor : Theme.errorColor
                    font.pixelSize: Theme.fontSizeMedium
                    font.strikeout: !isPresent
                    anchors.verticalCenter: parent.verticalCenter
                    truncationMode: TruncationMode.Fade
                    width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium
                }
            }
        }
        
        ViewPlaceholder {
            enabled: students.length === 0
            text: "Keine Schüler"
            hintText: "Ziehen und 'Schüler bearbeiten' wählen"
        }
        
        VerticalScrollDecorator {}
    }
    
    // Signal für UI-Update
    signal attendanceChanged()
    onAttendanceChanged: {
        studentList.model = []
        studentList.model = students
    }
    
    function loadStudents() {
        python.call('webuntis_backend.load_students', [className], function(result) {
            if (result && result.length > 0) {
                students = result
                // Alle als anwesend initialisieren
                for (var i = 0; i < students.length; i++) {
                    if (attendance[students[i]] === undefined) {
                        attendance[students[i]] = true
                    }
                }
            } else {
                students = []
            }
        })
    }
    
    function countPresent() {
        var count = 0
        for (var i = 0; i < students.length; i++) {
            if (attendance[students[i]] !== false) count++
        }
        return count
    }
    
    function countAbsent() {
        return students.length - countPresent()
    }
    
    function showSummary() {
        var absent = []
        for (var i = 0; i < students.length; i++) {
            if (attendance[students[i]] === false) {
                absent.push(students[i])
            }
        }
        
        var msg = "Anwesend: " + countPresent() + " von " + students.length + "\n\n"
        if (absent.length > 0) {
            msg += "Fehlend:\n• " + absent.join("\n• ")
        } else {
            msg += "Alle anwesend! 🎉"
        }
        
        pageStack.push(Qt.resolvedUrl("InfoPage.qml"), {
            title: "Zusammenfassung",
            message: msg
        })
    }
}
