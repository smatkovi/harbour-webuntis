import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: lessonDetailPage
    allowedOrientations: Orientation.All
    
    property var lesson: ({})
    
    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge
        
        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium
            
            PageHeader {
                title: lesson.subjects ? lesson.subjects.join(", ") : "Stunde"
            }
            
            // Stundeninfo
            DetailItem {
                label: "Datum"
                value: {
                    if (!lesson.date) return ""
                    var d = new Date(lesson.date)
                    var days = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag']
                    var months = ['Jänner', 'Februar', 'März', 'April', 'Mai', 'Juni', 
                                  'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember']
                    return days[d.getDay()] + ", " + d.getDate() + ". " + months[d.getMonth()] + " " + d.getFullYear()
                }
            }
            
            DetailItem {
                label: "Zeit"
                value: (lesson.start_time || "") + " - " + (lesson.end_time || "")
            }
            
            DetailItem {
                label: "Klasse"
                value: lesson.classes ? lesson.classes.join(", ") : ""
            }
            
            DetailItem {
                label: "Raum"
                value: lesson.rooms ? lesson.rooms.join(", ") : ""
                visible: lesson.rooms && lesson.rooms.length > 0
            }
            
            DetailItem {
                label: "Lehrer"
                value: lesson.teachers ? lesson.teachers.join(", ") : ""
                visible: lesson.teachers && lesson.teachers.length > 0
            }
            
            DetailItem {
                label: "Status"
                value: lesson.code === "cancelled" ? "Entfall" : 
                       lesson.code === "irregular" ? "Verlegung" : "Regulär"
            }
            
            SectionHeader {
                text: "Lehrstoff"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: lesson.lesson_topic || "(Noch kein Stoff eingetragen)"
                color: lesson.lesson_topic ? Theme.primaryColor : Theme.secondaryColor
                wrapMode: Text.WordWrap
                font.italic: !lesson.lesson_topic
            }
            
            SectionHeader {
                text: "Hausübung"
                visible: lesson.homework && lesson.homework.length > 0
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: lesson.homework || ""
                color: Theme.primaryColor
                wrapMode: Text.WordWrap
                visible: lesson.homework && lesson.homework.length > 0
            }
            
            SectionHeader {
                text: "Hinweis"
            }
            
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2*x
                text: "Anwesenheitserfassung und Stoffeintragung sind über die WebUntis API leider nicht möglich. Bitte die WebUntis Webseite verwenden."
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
                font.pixelSize: Theme.fontSizeSmall
            }
        }
        
        VerticalScrollDecorator {}
    }
}
